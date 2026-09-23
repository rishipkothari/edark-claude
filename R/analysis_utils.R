#' Analysis Utilities
#'
#' Shared helper functions used across all Analysis module service files:
#' formula assembly, reference level application, and complete-case
#' subsetting. These are pure functions — no Shiny reactivity.
#'
#' @importFrom magrittr %>%
#'
#' @name analysis_utils
NULL


#' Build the model formula from an \code{analysis_spec}
#'
#' Assembles an R \code{formula} object from the variable roles and model
#' design stored in \code{analysis_spec}. The outcome is placed on the
#' left-hand side; the exposure (if assigned) is first on the right-hand
#' side, followed by the confirmed covariates (deduped). For mixed models,
#' one random intercept \code{(1 | cluster)} is appended per cluster variable.
#'
#' @param spec A named list conforming to the \code{analysis_spec} structure
#'   (see PRD §3.5).
#'
#' @return A \code{formula} object.
#' @export
build_analysis_formula <- function(spec) {
  roles      <- spec$variable_roles
  outcome    <- roles$outcome_variable
  exposure   <- roles$exposure_variable
  covariates <- roles$final_model_covariates
  clusters   <- roles$cluster_variables
  model_type <- spec$model_design$model_type

  if (is.null(outcome) || !nzchar(outcome)) {
    stop("build_analysis_formula: no outcome variable in spec.")
  }

  # Fixed-effect predictors: exposure first, then remaining covariates
  preds <- unique(c(exposure, covariates))
  preds <- preds[!vapply(preds, is.null, logical(1))]
  preds <- preds[nzchar(preds)]

  rhs <- if (length(preds) == 0) "1" else paste(preds, collapse = " + ")

  # Random intercepts for mixed models — one per cluster variable
  if (!is.null(model_type) && model_type %in% c("linear_mixed", "logistic_mixed")) {
    clusters <- clusters[nzchar(clusters)]
    if (length(clusters) > 0L) {
      rhs <- paste(rhs, "+", paste0("(1 | ", clusters, ")", collapse = " + "))
    }
  }

  stats::as.formula(paste(outcome, "~", rhs))
}


#' Apply reference level overrides to factor columns
#'
#' Calls \code{stats::relevel()} on each factor column named in
#' \code{reference_levels}. Silently skips columns that are absent from
#' \code{data} or whose specified reference level is not a current level.
#'
#' @param data A \code{data.frame}.
#' @param reference_levels A named list: \code{variable_name -> reference_level}
#'   (from \code{analysis_spec$variable_roles$reference_levels}).
#'
#' @return The modified \code{data.frame}.
#' @export
apply_reference_levels <- function(data, reference_levels) {
  if (is.null(reference_levels) || length(reference_levels) == 0) return(data)

  for (var_name in names(reference_levels)) {
    ref <- reference_levels[[var_name]]
    if (!var_name %in% names(data)) next
    col <- data[[var_name]]
    if (!is.factor(col)) next
    if (is.ordered(col)) next
    if (!ref %in% levels(col)) next
    data[[var_name]] <- stats::relevel(col, ref = ref)
  }
  data
}


#' Compute complete cases for a set of variables
#'
#' Filters \code{data} to rows that are complete (non-\code{NA}) across all
#' \code{variables} that exist in \code{data}. Returns the filtered data and
#' the number of excluded rows.
#'
#' @param data A \code{data.frame}.
#' @param variables Character vector of column names to include in the
#'   completeness check.
#'
#' @return A named list:
#'   \describe{
#'     \item{data}{The complete-case \code{data.frame}.}
#'     \item{n_excluded}{Integer. Number of rows removed.}
#'   }
#' @export
compute_complete_cases <- function(data, variables) {
  vars_present <- intersect(variables, names(data))

  if (length(vars_present) == 0) {
    return(list(data = data, n_excluded = 0L))
  }

  complete_idx <- stats::complete.cases(data[, vars_present, drop = FALSE])
  n_excluded   <- sum(!complete_idx)

  list(
    data       = data[complete_idx, , drop = FALSE],
    n_excluded = n_excluded
  )
}


#' The train/test split a spec asks for
#'
#' A split applies only when the model purpose is \code{"prediction"}, the
#' validation method is \code{"split"} (a held-out test set) and a variable
#' and a training level are chosen (PRD §A3.5 \code{purpose_specification}).
#'
#' @param spec An \code{analysis_spec} list.
#' @return \code{list(variable, training_level)}, or \code{NULL} when no split
#'   applies.
#' @export
analysis_split <- function(spec) {
  ps <- spec$purpose_specification
  if (!identical(ps$model_purpose, "prediction") || !identical(ps$validation_method, "split")) return(NULL)
  v   <- ps$split_variable
  lvl <- ps$training_level
  if (is.null(v) || !nzchar(v) || is.null(lvl) || !nzchar(lvl)) return(NULL)
  list(variable = v, training_level = lvl)
}


#' How a prediction model is validated
#'
#' Reads the Step 1 purpose (\code{purpose_specification}) and the Model ›
#' Performance settings (\code{validation_settings}), filling defaults.
#' Association models are not validated: \code{method = "none"}. A held-out
#' test set (\code{"split"}) cannot be combined with resampling — it is
#' deliberately separate data, e.g. other centres.
#'
#' @param spec An \code{analysis_spec} list.
#' @param mixed Logical. Mixed models default to fewer bootstrap resamples
#'   (each refit is slow).
#' @return \code{list(method, cv_folds, cv_repeats, bootstrap_reps, seed)};
#'   \code{method} is \code{"none"}, \code{"split"}, \code{"cv"} or
#'   \code{"bootstrap"}.
#' @export
analysis_validation <- function(spec, mixed = FALSE) {
  ps <- spec$purpose_specification
  method <- if (!identical(ps$model_purpose, "prediction")) "none" else {
    m <- ps$validation_method %||% "bootstrap"
    if (m %in% c("split", "cv", "bootstrap")) m else "bootstrap"
  }
  vs  <- spec$validation_settings %||% list()
  def <- .default_validation_settings()
  .int <- function(x, d, lo, hi) {
    x <- suppressWarnings(as.integer(x))
    if (length(x) != 1L || is.na(x)) d else min(max(x, lo), hi)
  }
  list(
    method         = method,
    cv_folds       = .int(vs$cv_folds, def$cv_folds, 2L, 20L),
    cv_repeats     = .int(vs$cv_repeats, def$cv_repeats, 1L, 50L),
    bootstrap_reps = .int(vs$bootstrap_reps, if (mixed) .PERF_BOOT_MIXED_DEFAULT else .PERF_BOOT_DEFAULT,
                          10L, 2000L),
    seed           = .int(vs$seed, def$seed, 1L, .Machine$integer.max)
  )
}


#' Which rows are in the training and test sets
#'
#' Rows whose split variable equals the training level are the training set;
#' rows with any other (non-missing) level are the test set; rows missing the
#' split variable are in neither.
#'
#' @param spec An \code{analysis_spec} list.
#' @param data The frozen analysis dataset.
#' @return \code{NULL} when no split applies, else \code{list(variable,
#'   training_level, test_levels, training, test, n_missing)} where
#'   \code{training} and \code{test} are logical vectors over the rows of
#'   \code{data}.
#' @export
analysis_split_rows <- function(spec, data) {
  sp <- analysis_split(spec)
  if (is.null(sp) || is.null(data) || !sp$variable %in% names(data)) return(NULL)
  x <- as.character(data[[sp$variable]])
  training <- !is.na(x) & x == sp$training_level
  test     <- !is.na(x) & x != sp$training_level
  c(sp, list(test_levels = sort(unique(x[test])),
             training = training, test = test, n_missing = sum(is.na(x))))
}


#' The rows a model is built from
#'
#' The training set when a train/test split applies, otherwise every row.
#' Variable investigation, covariate counts, preflight and the model fit all
#' use this, so nothing is learned from the test set.
#'
#' @param spec An \code{analysis_spec} list.
#' @param data The frozen analysis dataset.
#' @return A \code{data.frame}.
#' @export
analysis_model_data <- function(spec, data) {
  sr <- analysis_split_rows(spec, data)
  if (is.null(sr)) return(data)
  data[sr$training, , drop = FALSE]
}


#' The held-out test set
#'
#' @inheritParams analysis_model_data
#' @return A \code{data.frame}, or \code{NULL} when no split applies.
#' @export
analysis_test_data <- function(spec, data) {
  sr <- analysis_split_rows(spec, data)
  if (is.null(sr)) return(NULL)
  data[sr$test, , drop = FALSE]
}


#' Summarise the complete-case sample for a covariate selection
#'
#' Listwise deletion across the outcome, exposure and selected covariates
#' decides which rows reach the model — and which factor levels survive.
#' This computes everything Step 4 needs to show that live as covariates are
#' checked and unchecked: row counts, per-variable row cost, the factor levels
#' present in the surviving rows, and the checks that block or warn.
#'
#' @param data A \code{data.frame} (the frozen analysis dataset).
#' @param outcome Character. Outcome variable name.
#' @param exposure Character or \code{NULL}. Exposure variable name.
#' @param covariates Character vector. Currently selected covariates.
#' @param candidates Character vector. All candidate covariates (selected or
#'   not); each gets a row cost and a level set.
#' @param cluster_vars Character vector. Cluster variables, used only by mixed
#'   models as random intercepts. Counted separately so a plain
#'   \code{lm}/\code{glm} is not charged for their missingness.
#'
#' @return A named list: \code{n_total}, \code{n_base} (outcome + exposure),
#'   \code{n_fixed} (+ selected covariates), \code{n_mixed} (+ cluster vars,
#'   or \code{NA} when there are none), \code{outcome_counts} (named integer,
#'   for a factor outcome), \code{n_params}, \code{epv}, \code{row_cost} (named
#'   integer over \code{candidates} and \code{cluster_vars}), \code{levels}
#'   (named list of levels present, factor variables only), and \code{issues}
#'   (\code{data.frame(level, variable, message)}; level is
#'   \code{"error"}, \code{"warning"} or \code{"note"}).
#' @export
compute_covariate_sample <- function(data, outcome, exposure = NULL,
                                     covariates = character(0),
                                     candidates = character(0),
                                     cluster_vars = character(0)) {
  n_total      <- nrow(data)
  exposure     <- exposure[!is.null(exposure) & nzchar(exposure)]
  covariates   <- intersect(covariates, names(data))
  candidates   <- intersect(candidates, names(data))
  cluster_vars <- intersect(cluster_vars, names(data))

  all_true <- rep(TRUE, n_total)
  .ok   <- function(v) !is.na(data[[v]])
  .rows <- function(vars) Reduce(`&`, lapply(vars, .ok), all_true)

  base_vars  <- c(outcome, exposure)
  model_vars <- unique(c(base_vars, covariates))
  ok_base    <- .rows(base_vars)
  ok_fixed   <- .rows(model_vars)
  ok_mixed   <- if (length(cluster_vars) > 0L) ok_fixed & .rows(cluster_vars) else NULL

  n_fixed <- sum(ok_fixed)

  # Row cost: checked covariates → rows they are costing now;
  # unchecked candidates and cluster vars → rows lost by adding them.
  cost_vars <- unique(c(candidates, cluster_vars))
  row_cost  <- vapply(cost_vars, function(v) {
    if (v %in% covariates) {
      sum(.rows(setdiff(model_vars, v))) - n_fixed
    } else {
      n_fixed - sum(ok_fixed & .ok(v))
    }
  }, integer(1))

  # Factor levels present in the rows each variable would be modelled on
  .present <- function(v, rows) {
    col <- data[[v]]
    if (!is.factor(col)) return(NULL)
    levels(droplevels(col[rows]))
  }
  lv <- list()
  for (v in model_vars) lv[[v]] <- .present(v, ok_fixed)
  for (v in setdiff(candidates, covariates)) lv[[v]] <- .present(v, ok_fixed & .ok(v))
  for (v in cluster_vars) lv[[v]] <- .present(v, ok_mixed)
  lv <- Filter(Negate(is.null), lv)

  .issue <- function(level, variable, message) {
    data.frame(level = level, variable = variable, message = message,
               stringsAsFactors = FALSE)
  }
  issues <- list()

  # Variables the model cannot estimate on the surviving rows → error row or NULL
  .check_variation <- function(v, label) {
    x <- data[[v]][ok_fixed]
    x <- x[!is.na(x)]
    n_distinct <- length(unique(x))
    if (n_distinct >= 2L) return(NULL)
    what <- if (is.factor(x)) {
      if (n_distinct == 1L) sprintf("has only one level (%s)", as.character(x[1]))
      else "has no levels"
    } else {
      "has no variation"
    }
    .issue("error", v, sprintf("%s %s %s in the %d complete rows.",
                               label, v, what, n_fixed))
  }

  outcome_counts <- NULL
  if (n_fixed == 0L) {
    issues <- c(issues, list(.issue("error", NA_character_,
      "No rows are complete across the outcome, exposure and selected covariates.")))
  } else {
    issues <- c(issues,
                list(.check_variation(outcome, "Outcome")),
                lapply(exposure,   .check_variation, label = "Exposure"),
                lapply(covariates, .check_variation, label = "Covariate"))

    y <- data[[outcome]]
    if (is.factor(y) || is.logical(y)) {
      y <- if (is.factor(y)) droplevels(y[ok_fixed]) else factor(y[ok_fixed])
      outcome_counts <- table(y)
      outcome_counts <- stats::setNames(as.integer(outcome_counts), names(outcome_counts))
    }
  }

  # Parameters: 1 per numeric/logical term, (levels − 1) per factor term
  pred_vars <- c(exposure, covariates)
  n_params <- sum(vapply(pred_vars, function(v) {
    if (is.factor(data[[v]])) max(length(lv[[v]]) - 1L, 0L) else 1L
  }, integer(1)))

  epv <- NA_real_
  if (length(outcome_counts) == 2L && n_params > 0L) {
    epv <- min(outcome_counts) / n_params
    if (epv < 5) {
      issues <- c(issues, list(.issue("warning", outcome, sprintf(
        "Only %.1f events per parameter (EPV < 5) - estimates are likely unstable.", epv))))
    } else if (epv < 10) {
      issues <- c(issues, list(.issue("warning", outcome, sprintf(
        "%.1f events per parameter (EPV < 10) - consider fewer covariates.", epv))))
    }
  }

  if (n_total > 0L && n_fixed > 0L && (n_total - n_fixed) / n_total > 0.2) {
    issues <- c(issues, list(.issue("warning", NA_character_, sprintf(
      "%d of %d rows (%d%%) are dropped for missing data.",
      n_total - n_fixed, n_total, round((n_total - n_fixed) / n_total * 100)))))
  }

  # Cluster structure: warn only — Step 5 preflight blocks the mixed model
  for (v in if (n_fixed > 0L) cluster_vars else character(0)) {
    x <- data[[v]][ok_mixed]
    n_distinct <- length(unique(x[!is.na(x)]))
    if (n_distinct < 2L) {
      issues <- c(issues, list(.issue("warning", v, sprintf(
        "%s has %d distinct value%s in the complete rows - mixed models will be unavailable.",
        v, n_distinct, if (n_distinct == 1L) "" else "s"))))
    }
  }

  # Levels present in the full data but lost to listwise deletion
  for (v in intersect(model_vars, names(lv))) {
    lost <- setdiff(levels(droplevels(data[[v]])), lv[[v]])
    if (length(lost) > 0L && length(lv[[v]]) >= 2L) {
      issues <- c(issues, list(.issue("note", v, sprintf(
        "%s: level%s %s not present in the complete rows.",
        v, if (length(lost) > 1L) "s" else "", paste(lost, collapse = ", ")))))
    }
  }

  issues <- Filter(Negate(is.null), issues)
  issues <- if (length(issues) > 0L) {
    do.call(rbind, issues)
  } else {
    data.frame(level = character(0), variable = character(0),
               message = character(0), stringsAsFactors = FALSE)
  }

  list(
    n_total        = n_total,
    n_base         = sum(ok_base),
    n_fixed        = n_fixed,
    n_mixed        = if (is.null(ok_mixed)) NA_integer_ else sum(ok_mixed),
    outcome_counts = outcome_counts,
    n_params       = n_params,
    epv            = epv,
    row_cost       = row_cost,
    levels         = lv,
    issues         = issues
  )
}
