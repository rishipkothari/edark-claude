#' Explore Controls — Describe and Relationship Modules
#'
#' Sidebar panels for the Explore stage.
#'
#' `describe_controls_ui/server`: Univariate variable description.
#' `relationship_controls_ui/server`: Bivariate relationship / correlation.
#'
#' Both modes write the same `shared_state` fields - `primary_variable`,
#' `stratify_variable`, `bar_display` - so whichever one wrote last used to
#' win. Switching from Describe to Correlate and clicking Plot Relationship
#' drew Correlate's secondary variable against Describe's leftover primary and
#' stratify, and switching back did the mirror image. Each mode now publishes
#' *all* the fields it owns from its own inputs, and clears the ones it does
#' not own, both when its panel becomes active and again on its button click -
#' so the spec is built from what is on screen, never from what the other
#' panel left behind.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#' @param active_mode A reactive returning the id of the Explore config-pane
#'   panel currently on screen (`"describe"`, `"correlate"`, `"trend"`), or
#'   `NULL` when the caller does not track it.
#'
#' @name module_explore_controls
NULL


# Read a "None"-able picker: "" and NULL both mean no selection.
.explore_opt <- function(x) if (is.null(x) || !nzchar(x)) NULL else x


# ==============================================================================
# Describe module
# ==============================================================================

#' @rdname module_explore_controls
#' @export
describe_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(

    edark_section_label("Variable"),
    shiny::uiOutput(ns("primary_var_picker")),
    shiny::uiOutput(ns("bar_display_ui")),

    edark_section_label("Stratify By"),
    shiny::uiOutput(ns("stratify_picker")),

    shiny::tags$div(class = "mt-3",
      edark_button(ns, "describe_btn", "Describe", icon = "chart-bar")
    )
  )
}


#' @rdname module_explore_controls
#' @export
describe_controls_server <- function(id, shared_state, active_mode = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Everything this mode owns, taken from this mode's own inputs. Describe is
    # univariate, so it also clears secondary_variable rather than leaving
    # Correlate's behind.
    publish_state <- function() {
      shared_state$primary_variable   <- input$primary_variable
      shared_state$stratify_variable  <- .explore_opt(input$stratify_variable)
      shared_state$secondary_variable <- NULL
      shared_state$bar_display        <- input$bar_display %||% "count"
    }

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
      shared_state$stratify_variable <- .explore_opt(input$stratify_variable)
    })

    # Reclaim the shared fields the moment this panel is shown, so the info
    # pane and any later read reflect Describe rather than the mode the user
    # just left. Skipped until the pickers exist: a panel that has never been
    # opened has suspended outputs and therefore no inputs to publish.
    if (!is.null(active_mode)) {
      shiny::observeEvent(active_mode(), {
        if (!identical(active_mode(), "describe")) return()
        if (is.null(input$primary_variable)) return()
        publish_state()
      }, ignoreInit = TRUE)
    }

    shiny::observeEvent(input$describe_btn, {
      shiny::req(input$primary_variable)
      publish_state()
      shared_state$plot_specification <- build_univariate_plot_spec(shared_state)
    })

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

    edark_section_label("Primary Variable"),
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

    edark_section_label("Secondary Variable"),
    shiny::uiOutput(ns("secondary_var_picker")),
    shiny::uiOutput(ns("bar_display_ui")),

    edark_section_label("Stratify By"),
    shiny::uiOutput(ns("stratify_picker")),

    shiny::tags$div(class = "mt-3",
      edark_button(ns, "plot_btn", "Plot Relationship", icon = "chart-line")
    )
  )
}


#' @rdname module_explore_controls
#' @export
relationship_controls_server <- function(id, shared_state, active_mode = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Everything this mode owns, taken from this mode's own inputs.
    publish_state <- function() {
      shared_state$primary_variable      <- input$primary_variable
      shared_state$secondary_variable    <- input$secondary_variable
      shared_state$primary_variable_role <- input$primary_role %||% "exposure"
      shared_state$stratify_variable     <- .explore_opt(input$stratify_variable)
      shared_state$bar_display           <- input$bar_display %||% "count"
    }

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
      shared_state$stratify_variable <- .explore_opt(input$stratify_variable)
    })

    shiny::observeEvent(input$secondary_variable, {
      shared_state$secondary_variable <- input$secondary_variable
    }, ignoreNULL = TRUE)

    # See the matching block in describe_controls_server().
    if (!is.null(active_mode)) {
      shiny::observeEvent(active_mode(), {
        if (!identical(active_mode(), "correlate")) return()
        if (is.null(input$primary_variable) || is.null(input$secondary_variable)) return()
        publish_state()
      }, ignoreInit = TRUE)
    }

    shiny::observeEvent(input$plot_btn, {
      shiny::req(input$primary_variable, input$secondary_variable)
      publish_state()
      shared_state$plot_specification <- build_bivariate_plot_spec(shared_state)
    })

  })
}
