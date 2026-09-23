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


# Split candidates into those that can enter a model on `data` (already
# complete-cased by the caller) and those that cannot — a factor with < 2
# observed levels, or a constant numeric. Returns list(keep, excluded) where
# `excluded` is a data.frame(variable, reason).
.partition_modelable <- function(data, candidates) {
  reasons <- vapply(candidates, function(v) {
    x <- data[[v]]
    n_distinct <- length(unique(x[!is.na(x)]))
    if (n_distinct >= 2L) return(NA_character_)
    if (is.numeric(x)) "no variation after removing missing values"
    else "only 1 level after removing missing values"
  }, character(1), USE.NAMES = FALSE)

  list(
    keep     = candidates[is.na(reasons)],
    excluded = data.frame(
      variable         = candidates[!is.na(reasons)],
      reason           = reasons[!is.na(reasons)],
      stringsAsFactors = FALSE
    )
  )
}

# Drop unobserved levels from the factor columns in `vars`, so that empty
# levels do not become all-zero dummy columns.
.droplevels_cols <- function(data, vars) {
  for (v in intersect(vars, names(data))) {
    if (is.factor(data[[v]])) data[[v]] <- droplevels(data[[v]])
  }
  data
}

# Shared prep for stepwise / LASSO, which listwise-delete across the whole
# candidate pool. Excludes candidates that cannot be modelled on the surviving
# rows. Returns list(data, keep, error, run_info); `run_info` (excluded
# variables, rows used, rows total) is appended to every result, success or
# failure, so the UI can explain what was dropped.
.prepare_selection_data <- function(data, data_cc, candidates) {
  part     <- .partition_modelable(data_cc, candidates)
  run_info <- list(
    excluded_variables = part$excluded,
    n_used             = nrow(data_cc),
    n_total            = nrow(data)
  )

  error <- if (nrow(data_cc) == 0L) {
    "No rows are complete across the outcome and all candidate variables."
  } else if (length(part$keep) == 0L) {
    "None of the candidate variables can be modelled on the complete rows."
  }

  list(
    data     = .droplevels_cols(data_cc, part$keep),
    keep     = part$keep,
    error    = error,
    run_info = run_info
  )
}

# The exposure, when one is assigned and present in `data` — else
# character(0). Stepwise and LASSO hold it in every model so that covariates
# are chosen for what they add alongside the exposure, which is how the final
# model uses them (a confounder matters because of its link to the exposure).
.held_exposure <- function(roles, data) {
  exposure <- roles$exposure_variable
  if (is.null(exposure) || !nzchar(exposure) || !exposure %in% names(data)) {
    return(character(0))
  }
  exposure
}

# Error message when the held exposure cannot be modelled on the complete
# rows, else NULL.
.held_exposure_error <- function(data_cc, exposure) {
  if (length(exposure) == 0L || nrow(data_cc) == 0L) return(NULL)
  bad <- .partition_modelable(data_cc, exposure)$excluded
  if (nrow(bad) == 0L) return(NULL)
  sprintf("The exposure (%s) has %s.", exposure, bad$reason[1])
}


#' Run univariable regression screen
#'
#' Fits one \code{lm} (continuous outcome) or \code{glm} (binary outcome)
#' per candidate variable. Returns a tidy tibble, exposure first, then
#' candidates in dataset column order.
#'
#' @param data A \code{data.frame} (the frozen analysis dataset).
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A \code{tibble} with columns \code{variable}, \code{term},
#'   \code{estimate}, \code{conf.low}, \code{conf.high}, \code{p.value},
#'   \code{reference_level}, \code{effect_measure}, and \code{suggested}
#'   (logical: p < threshold). For a binary outcome \code{estimate} and the
#'   CI are odds ratios (\code{effect_measure = "odds_ratio"}); for a
#'   continuous outcome they are raw coefficients
#'   (\code{effect_measure = "coefficient"}). Candidates that cannot be
#'   modelled (single-level factor, constant numeric, or a failed fit) are
#'   omitted and listed in \code{attr(result, "excluded_variables")}, a
#'   \code{data.frame(variable, reason)}; if every candidate is excluded the
#'   tibble has zero rows. Returns \code{NULL} when no candidates or no
#'   outcome are assigned.
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

  # Each candidate yields either tidy rows or an exclusion reason
  .skip <- function(cand, reason) {
    list(tidy = NULL,
         excluded = data.frame(variable = cand, reason = reason,
                               stringsAsFactors = FALSE))
  }

  results <- lapply(candidates, function(cand) {
    if (!cand %in% names(data)) return(.skip(cand, "not in the analysis dataset"))

    cc <- compute_complete_cases(data, c(outcome, cand))$data
    if (nrow(cc) == 0L) return(.skip(cand, "no complete rows with the outcome"))

    part <- .partition_modelable(cc, cand)
    if (nrow(part$excluded) > 0L) return(.skip(cand, part$excluded$reason))

    tryCatch({
      cc   <- .droplevels_cols(cc, cand)
      fmla <- stats::as.formula(paste(outcome, "~", cand))

      fit <- if (is_binary) {
        stats::glm(fmla, data = cc, family = stats::binomial())
      } else {
        stats::lm(fmla, data = cc)
      }

      # Same estimates / CIs / p-values as every other model in the app;
      # estimate and CI are on the reporting scale (OR for logistic).
      ct <- edark_coef_table(fit, cc)
      tidy_res <- tibble::tibble(
        term      = ct$term,
        estimate  = ct$effect,
        conf.low  = ct$effect.low,
        conf.high = ct$effect.high,
        p.value   = ct$p.value
      )

      list(tidy = tidy_res %>%
             dplyr::filter(.data$term != "(Intercept)") %>%
             dplyr::mutate(variable = cand),
           excluded = NULL)
    }, error = function(e) .skip(cand, paste("model failed:", conditionMessage(e))))
  })

  excluded <- dplyr::bind_rows(lapply(results, `[[`, "excluded"))
  if (nrow(excluded) == 0L) {
    excluded <- data.frame(variable = character(0), reason = character(0),
                           stringsAsFactors = FALSE)
  }

  tidy_all <- dplyr::bind_rows(lapply(results, `[[`, "tidy"))
  if (nrow(tidy_all) == 0L) {
    empty <- tibble::tibble(
      variable = character(0), term = character(0), estimate = numeric(0),
      conf.low = numeric(0), conf.high = numeric(0), p.value = numeric(0),
      reference_level = character(0), effect_measure = character(0),
      suggested = logical(0)
    )
    attr(empty, "excluded_variables") <- excluded
    return(empty)
  }

  exposure     <- roles$exposure_variable
  cand_ordered <- intersect(names(data), candidates)
  if (!is.null(exposure) && nzchar(exposure) && exposure %in% cand_ordered)
    cand_ordered <- c(exposure, setdiff(cand_ordered, exposure))
  var_order <- stats::setNames(seq_along(cand_ordered), cand_ordered)

  ref_levels <- if (!is.null(roles$reference_levels)) roles$reference_levels else list()

  out <- tidy_all %>%
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
      effect_measure  = if (is_binary) "odds_ratio" else "coefficient",
      suggested = !is.na(.data$p.value) & .data$p.value < threshold
    ) %>%
    dplyr::arrange(.data$.var_rank, .data$term) %>%
    dplyr::select(-.data$.var_rank)

  attr(out, "excluded_variables") <- excluded
  out
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
          type  = "Cram\u00e9r's V",
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
#' When an exposure is assigned it is held in every model (the lower bound of
#' the search scope) and never offered for selection.
#'
#' @param data A \code{data.frame}.
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A named list: \code{selected_variables}, \code{held_variables}
#'   (the exposure, or empty), \code{direction}, \code{criterion},
#'   \code{final_formula}, \code{step_trace}, plus
#'   \code{excluded_variables} (\code{data.frame(variable, reason)} of
#'   candidates that could not be modelled on the complete rows),
#'   \code{n_used} and \code{n_total}. On a fit error, \code{error} holds the
#'   message and \code{selected_variables} is empty. Returns \code{NULL} when
#'   no outcome or candidates are assigned.
#' @export
run_stepwise <- function(data, spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  candidates <- roles$univariable_test_pool
  vsel       <- spec$variable_selection_specification
  direction  <- if (!is.null(vsel$stepwise_direction)) vsel$stepwise_direction else "backward"
  criterion  <- if (!is.null(vsel$stepwise_criterion)) vsel$stepwise_criterion else "BIC"

  if (is.null(outcome) || is.null(candidates) || length(candidates) == 0L) return(NULL)

  exposure <- .held_exposure(roles, data)
  cc       <- compute_complete_cases(data, c(outcome, exposure, candidates))
  data_cc  <- apply_reference_levels(cc$data, roles$reference_levels)

  cands_present <- setdiff(intersect(candidates, names(data_cc)), exposure)
  if (length(cands_present) == 0L) return(NULL)

  prep <- .prepare_selection_data(data, data_cc, cands_present)
  .fail <- function(msg) {
    c(list(selected_variables = character(0), held_variables = exposure,
           direction = direction, criterion = criterion, final_formula = NULL,
           error = msg),
      prep$run_info)
  }
  if (!is.null(prep$error)) return(.fail(prep$error))
  exp_err <- .held_exposure_error(prep$data, exposure)
  if (!is.null(exp_err)) return(.fail(exp_err))
  cands_present <- prep$keep
  data_cc       <- .droplevels_cols(prep$data, exposure)

  out_col   <- data_cc[[outcome]]
  is_binary <- is.factor(out_col) && length(levels(droplevels(out_col))) == 2L
  n         <- nrow(data_cc)
  k         <- if (criterion == "BIC") log(n) else 2

  # Scope: the exposure (if any) is the floor, the full candidate set the ceiling
  lower_rhs <- if (length(exposure) > 0L) exposure else "1"
  full_fmla <- stats::as.formula(
    paste(outcome, "~", paste(c(exposure, cands_present), collapse = " + "))
  )
  null_fmla <- stats::as.formula(paste(outcome, "~", lower_rhs))
  scope     <- list(lower = stats::as.formula(paste("~", lower_rhs)),
                    upper = stats::as.formula(
                      paste("~", paste(c(exposure, cands_present), collapse = " + "))))

  .fit <- function(fmla) {
    if (is_binary) stats::glm(fmla, data = data_cc, family = stats::binomial())
    else stats::lm(fmla, data = data_cc)
  }

  tryCatch({
    start_fit    <- .fit(if (direction == "backward") full_fmla else null_fmla)
    selected_fit <- stats::step(start_fit, scope = scope, direction = direction,
                                k = k, trace = 0)

    # term.labels are the variable names themselves (not dummy columns)
    selected_terms <- attr(stats::terms(selected_fit), "term.labels")
    selected_vars  <- intersect(cands_present, selected_terms)

    c(list(
      selected_variables = selected_vars,
      held_variables     = exposure,
      direction          = direction,
      criterion          = criterion,
      final_formula      = stats::formula(selected_fit),
      step_trace         = selected_fit$anova
    ), prep$run_info)
  }, error = function(e) .fail(conditionMessage(e)))
}


#' Random seed for LASSO cross-validation
#'
#' Reads \code{variable_selection_specification$lasso_seed}, falling back to
#' the default when it is missing or not a positive whole number.
#'
#' @param spec An \code{analysis_spec} list.
#' @return A single integer.
#' @export
lasso_seed <- function(spec) {
  x <- suppressWarnings(as.integer(spec$variable_selection_specification$lasso_seed))
  if (length(x) != 1L || is.na(x) || x < 1L) .default_variable_selection_specification()$lasso_seed else x
}


#' Run LASSO variable selection
#'
#' Applies \code{glmnet::cv.glmnet} with alpha = 1 (LASSO). Factor variables
#' are expanded via \code{model.matrix()}; a factor is included in the
#' suggested list if any of its dummies has a non-zero coefficient. When an
#' exposure is assigned its columns get \code{penalty.factor = 0}, so it is
#' never shrunk out and never offered for selection. The cross-validation
#' folds are random; they are drawn with \code{\link{lasso_seed}(spec)} and the
#' session's random stream is left as it was.
#'
#' @param data A \code{data.frame}.
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#'
#' @return A named list: \code{selected_variables}, \code{held_variables}
#'   (the exposure, or empty), \code{lambda_type},
#'   \code{lambda_selected}, \code{seed}, \code{coef_data}, \code{cv_fit}, plus
#'   \code{excluded_variables}, \code{n_used} and \code{n_total} (as for
#'   \code{\link{run_stepwise}}). On a fit error, \code{error} holds the
#'   message. Returns \code{NULL} when no outcome or candidates are assigned.
#' @export
run_lasso <- function(data, spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  candidates <- roles$univariable_test_pool
  vsel       <- spec$variable_selection_specification
  lambda_sel <- if (!is.null(vsel$lasso_lambda)) vsel$lasso_lambda else "lambda.1se"
  seed       <- lasso_seed(spec)

  if (is.null(outcome) || is.null(candidates) || length(candidates) == 0L) return(NULL)

  exposure <- .held_exposure(roles, data)
  cc       <- compute_complete_cases(data, c(outcome, exposure, candidates))
  data_cc  <- apply_reference_levels(cc$data, roles$reference_levels)

  cands_present <- setdiff(intersect(candidates, names(data_cc)), exposure)
  if (length(cands_present) == 0L) return(NULL)

  prep <- .prepare_selection_data(data, data_cc, cands_present)
  .fail <- function(msg) {
    c(list(selected_variables = character(0), held_variables = exposure,
           lambda_type = lambda_sel, lambda_selected = NULL, seed = seed,
           coef_data = NULL, cv_fit = NULL, error = msg),
      prep$run_info)
  }
  if (!is.null(prep$error)) return(.fail(prep$error))
  exp_err <- .held_exposure_error(prep$data, exposure)
  if (!is.null(exp_err)) return(.fail(exp_err))
  cands_present <- prep$keep
  data_cc       <- .droplevels_cols(prep$data, exposure)

  out_col   <- data_cc[[outcome]]
  is_binary <- is.factor(out_col) && length(levels(droplevels(out_col))) == 2L
  family    <- if (is_binary) "binomial" else "gaussian"

  tryCatch({
    x_vars <- c(exposure, cands_present)
    x_fmla <- stats::as.formula(paste("~", paste(x_vars, collapse = " + ")))
    mm     <- stats::model.matrix(x_fmla, data = data_cc)
    # Variable behind each (dummy) column, from model.matrix's term index
    col_var <- x_vars[attr(mm, "assign")[-1L]]
    x      <- mm[, -1L, drop = FALSE]
    y      <- if (is_binary) as.numeric(out_col) - 1L else as.numeric(out_col)

    # Exposure columns are unpenalised: always in the model, never selected
    pf <- ifelse(col_var %in% exposure, 0, 1)

    # Folds are random: fix them with the seed so a run can be reproduced
    cv_fit <- .with_seed(seed, glmnet::cv.glmnet(x, y, family = family, alpha = 1,
                                                 nfolds = 10, penalty.factor = pf))

    chosen_lambda <- if (lambda_sel == "lambda.min") cv_fit$lambda.min else cv_fit$lambda.1se

    coefs <- glmnet::coef.glmnet(cv_fit$glmnet.fit, s = chosen_lambda)

    coef_df <- data.frame(
      term     = rownames(coefs)[-1L],
      variable = col_var,
      estimate = as.numeric(coefs)[-1L],
      stringsAsFactors = FALSE
    ) %>%
      dplyr::filter(.data$estimate != 0, !.data$variable %in% exposure)

    # A factor is selected if any of its dummies is non-zero
    selected_vars <- intersect(cands_present, coef_df$variable)

    c(list(
      selected_variables = selected_vars,
      held_variables     = exposure,
      lambda_type        = lambda_sel,
      lambda_selected    = chosen_lambda,
      seed               = seed,
      coef_data          = coef_df,
      cv_fit             = cv_fit
    ), prep$run_info)
  }, error = function(e) .fail(conditionMessage(e)))
}
