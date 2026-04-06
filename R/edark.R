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

    # ── Tab 1: Prepare ───────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "prepare",
      title = shiny::tagList(shiny::icon("sliders"), " 1 \u00b7 Prepare"),
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          title    = "Apply",
          position = "right",
          width    = 220,
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
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 320,
          bslib::navset_pill(
            bslib::nav_panel("Analyze", explore_controls_ui("explore_controls")),
            bslib::nav_panel("Trend",   trend_controls_ui("trend_controls"))
          )
        ),
        explore_output_ui("explore_output")
      )
    ),

    # ── Tab 3: Report ───────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "report",
      title = shiny::tagList(shiny::icon("file-export"), " 3 \u00b7 Report"),
      report_ui("report")
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
      requested_report_subtab = NULL      # navigate to report pill (full_report / custom_report)
    )

    # ── Prepare tab navigation guard ──────────────────────────────────────────
    # Auto-applies pending changes when the user switches prepare sub-tabs.
    # Invalid transforms block navigation (pipeline would mangle the column).
    last_prepare_tab <- shiny::reactiveVal("columns")
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
        shiny::showNotification("Changes applied.", type = "message", duration = 2)
      }
      last_prepare_tab(input$prepare_tabs)
    }, ignoreInit = TRUE)

    # ── Cross-tab navigation (requested by modules via shared_state$requested_tab) ─
    shiny::observeEvent(shared_state$requested_tab, {
      req(!is.null(shared_state$requested_tab))
      bslib::nav_select("main_navbar", shared_state$requested_tab)
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
    explore_controls_server("explore_controls", shared_state)
    trend_controls_server("trend_controls",   shared_state)
    explore_output_server("explore_output",   shared_state)
    report_server("report",                   shared_state)
  }

  shiny::shinyApp(ui = ui, server = server)
}
