#' Analysis Table Generation Service
#'
#' Provides functions for generating \code{gtsummary} tables used in the
#' Analysis module. Called from Steps 2 (Table 1) and 7 (Results).
#' All functions are pure — no Shiny dependencies.
#'
#' @importFrom magrittr %>%
#'
#' @name service_analysis_tables
NULL


#' Build Table 1 (descriptive summary table)
#'
#' Generates up to three \code{gtsummary::tbl_summary} objects: an overall
#' summary and optional stratified tables by exposure and outcome.
#'
#' @param data A \code{data.frame} (the frozen analysis dataset).
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#' @param include_pvalues_exposure Logical. Add p-values to the by-exposure tab.
#' @param include_pvalues_outcome Logical. Add p-values to the by-outcome tab.
#' @param include_smd Logical. Add standardized mean difference to the
#'   by-exposure tab (only applied when the stratifier has exactly 2 levels).
#'
#' @return A named list: \code{overall}, \code{by_exposure}, \code{by_outcome}.
#'   Elements are \code{NULL} when not applicable.
#' @export
build_table1 <- function(data,
                         spec,
                         include_pvalues_exposure = FALSE,
                         include_pvalues_outcome  = TRUE,
                         include_smd              = TRUE) {

  roles        <- spec$variable_roles
  outcome_var  <- roles$outcome_variable
  exposure_var <- roles$exposure_variable
  t1_vars      <- roles$table1_variables
  t1_spec      <- spec$table1_specification

  t1_vars <- setdiff(t1_vars, ".edark_row_id")
  t1_vars <- intersect(names(data), t1_vars)          # dataset column order
  priority <- c(exposure_var, outcome_var)
  priority <- priority[!vapply(priority, function(x) is.null(x) || !nzchar(x), logical(1))]
  priority <- intersect(priority, t1_vars)
  t1_vars  <- c(priority, setdiff(t1_vars, priority)) # exposure → outcome → rest

  if (length(t1_vars) == 0) {
    return(list(overall = NULL, by_exposure = NULL, by_outcome = NULL))
  }

  .build_one <- function(by_var, include_p, include_smd_flag) {
    tryCatch({
      if (!is.null(by_var) && by_var %in% names(data)) {
        all_vars <- unique(c(t1_vars, by_var))
        all_vars <- intersect(all_vars, names(data))

        tbl <- gtsummary::tbl_summary(
          data    = data[, all_vars, drop = FALSE],
          by      = by_var,
          missing = "no"
        ) %>%
          gtsummary::add_overall() %>%
          gtsummary::bold_labels()

        if (include_p) {
          tbl <- tbl %>% gtsummary::add_p()
        }

        if (include_smd_flag) {
          strat_col <- data[[by_var]]
          n_levels  <- if (is.factor(strat_col)) {
            length(levels(droplevels(strat_col)))
          } else {
            length(unique(stats::na.omit(strat_col)))
          }
          if (n_levels == 2L) {
            tbl <- tryCatch(
              tbl %>% gtsummary::add_difference(
                test = list(
                  gtsummary::all_continuous()   ~ "smd",
                  gtsummary::all_categorical()  ~ "smd"
                )
              ),
              error = function(e) tbl
            )
          }
        }

        tbl
      } else {
        gtsummary::tbl_summary(
          data    = data[, t1_vars, drop = FALSE],
          missing = "no"
        ) %>%
          gtsummary::bold_labels()
      }
    }, error = function(e) NULL)
  }

  overall <- .build_one(NULL, FALSE, FALSE)

  by_exposure <- if (!is.null(exposure_var) &&
                     exposure_var %in% names(data) &&
                     isTRUE(t1_spec$stratify_by_exposure)) {
    .build_one(
      exposure_var,
      isTRUE(t1_spec$include_pvalues_exposure) || include_pvalues_exposure,
      include_smd && isTRUE(t1_spec$include_standardized_mean_difference)
    )
  } else NULL

  by_outcome <- if (!is.null(outcome_var) &&
                    outcome_var %in% names(data) &&
                    isTRUE(t1_spec$stratify_by_outcome)) {
    .build_one(
      outcome_var,
      isTRUE(t1_spec$include_pvalues_outcome) || include_pvalues_outcome,
      FALSE
    )
  } else NULL

  list(overall = overall, by_exposure = by_exposure, by_outcome = by_outcome)
}
