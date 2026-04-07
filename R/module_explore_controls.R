#' Explore Controls Module
#'
#' Sidebar panel for the Explore stage. Provides inputs to select the primary
#' variable and its role, an optional stratification variable, an optional
#' secondary variable, and plot aesthetic controls. Clicking "Describe"
#' triggers a univariate plot; clicking "Plot Correlation" triggers a bivariate
#' plot.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_explore_controls
NULL


#' @rdname module_explore_controls
#' @export
explore_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(

    bslib::card(
      bslib::card_body(

        # ── Variable selection ──────────────────────────────────────────────────
        shiny::tags$p(class = "fw-semibold mb-1",
                      shiny::icon("crosshairs"), " Primary Variable"),
        shiny::uiOutput(ns("primary_var_picker")),
        # Role selector: Exposure (X) vs. Outcome (Y). This is used to determine which variable gets mapped to aesthetics in bivariate plots, and also informs the plot description.
        shinyWidgets::radioGroupButtons(
          ns("primary_role"),
          label    = "Role:",
          choices  = c("Exposure (X)" = "exposure",
                       "Outcome (Y)"  = "outcome"),
          selected = "exposure",
          size     = "sm",
          width    = "100%"
        ),
        shiny::tags$p(class = "fw-semibold mb-1",
                      shiny::icon("arrow-right-arrow-left"), " Correlate With"),
        shiny::uiOutput(ns("secondary_var_picker")),
        # When primary variable is a factor, show option to display counts vs. proportions
        shiny::uiOutput(ns("bar_display_ui")),
        # ── Action buttons ───────────────────────────────────────────────────────
        shiny::tags$p(class = "fw-semibold mb-1",
                      shiny::icon("chart-line"), " Actions"),
        shiny::actionButton(
          ns("describe_btn"),
          label = "Describe",
          icon  = shiny::icon("chart-bar"),
          class = "btn-primary w-75",
        ),
        shiny::actionButton(
          ns("plot_btn"),
          label = "Plot Correlation",
          icon  = shiny::icon("chart-line"),
          class = "btn-primary w-75",
        ),


        # ── Options ────────────────────────────────────────────────────
        
        shiny::tags$p(class = "fw-semibold mb-1",
                      shiny::icon("layer-group"), " Options"),
        # shiny::tags$p(class = "fw-semibold mb-1",
        #               shiny::icon("layer-group"), " Stratify By"),
        shiny::uiOutput(ns("stratify_picker"))

      )
    ),

    shiny::br(),

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


#' @rdname module_explore_controls
#' @export
explore_controls_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Populate pickers from working dataset ─────────────────────────────────
    # Only numeric and factor columns are eligible for Explore.
    # Datetime and character columns are reserved for future features.
    eligible_cols <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types %in% c("numeric", "factor")]
    })

    output$primary_var_picker <- shiny::renderUI({
      shinyWidgets::pickerInput(
        ns("primary_variable"),
        # label   = "Primary variable:",
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
        label   = "Stratify by",
        choices = cols_with_none,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$secondary_var_picker <- shiny::renderUI({
      # Exclude the primary variable from secondary choices
      primary  <- input$primary_variable
      choices  <- setdiff(eligible_cols(), primary)
      shinyWidgets::pickerInput(
        ns("secondary_variable"),
        # label   = "Secondary variable:",
        choices = choices,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })


    # Factor statistic picker — only shown when primary variable is a factor
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

    # ── Write control inputs into shared_state ────────────────────────────────
    # These fire on change so that aesthetics updates re-render the plot cheaply.
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

    shiny::observeEvent(input$ggplot_theme, {
      shared_state$ggplot_theme <- input$ggplot_theme
    })

    shiny::observeEvent(input$color_palette, {
      shared_state$color_palette <- input$color_palette
    })

    shiny::observeEvent(input$show_data_labels, {
      shared_state$show_data_labels <- input$show_data_labels
    })

    shiny::observeEvent(input$show_legend, {
      shared_state$show_legend <- input$show_legend
    })

    shiny::observeEvent(input$legend_position, {
      shared_state$legend_position <- input$legend_position
    })


    # ── Describe button: build univariate spec ────────────────────────────────
    shiny::observeEvent(input$describe_btn, {
      shiny::req(input$primary_variable)
      shared_state$bar_display        <- input$bar_display
      shared_state$plot_specification <- build_univariate_plot_spec(shared_state)
    })


    # ── Plot Correlation button: build bivariate spec ─────────────────────────
    shiny::observeEvent(input$plot_btn, {
      shiny::req(input$primary_variable, input$secondary_variable)
      shared_state$bar_display        <- input$bar_display
      shared_state$plot_specification <- build_bivariate_plot_spec(shared_state)
    })
  })
}
