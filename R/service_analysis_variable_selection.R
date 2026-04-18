#' Analysis Variable Selection Service
#'
#' Implements the three variable selection methods used in Step 3:
#' univariable outcome regression screen (one lm/glm per candidate),
#' backward/forward stepwise selection (stats::step), and LASSO penalized
#' regression (glmnet::cv.glmnet). All methods are advisory.
#' See PRD §7.6–7.8 and §9.
#'
#' @importFrom magrittr %>%
#'
#' @name service_analysis_variable_selection
NULL


#' Run univariable regression screen
#'
#' Fits one \code{lm} (continuous outcome) or \code{glm} (binary outcome)
#' per candidate variable. Returns a tidy tibble sorted by p-value.
#'
#' @param data A \code{data.frame} (the frozen analysis dataset).
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A \code{tibble} with columns \code{variable}, \code{term},
#'   \code{estimate}, \code{conf.low}, \code{conf.high}, \code{p.value},
#'   \code{suggested} (logical: p < threshold). Returns \code{NULL} when no
#'   candidates or no outcome are assigned.
#' @export
run_univariable_screen <- function(data, spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  candidates <- roles$univariable_test_pool
  threshold  <- spec$variable_selection_specification$univariable_p_threshold
  if (is.null(threshold)) threshold <- 0.2

  if (is.null(outcome) || !nzchar(outcome)) return(NULL)
  if (is.null(candidates) || length(candidates) == 0L) return(NULL)

  data <- apply_reference_levels(data, roles$reference_levels)

  out_col   <- data[[outcome]]
  is_binary <- is.factor(out_col) && length(levels(droplevels(out_col))) == 2L

  results <- lapply(candidates, function(cand) {
    if (!cand %in% names(data)) return(NULL)

    cc <- compute_complete_cases(data, c(outcome, cand))$data
    if (nrow(cc) == 0L) return(NULL)

    tryCatch({
      fmla <- stats::as.formula(paste(outcome, "~", cand))

      if (is_binary) {
        fit      <- stats::glm(fmla, data = cc, family = stats::binomial())
        tidy_res <- broom::tidy(fit, conf.int = TRUE, exponentiate = FALSE)
      } else {
        fit      <- stats::lm(fmla, data = cc)
        tidy_res <- broom::tidy(fit, conf.int = TRUE)
      }

      tidy_res %>%
        dplyr::filter(.data$term != "(Intercept)") %>%
        dplyr::mutate(variable = cand)
    }, error = function(e) NULL)
  })

  tidy_all <- dplyr::bind_rows(Filter(Negate(is.null), results))
  if (nrow(tidy_all) == 0L) return(NULL)

  exposure     <- roles$exposure_variable
  cand_ordered <- intersect(names(data), candidates)
  if (!is.null(exposure) && nzchar(exposure) && exposure %in% cand_ordered)
    cand_ordered <- c(exposure, setdiff(cand_ordered, exposure))
  var_order <- stats::setNames(seq_along(cand_ordered), cand_ordered)

  ref_levels <- if (!is.null(roles$reference_levels)) roles$reference_levels else list()

  tidy_all %>%
    dplyr::select(
      variable, term,
      estimate,
      conf.low  = dplyr::any_of("conf.low"),
      conf.high = dplyr::any_of("conf.high"),
      p.value
    ) %>%
    dplyr::mutate(
      .var_rank       = var_order[.data$variable],
      reference_level = vapply(.data$variable, function(v) {
        if (v %in% names(ref_levels)) as.character(ref_levels[[v]]) else NA_character_
      }, character(1L)),
      suggested = .data$p.value < threshold
    ) %>%
    dplyr::arrange(.data$.var_rank, .data$term) %>%
    dplyr::select(-.data$.var_rank)
}


#' Compute collinearity metrics for candidate variables
#'
#' Computes Pearson correlations for numeric candidates and Cramér's V for
#' factor candidates. Returns both matrices and a flagged-pairs table for
#' pairs exceeding the 0.7 threshold.
#'
#' @param data A \code{data.frame}.
#' @param candidates Character vector of candidate variable names.
#'
#' @return A named list: \code{cor_matrix} (or \code{NULL}),
#'   \code{cramers_v_matrix} (or \code{NULL}), \code{flagged_pairs} tibble,
#'   \code{num_vars}, \code{fac_vars}.
#' @export
compute_collinearity <- function(data, candidates) {
  if (is.null(candidates) || length(candidates) == 0L) return(NULL)

  cand_data <- data[, intersect(candidates, names(data)), drop = FALSE]

  num_vars <- names(cand_data)[vapply(cand_data, is.numeric, logical(1))]
  fac_vars <- names(cand_data)[vapply(cand_data, is.factor,  logical(1))]

  # Pearson correlation for numerics
  cor_mat <- NULL
  if (length(num_vars) >= 2L) {
    cor_mat <- tryCatch(
      stats::cor(cand_data[, num_vars, drop = FALSE], use = "pairwise.complete.obs"),
      error = function(e) NULL
    )
  }

  # Cramér's V for factors
  cramers_v_mat <- NULL
  if (length(fac_vars) >= 2L) {
    v_mat <- matrix(
      NA_real_,
      nrow     = length(fac_vars),
      ncol     = length(fac_vars),
      dimnames = list(fac_vars, fac_vars)
    )
    diag(v_mat) <- 1

    for (i in seq_along(fac_vars)) {
      if (i >= length(fac_vars)) next
      for (j in (i + 1L):length(fac_vars)) {
        v <- tryCatch({
          tbl   <- table(cand_data[[fac_vars[i]]], cand_data[[fac_vars[j]]])
          chi   <- suppressWarnings(chisq.test(tbl, correct = FALSE))
          n     <- sum(tbl)
          k     <- min(nrow(tbl), ncol(tbl))
          if (k <= 1L || n == 0L) NA_real_ else sqrt(chi$statistic / (n * (k - 1L)))
        }, error = function(e) NA_real_)
        v_mat[i, j] <- v_mat[j, i] <- as.numeric(v)
      }
    }
    cramers_v_mat <- v_mat
  }

  # Build flagged pairs table
  flagged <- list()

  if (!is.null(cor_mat)) {
    idx <- which(upper.tri(cor_mat), arr.ind = TRUE)
    for (k in seq_len(nrow(idx))) {
      r <- cor_mat[idx[k, 1], idx[k, 2]]
      if (!is.na(r) && abs(r) > 0.7) {
        flagged[[length(flagged) + 1L]] <- data.frame(
          var1  = rownames(cor_mat)[idx[k, 1]],
          var2  = colnames(cor_mat)[idx[k, 2]],
          type  = "Pearson r",
          value = round(r, 3L),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (!is.null(cramers_v_mat)) {
    idx <- which(upper.tri(cramers_v_mat), arr.ind = TRUE)
    for (k in seq_len(nrow(idx))) {
      v <- cramers_v_mat[idx[k, 1], idx[k, 2]]
      if (!is.na(v) && v > 0.7) {
        flagged[[length(flagged) + 1L]] <- data.frame(
          var1  = rownames(cramers_v_mat)[idx[k, 1]],
          var2  = colnames(cramers_v_mat)[idx[k, 2]],
          type  = "Cramér's V",
          value = round(v, 3L),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  flagged_df <- if (length(flagged) > 0L) {
    dplyr::bind_rows(flagged)
  } else {
    data.frame(var1 = character(), var2 = character(),
               type = character(), value = numeric(),
               stringsAsFactors = FALSE)
  }

  list(
    cor_matrix    = cor_mat,
    cramers_v_mat = cramers_v_mat,
    flagged_pairs = flagged_df,
    num_vars      = num_vars,
    fac_vars      = fac_vars
  )
}


#' Run stepwise variable selection
#'
#' Applies \code{stats::step()} using backward or forward direction with BIC
#' or AIC criterion. Uses the candidate pool from \code{univariable_test_pool}.
#'
#' @param data A \code{data.frame}.
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A named list: \code{selected_variables}, \code{direction},
#'   \code{criterion}, \code{final_formula}. Returns \code{NULL} on failure.
#' @export
run_stepwise <- function(data, spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  candidates <- roles$univariable_test_pool
  vsel       <- spec$variable_selection_specification
  direction  <- if (!is.null(vsel$stepwise_direction)) vsel$stepwise_direction else "backward"
  criterion  <- if (!is.null(vsel$stepwise_criterion)) vsel$stepwise_criterion else "BIC"

  if (is.null(outcome) || is.null(candidates) || length(candidates) == 0L) return(NULL)

  cc      <- compute_complete_cases(data, c(outcome, candidates))
  data_cc <- apply_reference_levels(cc$data, roles$reference_levels)

  cands_present <- intersect(candidates, names(data_cc))
  if (length(cands_present) == 0L) return(NULL)

  out_col   <- data_cc[[outcome]]
  is_binary <- is.factor(out_col) && length(levels(droplevels(out_col))) == 2L
  n         <- nrow(data_cc)
  k         <- if (criterion == "BIC") log(n) else 2

  full_fmla <- stats::as.formula(
    paste(outcome, "~", paste(cands_present, collapse = " + "))
  )
  null_fmla <- stats::as.formula(paste(outcome, "~ 1"))

  tryCatch({
    if (is_binary) {
      full_fit <- stats::glm(full_fmla, data = data_cc, family = stats::binomial())
    } else {
      full_fit <- stats::lm(full_fmla, data = data_cc)
    }

    if (direction == "backward") {
      selected_fit <- stats::step(full_fit, direction = "backward", k = k, trace = 0)
    } else {
      if (is_binary) {
        null_fit <- stats::glm(null_fmla, data = data_cc, family = stats::binomial())
      } else {
        null_fit <- stats::lm(null_fmla, data = data_cc)
      }
      selected_fit <- stats::step(
        null_fit,
        scope     = list(lower = null_fmla, upper = full_fmla),
        direction = "forward",
        k         = k,
        trace     = 0
      )
    }

    selected_terms <- attr(stats::terms(selected_fit), "term.labels")
    # Map terms back to original variable names (handles factor dummy expansion)
    selected_vars <- unique(unlist(lapply(selected_terms, function(t) {
      matches <- cands_present[vapply(cands_present,
        function(cv) startsWith(t, cv), logical(1))]
      if (length(matches) > 0L) matches[1L] else t
    })))

    list(
      selected_variables = selected_vars,
      direction          = direction,
      criterion          = criterion,
      final_formula      = stats::formula(selected_fit),
      step_trace         = selected_fit$anova
    )
  }, error = function(e) {
    list(
      selected_variables = character(0),
      direction          = direction,
      criterion          = criterion,
      final_formula      = NULL,
      error              = conditionMessage(e)
    )
  })
}


#' Run LASSO variable selection
#'
#' Applies \code{glmnet::cv.glmnet} with alpha = 1 (LASSO). Factor variables
#' are expanded via \code{model.matrix()}; a factor is included in the
#' suggested list if any of its dummies has a non-zero coefficient.
#'
#' @param data A \code{data.frame}.
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A named list: \code{selected_variables}, \code{lambda_type},
#'   \code{lambda_selected}, \code{coef_data}, \code{cv_fit}.
#'   Returns \code{NULL} on failure.
#' @export
run_lasso <- function(data, spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  candidates <- roles$univariable_test_pool
  vsel       <- spec$variable_selection_specification
  lambda_sel <- if (!is.null(vsel$lasso_lambda)) vsel$lasso_lambda else "lambda.1se"

  if (is.null(outcome) || is.null(candidates) || length(candidates) == 0L) return(NULL)

  cc      <- compute_complete_cases(data, c(outcome, candidates))
  data_cc <- apply_reference_levels(cc$data, roles$reference_levels)

  cands_present <- intersect(candidates, names(data_cc))
  if (length(cands_present) == 0L) return(NULL)

  out_col   <- data_cc[[outcome]]
  is_binary <- is.factor(out_col) && length(levels(droplevels(out_col))) == 2L
  family    <- if (is_binary) "binomial" else "gaussian"

  tryCatch({
    x_fmla <- stats::as.formula(paste("~", paste(cands_present, collapse = " + ")))
    x      <- stats::model.matrix(x_fmla, data = data_cc)[, -1L, drop = FALSE]
    y      <- if (is_binary) as.numeric(out_col) - 1L else as.numeric(out_col)

    cv_fit <- glmnet::cv.glmnet(x, y, family = family, alpha = 1, nfolds = 10)

    chosen_lambda <- if (lambda_sel == "lambda.min") cv_fit$lambda.min else cv_fit$lambda.1se

    coefs    <- glmnet::coef.glmnet(cv_fit$glmnet.fit, s = chosen_lambda)
    coef_vec <- as.numeric(coefs)
    terms    <- rownames(coefs)

    coef_df <- data.frame(
      term     = terms,
      estimate = coef_vec,
      stringsAsFactors = FALSE
    ) %>%
      dplyr::filter(.data$term != "(Intercept)", .data$estimate != 0)

    # Map non-zero dummies back to original variable names
    selected_vars <- if (nrow(coef_df) > 0L) {
      unique(unlist(lapply(coef_df$term, function(t) {
        matches <- cands_present[vapply(cands_present,
          function(cv) startsWith(t, cv), logical(1))]
        if (length(matches) > 0L) matches[1L] else t
      })))
    } else {
      character(0)
    }

    list(
      selected_variables = selected_vars,
      lambda_type        = lambda_sel,
      lambda_selected    = chosen_lambda,
      coef_data          = coef_df,
      cv_fit             = cv_fit
    )
  }, error = function(e) {
    list(
      selected_variables = character(0),
      lambda_type        = lambda_sel,
      lambda_selected    = NULL,
      coef_data          = NULL,
      cv_fit             = NULL,
      error              = conditionMessage(e)
    )
  })
}
