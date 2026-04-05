#' Trend Controls Module
#'
#' Sidebar controls for the Trend tab in the Explore stage. Lets the user
#' pick a datetime timestamp, time resolution, a numeric or factor variable
#' to trend, an optional summary stat (numeric only), and an optional
#' stratification variable.
#'
#' @param id Module namespace id.
#' @param shared_state A Shiny `reactiveValues` object (the session-level
#'   shared state created in `edark.R`).
#'
#' @name module_trend_controls
#' @keywords internal
NULL


#' @rdname module_trend_controls
#' @export
trend_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(

    # ── Timestamp ───────────────────────────────────────────────────────────
    bslib::card(
      bslib::card_body(
        shiny::uiOutput(ns("timestamp_picker"))
      )
    ),

    # ── Resolution ──────────────────────────────────────────────────────────
    bslib::card(
      bslib::card_body(
        shiny::selectInput(
          ns("trend_resolution"),
          label   = "Time resolution:",
          choices = c("Hour", "Day", "Week", "Month", "Quarter", "Year"),
          selected = "Month"
        )
      )
    ),

    # ── Trend variable + stat picker ─────────────────────────────────────────
    bslib::card(
      bslib::card_body(
        shiny::uiOutput(ns("trend_var_picker")),
        shiny::uiOutput(ns("stat_picker_ui"))
      )
    ),

    # ── Stratify By ─────────────────────────────────────────────────────────
    bslib::card(
      bslib::card_body(
        shiny::uiOutput(ns("stratify_picker"))
      )
    ),

    # ── Plot button ─────────────────────────────────────────────────────────
    bslib::input_task_button(ns("plot_trend"), "Plot Trend",
                             icon = shiny::icon("chart-line")),

    # ── Aesthetics ───────────────────────────────────────────────────────────
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        "Plot Aesthetics",
        icon = shiny::icon("palette"),
        shinyWidgets::pickerInput(
          ns("color_palette"),
          label    = "Colour palette:",
          choices  = c("Set2", "Set1", "Dark2", "Paired", "Accent",
                       "Blues", "Greens", "Reds", "Purples"),
          selected = "Set2"
        ),
        shiny::checkboxInput(ns("show_data_labels"), "Show data labels", value = FALSE),
        shiny::checkboxInput(ns("show_legend"),      "Show legend",      value = TRUE),
        shinyWidgets::radioGroupButtons(
          ns("legend_position"),
          label    = "Legend position:",
          choices  = c("right", "left", "top", "bottom"),
          selected = "top",
          size     = "sm"
        )
      )
    )
  )
}


#' @rdname module_trend_controls
#' @export
trend_controls_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Populate pickers from working dataset ─────────────────────────────────
    datetime_cols <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types == "datetime"]
    })

    eligible_trend_cols <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types %in% c("numeric", "factor")]
    })

    output$timestamp_picker <- shiny::renderUI({
      cols <- datetime_cols()
      shinyWidgets::pickerInput(
        ns("trend_timestamp_variable"),
        label   = "Timestamp column:",
        choices = cols,
        options = shinyWidgets::pickerOptions(
          liveSearch  = TRUE,
          container   = "body",
          noneSelectedText = "Select date/time column"
        )
      )
    })

    output$trend_var_picker <- shiny::renderUI({
      choices <- c("None (event count)" = "", eligible_trend_cols())
      shinyWidgets::pickerInput(
        ns("trend_variable"),
        label   = "Trend variable (optional):",
        choices = choices,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    # Stat picker — only rendered when the selected trend variable is numeric
    output$stat_picker_ui <- shiny::renderUI({
      tv <- input$trend_variable
      shiny::req(!is.null(tv) && !identical(tv, ""))

      types <- shared_state$column_types
      if (!tv %in% names(types) || types[[tv]] != "numeric") return(NULL)

      shiny::selectInput(
        ns("trend_summary_stat"),
        label   = "Summary statistic:",
        choices = c(
          "Mean \u00b1 SD"      = "mean_sd",
          "Mean \u00b1 SE"      = "mean_se",
          "Mean \u00b1 95% CI"  = "mean_ci",
          "Median (IQR)"        = "median_iqr",
          "Count"               = "count",
          "Sum"                 = "sum",
          "Max"                 = "max",
          "Min"                 = "min"
        ),
        selected = shiny::isolate(shared_state$trend_summary_stat)
      )
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      cols_with_none <- c("None" = "", factor_cols)
      shinyWidgets::pickerInput(
        ns("trend_stratify_variable"),
        label   = "Stratify by (optional):",
        choices = cols_with_none,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })


    # ── Write control inputs into shared_state ────────────────────────────────
    shiny::observeEvent(input$trend_timestamp_variable, {
      val <- input$trend_timestamp_variable
      if (!identical(shared_state$trend_timestamp_variable, val))
        shared_state$trend_timestamp_variable <- val
    })

    shiny::observeEvent(input$trend_resolution, {
      val <- input$trend_resolution
      if (!identical(shared_state$trend_resolution, val))
        shared_state$trend_resolution <- val
    })

    shiny::observeEvent(input$trend_variable, {
      val <- if (is.null(input$trend_variable) || identical(input$trend_variable, ""))
        NULL else input$trend_variable
      if (!identical(shared_state$trend_variable, val))
        shared_state$trend_variable <- val
    })

    shiny::observeEvent(input$trend_summary_stat, {
      val <- input$trend_summary_stat
      if (!is.null(val) && !identical(shared_state$trend_summary_stat, val))
        shared_state$trend_summary_stat <- val
    })

    shiny::observeEvent(input$trend_stratify_variable, {
      val <- if (is.null(input$trend_stratify_variable) ||
                   identical(input$trend_stratify_variable, ""))
        NULL else input$trend_stratify_variable
      if (!identical(shared_state$trend_stratify_variable, val))
        shared_state$trend_stratify_variable <- val
    })

    # Aesthetics — shared with Analyse tab (same shared_state fields)
    shiny::observeEvent(input$color_palette, {
      val <- input$color_palette
      if (!is.null(val) && !identical(shared_state$color_palette, val))
        shared_state$color_palette <- val
    })

    shiny::observeEvent(input$show_data_labels, {
      val <- isTRUE(input$show_data_labels)
      if (!identical(shared_state$show_data_labels, val))
        shared_state$show_data_labels <- val
    })

    shiny::observeEvent(input$show_legend, {
      val <- isTRUE(input$show_legend)
      if (!identical(shared_state$show_legend, val))
        shared_state$show_legend <- val
    })

    shiny::observeEvent(input$legend_position, {
      val <- input$legend_position
      if (!is.null(val) && !identical(shared_state$legend_position, val))
        shared_state$legend_position <- val
    })


    # ── Plot Trend button ─────────────────────────────────────────────────────
    shiny::observeEvent(input$plot_trend, {
      shiny::req(!is.null(shared_state$trend_timestamp_variable),
                 nchar(shared_state$trend_timestamp_variable) > 0)
      shared_state$plot_specification <- build_trend_plot_spec(shared_state)
    })

  })
}
