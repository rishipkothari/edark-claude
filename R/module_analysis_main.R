#' Analysis Module — Main Orchestrator
#'
#' UI and server for the Analysis stage (Tab 4 — \code{4 · Analyze}).
#' Renders an 8-step \code{navset_pill} and delegates each step to its own
#' sub-module. Also registers the JS custom message handler used by the
#' blocking progress modal shared across all analysis run buttons.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object (shared across
#'   all modules).
#'
#' @name module_analysis_main
NULL


#' @rdname module_analysis_main
#' @export
analysis_main_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # JS handler — updates the progress bar and detail text inside the
    # blocking analysis modal (mirrors the pattern in module_report.R).
    shiny::tags$script(shiny::HTML(
      "Shiny.addCustomMessageHandler('edark_analysis_progress', function(msg) {",
      "  var bar = document.getElementById('edark_analysis_progress_bar');",
      "  if (bar) {",
      "    bar.style.width = (msg.frac * 100) + '%';",
      "    bar.setAttribute('aria-valuenow', Math.round(msg.frac * 100));",
      "  }",
      "  var txt = document.getElementById('edark_analysis_progress_detail');",
      "  if (txt) txt.textContent = msg.detail;",
      "});"
    )),

    bslib::navset_pill(
      id = ns("analysis_steps"),

      bslib::nav_panel(
        value = "step1",
        title = "1 \u00b7 Setup",
        analysis_setup_ui(ns("setup"))
      ),
      bslib::nav_panel(
        value = "step2",
        title = "2 \u00b7 Table 1",
        analysis_table1_ui(ns("table1"))
      ),
      bslib::nav_panel(
        value = "step3",
        title = "3 \u00b7 Variable Investigation",
        analysis_varinvestigation_ui(ns("varinvestigation"))
      ),
      bslib::nav_panel(
        value = "step4",
        title = "4 \u00b7 Covariate Confirmation",
        analysis_covariate_confirm_ui(ns("covariate_confirm"))
      ),
      bslib::nav_panel(
        value = "step5",
        title = "5 \u00b7 Model Specification",
        analysis_modelspec_ui(ns("modelspec"))
      ),
      bslib::nav_panel(
        value = "step6",
        title = "6 \u00b7 Diagnostics",
        analysis_diagnostics_ui(ns("diagnostics"))
      ),
      bslib::nav_panel(
        value = "step7",
        title = "7 \u00b7 Results",
        analysis_results_ui(ns("results"))
      ),
      bslib::nav_panel(
        value = "step8",
        title = "8 \u00b7 Export",
        analysis_export_ui(ns("export"))
      )
    )
  )
}


#' @rdname module_analysis_main
#' @export
analysis_main_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    # Wire all step sub-modules — each is a sibling, none calls another's server.
    analysis_setup_server("setup",                       shared_state)
    analysis_table1_server("table1",                     shared_state)
    analysis_varinvestigation_server("varinvestigation", shared_state)
    analysis_covariate_confirm_server("covariate_confirm", shared_state)
    analysis_modelspec_server("modelspec",               shared_state)
    analysis_diagnostics_server("diagnostics",           shared_state)
    analysis_results_server("results",                   shared_state)
    analysis_export_server("export",                     shared_state)
  })
}
