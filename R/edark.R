#' Launch the EDARK exploratory data analysis GUI
#'
#' The primary entry point for the package. Validates the input dataset,
#' auto-casts column types, initialises the session-scoped shared state, and
#' launches the Shiny application.
#'
#' @param dataset A `data.frame` or `tibble`. Defaults to the built-in
#'   `liver_tx` synthetic liver transplant dataset so that `edark()` with no
#'   arguments launches immediately for testing and demonstration.
#' @param max_factor_levels Integer. Character columns with no more than this
#'   many unique non-NA values are auto-converted to `factor` at launch.
#'   Also used as the high-cardinality guard threshold in the Explore stage.
#'   Default `20`.
#'
#' @return Launches a Shiny app (does not return a value).
#'
#' @export
#' @examples
#' \dontrun{
#' edark()                  # launches with built-in liver_tx demo data
#' edark(mtcars)
#' edark(palmerpenguins::penguins, max_factor_levels = 10)
#' }
edark <- function(dataset = liver_tx, max_factor_levels = 20) {

  # ── Validate ───────────────────────────────────────────────────────────────
  validate_input(dataset, max_factor_levels)

  # ── Pre-process (runs once, before the reactive graph starts) ──────────────
  dataset_cast  <- cast_column_types(dataset, max_factor_levels)
  column_types  <- detect_column_types(dataset_cast)

  # ── UI ─────────────────────────────────────────────────────────────────────
  ui <- bslib::page_navbar(
    id    = "main_navbar",
    title = shiny::tags$span(
      shiny::tags$strong("EDARK"),
      shiny::tags$span(" v0.2", class = "text-muted small ms-1")
    ),
    theme = bslib::bs_theme(
      version    = 5,
      bootswatch = "flatly",
      primary    = "#2c7be5"
    ),
    header = shiny::tags$head(shiny::tags$style(shiny::HTML("
      /* ── EDARK custom properties ── change values here, nowhere else ────── */

      /* sidebar nav-pill tabs */
      .sidebar .nav-pills .nav-link {
        padding-left: 0.6rem;
        padding-right: 0.6rem;
        border-radius: 20px;
        font-size: 0.95rem;
        font-weight: 500;
      }
      .sidebar .nav-pills .nav-link:not(.active) {
        background-color: var(--bs-tertiary-bg);
        color: var(--bs-secondary-color);
        border: 1px solid var(--bs-border-color);
      }
      .sidebar .nav-pills .nav-link:not(.active):hover {
        background-color: var(--bs-secondary-bg);
        color: var(--bs-body-color);
      }

      /* gap below tab bar, then leading whitespace inside each tab content */
      .sidebar .nav-pills {
        margin-bottom: 0.75rem;
      }
      .sidebar .tab-content > .tab-pane {
        padding-top: 0.75rem;
      }

      /* pickerInput button background */
      .bootstrap-select > .btn {
        background-color: var(--bs-body-bg) !important;
        border-color: var(--bs-border-color) !important;
      }
      .bootstrap-select > .btn:hover,
      .bootstrap-select > .btn:focus,
      .bootstrap-select.show > .btn {
        background-color: var(--bs-body-bg) !important;
        border-color: #86b7fe !important;
      }

      /* theme + debug navbar buttons */
      #theme_toggle, #debug_btn {
        background: none;
        border: none;
        color: rgba(255,255,255,0.75);
        font-size: 1.1rem;
        padding: 0.25rem 0.5rem;
        line-height: 1;
      }
      #theme_toggle:hover, #debug_btn:hover { color: #ffffff; }
    "))),

    # ── Tab 1: Prepare ───────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "prepare",
      title = shiny::tagList(shiny::icon("sliders"), " 1 \u00b7 Prepare"),
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          # title    = "Apply",
          position = "left",
          width    = 400,
          prepare_confirm_ui("prepare_confirm")
        ),
        bslib::navset_card_tab(
          id = "prepare_tabs",
          bslib::nav_panel(
            value = "columns",
            title = shiny::tagList(shiny::icon("table-columns"), " Columns"),
            column_manager_ui("column_manager")
          ),
          bslib::nav_panel(
            value = "transforms",
            title = shiny::tagList(shiny::icon("wand-magic-sparkles"), " Transforms"),
            transform_variables_ui("transform_variables")
          ),
          bslib::nav_panel(
            value = "filters",
            title = shiny::tagList(shiny::icon("filter"), " Row Filters"),
            row_filter_ui("row_filter")
          ),
          bslib::nav_panel(
            value = "preview",
            title = shiny::tagList(shiny::icon("eye"), " Data Preview"),
            data_preview_ui("data_preview")
          )
        )
      )
    ),

    # ── Tab 2: Explore ───────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "explore",
      title = shiny::tagList(shiny::icon("magnifying-glass-chart"), " 2 \u00b7 Explore"),
      bslib::navset_tab(
        id = "explore_tabs",
        bslib::nav_panel(
          value = "plot",
          title = shiny::tagList(shiny::icon("chart-area"), " Plot"),
          bslib::layout_sidebar(
            sidebar = bslib::sidebar(
              width = 400,
              bslib::navset_pill(
                bslib::nav_panel("Describe",  describe_controls_ui("describe_controls")),
                bslib::nav_panel("Correlate", relationship_controls_ui("relationship_controls")),
                bslib::nav_panel("Trend",     trend_controls_ui("trend_controls"))
              )
            ),
            explore_output_ui("explore_output")
          )
        ),
        bslib::nav_panel(
          value = "report",
          title = shiny::tagList(shiny::icon("file-export"), " Report"),
          report_ui("report")
        )
      )
    ),

    # ── Tab 3: Analyze ───────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "analyze",
      title = shiny::tagList(shiny::icon("chart-simple"), " 3 \u00b7 Analyze"),
      analysis_main_ui("analysis_main")
    ),

    bslib::nav_spacer(),
    bslib::nav_item(
      shiny::actionButton("debug_btn", label = shiny::icon("bug"))
    ),
    bslib::nav_item(
      shiny::actionButton("theme_toggle", label = shiny::tagList(span("Theme", class = "me-2"), icon("moon")))
    )
  )


  # ── Server ─────────────────────────────────────────────────────────────────
  server <- function(input, output, session) {

    # Session-scoped shared state — the single source of truth for everything.
    shared_state <- shiny::reactiveValues(

      # Dataset
      dataset_original        = dataset_cast,
      dataset_working         = dataset_cast,
      column_types            = column_types,
      original_column_types   = column_types,  # set once at launch, never overwritten

      # Prepare stage: staged (unapplied)
      included_columns        = names(dataset_cast),
      column_type_overrides   = list(),
      row_filter_specs        = list(),
      column_transform_specs  = list(),
      has_pending_changes     = FALSE,

      # Explore stage — Analyze tab
      primary_variable        = NULL,
      primary_variable_role   = "exposure",
      secondary_variable      = NULL,
      stratify_variable       = NULL,

      # Explore stage — Trend tab
      trend_timestamp_variable = NULL,
      trend_variable           = NULL,
      trend_summary_stat       = "mean_sd",
      trend_resolution         = "Month",
      trend_stratify_variable  = NULL,
      trend_zero_baseline      = TRUE,
      trend_impute_zero        = TRUE,

      # Plot state
      plot_specification      = NULL,
      active_plot             = NULL,
      variable_summary        = NULL,
      explore_needs_refresh   = FALSE,

      # Aesthetics
      ggplot_theme            = "minimal",
      color_palette           = "Set2",
      show_data_labels        = FALSE,
      show_legend             = TRUE,
      legend_position         = "right",

      # Plot options (captured on plot button click, not reactive)
      bar_display             = "count",

      # Custom report
      custom_report_items     = list(),   # list of item objects added from Explore tab
      requested_tab           = NULL,     # cross-tab navigation signal
      requested_report_subtab = NULL,     # navigate to report pill (full_report / custom_report)

      # Prepare stage revert support
      last_applied_specs = list(
        included_columns       = names(dataset_cast),
        column_type_overrides  = list(),
        column_transform_specs = list(),
        row_filter_specs       = list()
      ),
      revert_trigger = 0L,              # incremented by .revert_to_last_applied(); modules observe

      # Analysis module fields — initialized as NULL; written to only by the
      # analysis modules (see PRD §3.3). Never read or modified by Prepare/Explore.
      analysis_data   = NULL,
      analysis_spec   = NULL,
      analysis_result = NULL
    )

    # ── Prepare tab navigation guard ──────────────────────────────────────────
    # Auto-applies pending changes when the user switches prepare sub-tabs.
    # Invalid transforms block navigation (pipeline would mangle the column).
    # If custom report items exist, shows a modal before applying.
    last_prepare_tab <- shiny::reactiveVal("columns")

    # Shared helper: run the pipeline and commit to shared_state.
    .do_nav_apply <- function() {
      # Prune filter specs invalidated by staged transforms or column exclusion.
      .prune_conflicting_filter_specs(shared_state)
      df <- tryCatch(
        apply_prepare_pipeline(shared_state),
        error = function(e) {
          bslib::nav_select("prepare_tabs", last_prepare_tab())
          shiny::showNotification(
            paste("Error during apply:", conditionMessage(e)),
            type = "error", duration = 8
          )
          NULL
        }
      )
      if (is.null(df)) return()
      shared_state$dataset_working       <- df
      shared_state$column_types          <- detect_column_types(df)
      shared_state$has_pending_changes   <- FALSE
      shared_state$explore_needs_refresh <- TRUE
      .snapshot_last_applied_specs(shared_state)
      shiny::showNotification("Changes applied.", type = "message", duration = 2)
    }

    shiny::observeEvent(input$prepare_tabs, {
      if (isTRUE(shared_state$has_pending_changes)) {
        invalid <- .find_invalid_transforms(shared_state)
        if (length(invalid) > 0) {
          bslib::nav_select("prepare_tabs", last_prepare_tab())
          shiny::showNotification(
            paste0("Fix transforms before switching tabs: ",
                   paste(invalid, collapse = ", ")),
            type = "error", duration = 6
          )
          return()
        }
        # Guard: warn if custom report items exist (same guard as Apply button).
        n_items <- length(shiny::isolate(shared_state$custom_report_items))
        if (n_items > 0) {
          shiny::showModal(shiny::modalDialog(
            title = "Custom Report May Be Affected",
            paste0(
              "You have ", n_items, " item(s) in your custom report. ",
              "Dataset changes will clear custom report items. Would you like to proceed?"
            ),
            footer = shiny::tagList(
              shiny::actionButton("cancel_nav_apply_btn",
                                  "Go Back & Revert Changes",
                                  class = "btn-outline-secondary"),
              shiny::actionButton("confirm_nav_apply_btn",
                                  "Apply and Clear Custom Report",
                                  class = "btn-warning")
            ),
            easyClose = FALSE
          ))
          return()  # do NOT update last_prepare_tab — stays on old tab
        }
        .do_nav_apply()
      }
      last_prepare_tab(input$prepare_tabs)
    }, ignoreInit = TRUE)

    # Confirm: apply the pending changes and advance last_prepare_tab.
    shiny::observeEvent(input$confirm_nav_apply_btn, {
      shiny::removeModal()
      .do_nav_apply()
      last_prepare_tab(shiny::isolate(input$prepare_tabs))
    }, ignoreInit = TRUE)

    # Cancel: revert staged changes back to last-applied specs and return to
    # the previous tab (the tab navigation has already occurred in the DOM,
    # so we explicitly navigate back).
    shiny::observeEvent(input$cancel_nav_apply_btn, {
      shiny::removeModal()
      .revert_to_last_applied(shared_state)
      bslib::nav_select("prepare_tabs", last_prepare_tab())
    }, ignoreInit = TRUE)

    # ── Light / dark theme toggle ─────────────────────────────────────────────
    is_dark_theme <- shiny::reactiveVal(FALSE)

    shiny::observeEvent(input$theme_toggle, {
      dark <- !is_dark_theme()
      is_dark_theme(dark)
      session$setCurrentTheme(
        bslib::bs_theme(
          version    = 5,
          bootswatch = if (dark) "darkly" else "flatly",
          primary    = "#2c7be5"
        )
      )
      shiny::updateActionButton(session, "theme_toggle",
        label = shiny::tagList(span("Theme", class = "me-2"), icon(if (dark) "sun" else "moon"))
      )
    }, ignoreInit = TRUE)

    # ── Debug button ──────────────────────────────────────────────────────────
    shiny::observeEvent(input$debug_btn, {
      if (!identical(input$main_navbar, "analyze")) return(invisible(NULL))

      step <- input[["analysis_main-analysis_steps"]]
      if (is.null(step)) step <- "step1"

      .dbg <- function(label, x) {
        cat(sprintf("  [%s]\n", label))
        if (is.null(x)) cat("    <NULL>\n") else str(x, max.level = 3, give.attr = FALSE)
      }

      spec   <- shiny::isolate(shared_state$analysis_spec)
      result <- shiny::isolate(shared_state$analysis_result)
      adata  <- shiny::isolate(shared_state$analysis_data)

      cat(sprintf("\n════════════════ DEBUG · %s ════════════════\n", toupper(step)))

      if (step == "step1") {
        if (!is.null(adata)) {
          cat(sprintf("  [analysis_data] %d rows × %d cols\n", nrow(adata), ncol(adata)))
          cat(sprintf("  cols: %s\n", paste(names(adata), collapse = ", ")))
        } else {
          cat("  [analysis_data] <NULL>\n")
        }
        .dbg("analysis_spec$variable_roles",                    spec$variable_roles)
        .dbg("analysis_spec$specification_metadata$study_type", spec$specification_metadata$study_type)
        .dbg("analysis_spec$variable_roles$reference_levels",   spec$variable_roles$reference_levels)

      } else if (step == "step2") {
        .dbg("analysis_result$result_tables$table1_overall",     result$result_tables$table1_overall)
        .dbg("analysis_result$result_tables$table1_by_exposure", result$result_tables$table1_by_exposure)
        .dbg("analysis_result$result_tables$table1_by_outcome",  result$result_tables$table1_by_outcome)

      } else if (step == "step3") {
        .dbg("analysis_result$variable_investigation",        result$variable_investigation)
        .dbg("analysis_spec$variable_selection_specification", spec$variable_selection_specification)

      } else if (step == "step4") {
        .dbg("analysis_spec$variable_roles$final_model_covariates", spec$variable_roles$final_model_covariates)
        .dbg("analysis_spec$variable_roles$reference_levels",       spec$variable_roles$reference_levels)

      } else if (step == "step5") {
        .dbg("analysis_spec$model_design",             spec$model_design)
        .dbg("analysis_result$fitted_models$primary",  result$fitted_models$primary_model)
        .dbg("analysis_result$run_status",             result$run_status)

      } else if (step == "step6") {
        .dbg("analysis_result$result_plots$diagnostic_plots", result$result_plots$diagnostic_plots)
        .dbg("analysis_result$inference_summary",             result$inference_summary)

      } else if (step == "step7") {
        .dbg("analysis_result$result_tables",    result$result_tables)
        .dbg("analysis_result$inference_summary", result$inference_summary)

      } else if (step == "step8") {
        .dbg("analysis_spec (full)", spec)
        if (!is.null(result)) {
          cat(sprintf("  [analysis_result keys] %s\n", paste(names(result), collapse = ", ")))
        } else {
          cat("  [analysis_result] <NULL>\n")
        }
      }

      cat("════════════════════════════════════════════════\n\n")
    }, ignoreInit = TRUE)

    # ── Cross-tab navigation (requested by modules via shared_state$requested_tab) ─
    shiny::observeEvent(shared_state$requested_tab, {
      req(!is.null(shared_state$requested_tab))
      tab <- shared_state$requested_tab
      if (tab == "report") {
        bslib::nav_select("main_navbar", "explore")
        bslib::nav_select("explore_tabs", "report")
      } else {
        bslib::nav_select("main_navbar", tab)
      }
      shared_state$requested_tab <- NULL
    }, ignoreNULL = TRUE, ignoreInit = TRUE)

    # ── Session cleanup: remove thumbnail temp files on exit ──────────────────
    session$onSessionEnded(function() {
      paths <- vapply(shiny::isolate(shared_state$custom_report_items),
                      `[[`, character(1), "thumb_path")
      unlink(paths[file.exists(paths)])
    })

    # Wire all modules — each is a sibling, none calls another's server.
    column_manager_server("column_manager",         shared_state)
    transform_variables_server("transform_variables", shared_state)
    row_filter_server("row_filter",                 shared_state)
    data_preview_server("data_preview",             shared_state)
    prepare_confirm_server("prepare_confirm",       shared_state)
    describe_controls_server("describe_controls",         shared_state)
    relationship_controls_server("relationship_controls", shared_state)
    trend_controls_server("trend_controls",               shared_state)
    explore_output_server("explore_output",   shared_state)
    report_server("report",                   shared_state)
    analysis_main_server("analysis_main",     shared_state)
  }

  shiny::shinyApp(ui = ui, server = server)
}
