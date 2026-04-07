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

    # ── Timestamp ─────────────────────────────────────────────────────────────
    shiny::tags$p("Timestamp", class = "text-muted small text-uppercase fw-semibold mt-0 mb-1"),
    shiny::uiOutput(ns("timestamp_picker")),

    # ── Resolution ────────────────────────────────────────────────────────────
    shiny::tags$p("Resolution", class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
    shiny::selectInput(
      ns("trend_resolution"),
      label    = NULL,
      choices  = c("Hour", "Day", "Week", "Month", "Quarter", "Year"),
      selected = "Month"
    ),

    # ── Trend variable + stat picker ──────────────────────────────────────────
    shiny::tags$p("Trend Variable", class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
    shiny::uiOutput(ns("trend_var_picker")),
    shiny::uiOutput(ns("bar_display_ui")),
    shiny::uiOutput(ns("stat_picker_ui")),

    # ── Options ───────────────────────────────────────────────────────────────
    shiny::tags$p("Options", class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
    shiny::uiOutput(ns("stratify_picker")),
    shiny::uiOutput(ns("zero_baseline_ui")),

    # ── Plot button ───────────────────────────────────────────────────────────
    shiny::tags$div(class = "mt-3",
      bslib::input_task_button(ns("plot_trend"), "Plot Trend",
                               icon = shiny::icon("chart-line"))
    ),

    # ── Aesthetics ───────────────────────────────────────────────────────────
    bslib::accordion(
      open = FALSE,
      bslib::accordion_panel(
        "Plot Aesthetics",
        icon = shiny::icon("palette"),
        shinyWidgets::pickerInput(
          ns("ggplot_theme"),
          label    = "Plot theme:",
          choices  = c(
            "Minimal"          = "minimal",
            "Ipsum"            = "ipsum",
            "Ipsum RC"         = "ipsum_rc",
            "Publication"      = "publication",
            "Cowplot"          = "cowplot",
            "Economist"        = "economist",
            "FiveThirtyEight"  = "fivethirtyeight",
            "Tufte"            = "tufte",
            "Modern"           = "modern"
          ),
          selected = "minimal"
        ),
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
        # label   = "Timestamp column:",
        choices = cols,
        options = shinyWidgets::pickerOptions(
          liveSearch  = TRUE,
          container   = "body",
          noneSelectedText = "Select date/time column"
        )
      )
    })

    output$trend_var_picker <- shiny::renderUI({
      shinyWidgets::pickerInput(
        ns("trend_variable"),
        # label   = "Trend variable:",
        choices = eligible_trend_cols(),
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
          "Mean only"           = "mean_only",
          "Mean \u00b1 SD"      = "mean_sd",
          "Mean \u00b1 SE"      = "mean_se",
          "Mean \u00b1 95% CI"  = "mean_ci",
          "Median only"         = "median_only",
          "Median (IQR)"        = "median_iqr",
          "Count"               = "count",
          "Sum"                 = "sum",
          "Max"                 = "max",
          "Min"                 = "min"
        ),
        selected = shiny::isolate(shared_state$trend_summary_stat)
      )
    })

    # Factor statistic picker + impute zero checkbox — only shown when trend variable is a factor
    output$bar_display_ui <- shiny::renderUI({
      tv    <- input$trend_variable
      types <- shared_state$column_types
      if (is.null(tv) || !tv %in% names(types) || types[[tv]] != "factor") return(NULL)
      shiny::tagList(
        shinyWidgets::radioGroupButtons(
          ns("bar_display"),
          label    = "Factor statistic:",
          choices  = c("Count" = "count", "Proportion" = "proportion"),
          selected = if (!is.null(input$bar_display)) input$bar_display else "count",
          size     = "sm",
          width    = "100%"
        ),
        shiny::checkboxInput(
          ns("trend_impute_zero"),
          label = "Impute 0 for missing timepoint data",
          value = if (!is.null(input$trend_impute_zero)) input$trend_impute_zero else TRUE
        )
      )
    })

    output$zero_baseline_ui <- shiny::renderUI({
      shiny::checkboxInput(ns("trend_zero_baseline"),
                           "Include zero baseline (y-axis)",
                           value = FALSE)
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      cols_with_none <- c("None" = "", factor_cols)
      shinyWidgets::pickerInput(
        ns("trend_stratify_variable"),
        label   = "Stratify by",
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

    shiny::observeEvent(input$trend_zero_baseline, {
      val <- isTRUE(input$trend_zero_baseline)
      if (!identical(shared_state$trend_zero_baseline, val))
        shared_state$trend_zero_baseline <- val
    })

    shiny::observeEvent(input$trend_impute_zero, {
      val <- isTRUE(input$trend_impute_zero)
      if (!identical(shared_state$trend_impute_zero, val))
        shared_state$trend_impute_zero <- val
    })

    shiny::observeEvent(input$trend_stratify_variable, {
      val <- if (is.null(input$trend_stratify_variable) ||
                   identical(input$trend_stratify_variable, ""))
        NULL else input$trend_stratify_variable
      if (!identical(shared_state$trend_stratify_variable, val))
        shared_state$trend_stratify_variable <- val
    })

    # Aesthetics — shared with Analyse tab (same shared_state fields)
    shiny::observeEvent(input$ggplot_theme, {
      val <- input$ggplot_theme
      if (!is.null(val) && !identical(shared_state$ggplot_theme, val))
        shared_state$ggplot_theme <- val
    })

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
                 nchar(shared_state$trend_timestamp_variable) > 0,
                 !is.null(shared_state$trend_variable),
                 nchar(shared_state$trend_variable) > 0)
      shared_state$bar_display        <- input$bar_display
      shared_state$plot_specification <- build_trend_plot_spec(shared_state)
    })

  })
}
