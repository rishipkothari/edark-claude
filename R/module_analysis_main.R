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

    ns <- session$ns

    # Wire all step sub-modules — each is a sibling, none calls another's server.
    analysis_setup_server("setup",                       shared_state)
    analysis_table1_server("table1",                     shared_state)
    analysis_varinvestigation_server("varinvestigation", shared_state)
    analysis_covariate_confirm_server("covariate_confirm", shared_state)
    analysis_modelspec_server("modelspec",               shared_state)
    analysis_diagnostics_server("diagnostics",           shared_state)
    analysis_results_server("results",                   shared_state)
    analysis_export_server("export",                     shared_state)

    # ── Step gating ──────────────────────────────────────────────────────────
    # Steps 1–4 are always reachable (each shows its own guidance when Step 1
    # is incomplete). Table 1 and variable investigation are optional, so
    # Step 5 opens as soon as Step 1 has a frozen dataset and an outcome;
    # Step 5's Run Model is gated only by its preflight.
    step_unlocked <- shiny::reactive({
      spec   <- shared_state$analysis_spec
      ready  <- !is.null(shared_state$analysis_data) && !is.null(spec) &&
                !is.null(spec$variable_roles$outcome_variable)
      fitted <- !is.null(shared_state$analysis_result$fitted_models$primary_model)
      c(step1 = TRUE, step2 = TRUE, step3 = TRUE, step4 = TRUE,
        step5 = ready, step6 = fitted, step7 = fitted, step8 = fitted)
    })

    lock_reason <- c(
      step5 = "Start the analysis and assign an outcome in Step 1 first.",
      step6 = "Fit a model in Step 5 first.",
      step7 = "Fit a model in Step 5 first.",
      step8 = "Fit a model in Step 5 first."
    )

    shiny::observe({
      unlocked <- step_unlocked()
      tabs_sel <- paste0("#", ns("analysis_steps"))

      for (step in names(unlocked)) {
        link <- sprintf("%s a[data-value='%s']", tabs_sel, step)
        shinyjs::toggleClass(selector = link, class = "disabled",
                             condition = !unlocked[[step]])
        # Tooltip on the <li>: the disabled link itself has pointer-events: none
        tip <- if (unlocked[[step]]) "" else lock_reason[[step]]
        shinyjs::runjs(sprintf("$(\"%s\").parent().attr('title', %s);",
                               link, jsonlite::toJSON(tip, auto_unbox = TRUE)))
      }

      # If the current step just became locked, fall back to the furthest open step
      current <- shiny::isolate(input$analysis_steps)
      if (!is.null(current) && current %in% names(unlocked) && !unlocked[[current]]) {
        open_steps <- names(unlocked)[unlocked]
        open_steps <- open_steps[match(open_steps, names(unlocked)) <
                                 match(current, names(unlocked))]
        bslib::nav_select("analysis_steps", selected = utils::tail(open_steps, 1))
      }
    })
  })
}
