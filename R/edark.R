#' Launch the EDARK exploratory data analysis GUI
#'
#' The primary entry point for the package. Validates the input dataset,
#' auto-casts column types, initialises the session-scoped shared state, and
#' launches the Shiny application.
#'
#' @param dataset A `data.frame` or `tibble`. Required. The dataset to explore.
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
#' edark(mtcars)
#' edark(palmerpenguins::penguins, max_factor_levels = 10)
#' }
edark <- function(dataset, max_factor_levels = 20) {

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
          explore_controls_ui("explore_controls")
        ),
        explore_output_ui("explore_output")
      )
    ),

    # ── Tab 3: Report (post-MVP placeholder) ────────────────────────────────
    bslib::nav_panel(
      value = "report",
      title = shiny::tagList(shiny::icon("file-export"), " 3 \u00b7 Report"),
      bslib::card(
        bslib::card_body(
          shiny::tags$p(
            class = "text-muted",
            shiny::icon("clock"),
            " Report generation is coming in a future release."
          )
        )
      )
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

      # Explore stage
      primary_variable        = NULL,
      primary_variable_role   = "exposure",
      secondary_variable      = NULL,
      stratify_variable       = NULL,
      trend_resolution        = "Day",

      # Plot state
      plot_specification      = NULL,
      active_plot             = NULL,
      variable_summary        = NULL,
      explore_needs_refresh   = FALSE,

      # Aesthetics
      color_palette           = "Set2",
      show_data_labels        = FALSE,
      show_legend             = TRUE,
      legend_position         = "right"
    )

    # Wire all modules — each is a sibling, none calls another's server.
    column_manager_server("column_manager",         shared_state)
    transform_variables_server("transform_variables", shared_state)
    row_filter_server("row_filter",                 shared_state)
    data_preview_server("data_preview",             shared_state)
    prepare_confirm_server("prepare_confirm",       shared_state)
    explore_controls_server("explore_controls", shared_state)
    explore_output_server("explore_output",   shared_state)
  }

  shiny::shinyApp(ui = ui, server = server)
}
