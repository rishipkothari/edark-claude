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
#' the appropriate random-effects term is appended.
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
  model_type <- spec$model_design$model_type

  if (is.null(outcome) || !nzchar(outcome)) {
    stop("build_analysis_formula: no outcome variable in spec.")
  }

  # Fixed-effect predictors: exposure first, then remaining covariates
  preds <- unique(c(exposure, covariates))
  preds <- preds[!vapply(preds, is.null, logical(1))]
  preds <- preds[nzchar(preds)]

  rhs <- if (length(preds) == 0) "1" else paste(preds, collapse = " + ")

  # Random-effects term for mixed models
  if (!is.null(model_type) && model_type %in% c("linear_mixed", "logistic_mixed")) {
    subject_id <- roles$subject_id_variable
    if (!is.null(subject_id) && nzchar(subject_id)) {
      slope_var <- spec$model_design$random_slope_variable
      re_term <- if (!is.null(slope_var) && nzchar(slope_var)) {
        paste0("(1 + ", slope_var, " | ", subject_id, ")")
      } else {
        paste0("(1 | ", subject_id, ")")
      }
      rhs <- paste(rhs, "+", re_term)
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
