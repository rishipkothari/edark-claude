#' Analysis Pipeline Reset Service
#'
#' Provides \code{reset_analysis_pipeline()}, the single function responsible
#' for clearing downstream \code{shared_state} fields when an upstream change
#' invalidates previously computed results. See PRD §8.6 for the authoritative
#' reset matrix.
#'
#' @name service_analysis_pipeline
NULL


#' Reset downstream analysis state after an upstream change
#'
#' Clears the appropriate \code{shared_state} fields depending on which step
#' triggered the reset. Does not show any modal — the calling module is
#' responsible for confirming with the user before calling this function.
#'
#' @param shared_state A Shiny \code{reactiveValues} object.
#' @param from_step Integer. The step that triggered the reset: \code{1}
#'   (role assignment change), \code{4} (covariate change after a fit), or
#'   \code{5} (a Step 5 setting, e.g. the optimizer, changed after a fit).
#'
#' @return \code{invisible(NULL)}
#' @export
reset_analysis_pipeline <- function(shared_state, from_step) {
  from_step <- as.integer(from_step)

  if (from_step == 1L) {
    # Role change invalidates everything downstream of Setup.
    # Null out the entire result object and reset all spec fields
    # downstream of variable_roles (which has already been updated by the
    # calling module).
    shared_state$analysis_result <- NULL

    if (!is.null(shared_state$analysis_spec)) {
      shared_state$analysis_spec$variable_selection_specification <- list(
        method                  = "univariable",
        univariable_p_threshold = 0.2,
        stepwise_direction      = "backward",
        stepwise_criterion      = "BIC",
        lasso_lambda            = "lambda.1se",
        selected_variables      = NULL
      )
      shared_state$analysis_spec$model_design <- .default_model_design()
      # Covariates start unselected; Step 4 starts over
      shared_state$analysis_spec$variable_roles$final_model_covariates <- NULL
    }

  } else if (from_step %in% c(4L, 5L)) {
    # A covariate change (4) or a Step 5 setting change (5) invalidates the
    # fitted model, diagnostics, and results — but leaves Table 1 and
    # variable investigation intact. Step 5 changes the spec itself after the
    # reset, so model_design is left alone here.
    if (!is.null(shared_state$analysis_result)) {
      res <- shared_state$analysis_result

      res$fitted_models$primary_model <- NULL
      res$run_status <- list(
        status       = NULL,
        fitted_at    = NULL,
        run_messages = tibble::tibble(
          level   = character(),
          stage   = character(),
          message = character()
        )
      )
      res$result_tables$main_results       <- NULL
      res$result_tables$diagnostic_summary <- NULL
      res$result_plots$coefficient_plot    <- NULL
      res$result_plots$diagnostic_plots    <- lapply(
        res$result_plots$diagnostic_plots, function(x) NULL
      )
      res$inference_summary <- list(
        coefficients       = NULL,
        fit_statistics     = NULL,
        predicted_values   = NULL,
        influence_measures = NULL
      )
      res$diagnostics        <- NULL
      res$generated_r_script <- NULL
      res$methods_paragraph  <- NULL

      shared_state$analysis_result <- res
    }
  }

  invisible(NULL)
}


# Fresh model_design block for analysis_spec (PRD §3.5). Random intercepts
# come from variable_roles$cluster_variables, so there is no field for them.
.default_model_design <- function() {
  list(
    model_type                 = NULL,
    confidence_interval_level  = 0.95,
    optimizer                  = "bobyqa",
    linked_model_specification = NULL
  )
}
