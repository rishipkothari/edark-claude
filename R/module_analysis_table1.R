#' Analysis Step 2 — Table 1 Module
#'
#' UI and server for Step 2 of the Analysis workflow: descriptive summary
#' table (Table 1) stratified by exposure, outcome, or overall.
#' Full implementation per PRD §5.3 Step 2, §6.4, §3.7.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_table1
NULL


#' @rdname module_analysis_table1
#' @export
analysis_table1_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      position = "left",
      width    = 260,

      shiny::tags$p("Stratification",
        class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
      shiny::checkboxInput(ns("strat_by_exposure"), "By Exposure", value = TRUE),
      shiny::checkboxInput(ns("strat_by_outcome"),  "By Outcome",  value = FALSE),

      shiny::tags$p("Options",
        class = "text-muted small text-uppercase fw-semibold mt-3 mb-1"),
      shiny::checkboxInput(ns("include_pvalues"), "Show P-values", value = FALSE),
      shiny::div(
        class = "d-flex align-items-center gap-1",
        shiny::checkboxInput(ns("include_smd"), "Show SMD", value = TRUE),
        shiny::tags$small(
          class       = "text-muted",
          title       = "Standardized Mean Difference. Only shown for binary stratifiers.",
          style       = "cursor:help;",
          shiny::icon("circle-question")
        )
      ),

      shiny::tags$hr(class = "my-2"),
      shiny::actionButton(
        ns("btn_generate"),
        label = shiny::tagList(shiny::icon("table"), " Generate Table 1"),
        class = "btn-primary w-100"
      )
    ),

    shiny::uiOutput(ns("table_area"))
  )
}


#' @rdname module_analysis_table1
#' @export
analysis_table1_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Set checkbox defaults from study type when spec changes ──────────────
    shiny::observeEvent(shared_state$analysis_spec, {
      spec <- shared_state$analysis_spec
      if (is.null(spec)) return()

      st <- spec$specification_metadata$study_type
      if (is.null(st)) return()

      strat_exp <- st %in% c("exposure_outcome", "descriptive_exposure")
      strat_out <- st == "risk_factor"
      p_exp     <- FALSE
      p_out     <- st %in% c("risk_factor", "exposure_outcome")

      shiny::updateCheckboxInput(session, "strat_by_exposure", value = strat_exp)
      shiny::updateCheckboxInput(session, "strat_by_outcome",  value = strat_out)
      shiny::updateCheckboxInput(session, "include_pvalues",   value = p_out)
    }, ignoreNULL = TRUE)

    # ── Generate Table 1 ─────────────────────────────────────────────────────
    shiny::observeEvent(input$btn_generate, {
      spec  <- shiny::isolate(shared_state$analysis_spec)
      adata <- shiny::isolate(shared_state$analysis_data)

      if (is.null(spec) || is.null(adata)) {
        shiny::showNotification("Start analysis first (Step 1).", type = "warning")
        return()
      }
      if (is.null(spec$variable_roles$outcome_variable) &&
          is.null(spec$variable_roles$exposure_variable) &&
          is.null(spec$variable_roles$candidate_covariates)) {
        shiny::showNotification("Assign at least one variable role in Step 1.", type = "warning")
        return()
      }

      strat_exp <- isTRUE(input$strat_by_exposure)
      strat_out <- isTRUE(input$strat_by_outcome)
      incl_p    <- isTRUE(input$include_pvalues)
      incl_smd  <- isTRUE(input$include_smd)

      # Temporarily override spec table1_specification with current UI state
      spec$table1_specification$stratify_by_exposure <- strat_exp
      spec$table1_specification$stratify_by_outcome  <- strat_out
      spec$table1_specification$include_pvalues_exposure <- incl_p
      spec$table1_specification$include_pvalues_outcome  <- incl_p

      shiny::showModal(shiny::modalDialog(
        title = shiny::tagList(
          shiny::tags$span(
            class = "spinner-border spinner-border-sm me-2",
            role  = "status",
            shiny::tags$span(class = "visually-hidden", "Loading...")
          ),
          "Generating Table 1\u2026"
        ),
        shiny::div(
          class = "progress mb-2",
          style = "height: 6px;",
          shiny::div(
            id              = "edark_analysis_progress_bar",
            class           = "progress-bar progress-bar-striped progress-bar-animated",
            role            = "progressbar",
            style           = "width: 5%;",
            `aria-valuenow` = "5",
            `aria-valuemin` = "0",
            `aria-valuemax` = "100"
          )
        ),
        shiny::tags$p(
          id    = "edark_analysis_progress_detail",
          class = "text-muted mb-0 small",
          "Building summary table\u2026"
        ),
        footer    = NULL,
        easyClose = FALSE
      ))
      on.exit(shiny::removeModal(), add = TRUE)

      tables <- build_table1(
        data                     = adata,
        spec                     = spec,
        include_pvalues_exposure = incl_p,
        include_pvalues_outcome  = incl_p,
        include_smd              = incl_smd
      )

      # Store in analysis_result
      res <- shiny::isolate(shared_state$analysis_result)
      if (is.null(res)) res <- list()
      if (is.null(res$result_tables)) res$result_tables <- list()

      res$result_tables$table1_overall     <- tables$overall
      res$result_tables$table1_by_exposure <- tables$by_exposure
      res$result_tables$table1_by_outcome  <- tables$by_outcome
      shared_state$analysis_result <- res

      # Persist spec overrides
      cur_spec <- shiny::isolate(shared_state$analysis_spec)
      if (!is.null(cur_spec)) {
        cur_spec$table1_specification <- spec$table1_specification
        shared_state$analysis_spec    <- cur_spec
      }
    }, ignoreInit = TRUE)

    # ── Table area ────────────────────────────────────────────────────────────
    output$table_area <- shiny::renderUI({
      result <- shared_state$analysis_result
      spec   <- shared_state$analysis_spec

      # Determine which tabs to show
      exp_assigned <- !is.null(spec$variable_roles$exposure_variable)
      out_assigned <- !is.null(spec$variable_roles$outcome_variable)
      strat_exp    <- isTRUE(input$strat_by_exposure)
      strat_out    <- isTRUE(input$strat_by_outcome)

      has_overall  <- !is.null(result$result_tables$table1_overall)
      has_exposure <- exp_assigned && strat_exp && !is.null(result$result_tables$table1_by_exposure)
      has_outcome  <- out_assigned && strat_out && !is.null(result$result_tables$table1_by_outcome)

      if (!has_overall) {
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::icon("table", style = "font-size:2rem; opacity:0.3;"),
          shiny::tags$p(class = "mt-2", "Click \u201cGenerate Table 1\u201d to build the summary table.")
        ))
      }

      tabs <- list(
        bslib::nav_panel("Overall", gt::gt_output(ns("tbl_overall")))
      )
      if (has_exposure) {
        tabs[[length(tabs) + 1]] <- bslib::nav_panel(
          paste0("By ", spec$variable_roles$exposure_variable),
          gt::gt_output(ns("tbl_by_exposure"))
        )
      }
      if (has_outcome) {
        tabs[[length(tabs) + 1]] <- bslib::nav_panel(
          paste0("By ", spec$variable_roles$outcome_variable),
          gt::gt_output(ns("tbl_by_outcome"))
        )
      }

      do.call(bslib::navset_card_tab, tabs)
    })

    # ── gt render outputs ─────────────────────────────────────────────────────
    output$tbl_overall <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_overall
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

    output$tbl_by_exposure <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_by_exposure
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

    output$tbl_by_outcome <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_by_outcome
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

  })
}
