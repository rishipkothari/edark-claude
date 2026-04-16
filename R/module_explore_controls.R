#' Explore Controls — Describe and Relationship Modules
#'
#' Sidebar panels for the Explore stage.
#'
#' `describe_controls_ui/server`: Univariate variable description.
#' `relationship_controls_ui/server`: Bivariate relationship / correlation.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_explore_controls
NULL

# ── Shared aesthetics UI helper ───────────────────────────────────────────────
# Used by both Describe and Relationship modules.
.aesthetics_accordion <- function(ns) {
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
}

# ── Shared aesthetics server helper ───────────────────────────────────────────
.aesthetics_observers <- function(input, shared_state) {
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
}

# ── Sidebar label helper ──────────────────────────────────────────────────────
.sidebar_label <- function(text) {
  shiny::tags$p(text, class = "text-muted small text-uppercase fw-semibold mt-2 mb-1")
}


# ==============================================================================
# Describe module
# ==============================================================================

#' @rdname module_explore_controls
#' @export
describe_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(

    .sidebar_label("Variable"),
    shiny::uiOutput(ns("primary_var_picker")),
    shiny::uiOutput(ns("bar_display_ui")),

    .sidebar_label("Stratify By"),
    shiny::uiOutput(ns("stratify_picker")),

    shiny::tags$div(class = "mt-3",
      shiny::actionButton(
        ns("describe_btn"),
        label = "Describe",
        icon  = shiny::icon("chart-bar"),
        class = "btn-primary w-100"
      )
    ),

    shiny::tags$div(class = "mt-3",
      .aesthetics_accordion(ns)
    )
  )
}


#' @rdname module_explore_controls
#' @export
describe_controls_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    eligible_cols <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types %in% c("numeric", "factor")]
    })

    output$primary_var_picker <- shiny::renderUI({
      shinyWidgets::pickerInput(
        ns("primary_variable"),
        choices = eligible_cols(),
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      primary     <- input$primary_variable
      factor_cols <- setdiff(factor_cols, primary)
      cols_with_none <- c("None" = "", factor_cols)
      shinyWidgets::pickerInput(
        ns("stratify_variable"),
        label   = NULL,
        choices = cols_with_none,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$bar_display_ui <- shiny::renderUI({
      pv    <- input$primary_variable
      types <- shared_state$column_types
      if (is.null(pv) || !pv %in% names(types) || types[[pv]] != "factor") return(NULL)
      shinyWidgets::radioGroupButtons(
        ns("bar_display"),
        label    = "Factor statistic:",
        choices  = c("Count" = "count", "Proportion" = "proportion"),
        selected = if (!is.null(input$bar_display)) input$bar_display else "count",
        size     = "sm",
        width    = "100%"
      )
    })

    shiny::observeEvent(input$primary_variable, {
      shared_state$primary_variable <- input$primary_variable
    }, ignoreNULL = TRUE)

    shiny::observeEvent(input$stratify_variable, {
      val <- input$stratify_variable
      shared_state$stratify_variable <- if (is.null(val) || val == "") NULL else val
    })

    shiny::observeEvent(input$describe_btn, {
      shiny::req(input$primary_variable)
      shared_state$bar_display        <- input$bar_display
      shared_state$plot_specification <- build_univariate_plot_spec(shared_state)
    })

    .aesthetics_observers(input, shared_state)
  })
}


# ==============================================================================
# Relationship module
# ==============================================================================

#' @rdname module_explore_controls
#' @export
relationship_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(

    .sidebar_label("Primary Variable"),
    shiny::uiOutput(ns("primary_var_picker")),
    shinyWidgets::radioGroupButtons(
      ns("primary_role"),
      label    = NULL,
      choices  = c("Exposure (X)" = "exposure",
                   "Outcome (Y)"  = "outcome"),
      selected = "exposure",
      size     = "sm",
      width    = "100%"
    ),

    .sidebar_label("Secondary Variable"),
    shiny::uiOutput(ns("secondary_var_picker")),
    shiny::uiOutput(ns("bar_display_ui")),

    .sidebar_label("Stratify By"),
    shiny::uiOutput(ns("stratify_picker")),

    shiny::tags$div(class = "mt-3",
      shiny::actionButton(
        ns("plot_btn"),
        label = "Plot Relationship",
        icon  = shiny::icon("chart-line"),
        class = "btn-primary w-100"
      )
    ),

    shiny::tags$div(class = "mt-3",
      .aesthetics_accordion(ns)
    )
  )
}


#' @rdname module_explore_controls
#' @export
relationship_controls_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    eligible_cols <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types %in% c("numeric", "factor")]
    })

    output$primary_var_picker <- shiny::renderUI({
      shinyWidgets::pickerInput(
        ns("primary_variable"),
        choices = eligible_cols(),
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$secondary_var_picker <- shiny::renderUI({
      primary <- input$primary_variable
      choices <- setdiff(eligible_cols(), primary)
      shinyWidgets::pickerInput(
        ns("secondary_variable"),
        choices = choices,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      cols_with_none <- c("None" = "", factor_cols)
      shinyWidgets::pickerInput(
        ns("stratify_variable"),
        label   = NULL,
        choices = cols_with_none,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$bar_display_ui <- shiny::renderUI({
      pv    <- input$primary_variable
      types <- shared_state$column_types
      if (is.null(pv) || !pv %in% names(types) || types[[pv]] != "factor") return(NULL)
      shinyWidgets::radioGroupButtons(
        ns("bar_display"),
        label    = "Factor statistic:",
        choices  = c("Count" = "count", "Proportion" = "proportion"),
        selected = if (!is.null(input$bar_display)) input$bar_display else "count",
        size     = "sm",
        width    = "100%"
      )
    })

    shiny::observeEvent(input$primary_variable, {
      shared_state$primary_variable <- input$primary_variable
    }, ignoreNULL = TRUE)

    shiny::observeEvent(input$primary_role, {
      shared_state$primary_variable_role <- input$primary_role
    })

    shiny::observeEvent(input$stratify_variable, {
      val <- input$stratify_variable
      shared_state$stratify_variable <- if (is.null(val) || val == "") NULL else val
    })

    shiny::observeEvent(input$secondary_variable, {
      shared_state$secondary_variable <- input$secondary_variable
    }, ignoreNULL = TRUE)

    shiny::observeEvent(input$plot_btn, {
      shiny::req(input$primary_variable, input$secondary_variable)
      shared_state$bar_display        <- input$bar_display
      shared_state$plot_specification <- build_bivariate_plot_spec(shared_state)
    })

    .aesthetics_observers(input, shared_state)
  })
}
