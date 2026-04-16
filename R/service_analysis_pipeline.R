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
#'   (role assignment change), \code{4} (covariate re-confirmation), or
#'   \code{5} (model type change).
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
      shared_state$analysis_spec$model_design <- list(
        model_type                 = NULL,
        random_intercept_variable  = NULL,
        random_slope_variable      = NULL,
        confidence_interval_level  = 0.95,
        optimizer                  = "bobyqa",
        linked_model_specification = NULL
      )
      # Reset final covariates back to the full candidate pool
      cands <- shared_state$analysis_spec$variable_roles$candidate_covariates
      shared_state$analysis_spec$variable_roles$final_model_covariates <- cands
    }

  } else if (from_step %in% c(4L, 5L)) {
    # Covariate re-confirmation or model type change invalidates the fitted
    # model, diagnostics, and results — but leaves Table 1 and variable
    # investigation intact.
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
      res$generated_r_script <- NULL
      res$methods_paragraph  <- NULL

      shared_state$analysis_result <- res
    }

    # When the model type itself changes (Step 5), also clear the model_design
    # in the spec so the new selection is treated as a fresh configuration.
    if (from_step == 5L && !is.null(shared_state$analysis_spec)) {
      shared_state$analysis_spec$model_design <- list(
        model_type                 = NULL,
        random_intercept_variable  = NULL,
        random_slope_variable      = NULL,
        confidence_interval_level  = 0.95,
        optimizer                  = "bobyqa",
        linked_model_specification = NULL
      )
    }
  }

  invisible(NULL)
}
