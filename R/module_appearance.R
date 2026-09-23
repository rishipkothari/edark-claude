#' Appearance Module
#'
#' The app's single set of plot aesthetics controls, and the only writer of
#' the five aesthetic fields in `shared_state`.
#'
#' Before UI Stage 2 these controls existed four times - Describe, Trend, Full
#' Report and Custom Report - and the two Report copies used separate
#' `custom_*` inputs that were applied at generation time, so a generated
#' report did not match the plot on screen (D7, D9, F4 in
#' `PRD/BUILD_UI-redesign.md`).
#'
#' It sits as a panel of the Explore config pane alongside the mode panels
#' (Describe / Correlate / Trend) rather than stacked underneath one of them.
#' The mode panels are staged - nothing happens until that mode's button is
#' clicked - while everything here applies live, so keeping the two apart is
#' what removes the staged-vs-live collision described in
#' §BUILD_UI-redesign 2.6.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_appearance
NULL


#' @rdname module_appearance
#' @export
appearance_controls_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::tags$p(
      class = "text-muted small mb-3",
      "Applies to the plot on screen and to every report generated from it."
    ),
    edark_aesthetics_controls(ns)
  )
}


#' @rdname module_appearance
#' @export
appearance_controls_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    # Each observer is guarded with !identical() (§N1.2) so a re-render of the
    # control cannot spuriously invalidate everything that reads the plot.
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
  })
}


#' The aesthetics in force, as a plot-spec fragment
#'
#' Read wherever a plot or a report needs the current appearance: the Explore
#' plot, Full Report generation, and the snapshot written into a Custom Report
#' item at the moment it is added.
#'
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @return A named list of the five aesthetic fields.
#' @keywords internal
#' @noRd
edark_current_aesthetics <- function(shared_state) {
  list(
    ggplot_theme     = shared_state$ggplot_theme     %||% "minimal",
    color_palette    = shared_state$color_palette    %||% "Set2",
    show_data_labels = isTRUE(shared_state$show_data_labels),
    show_legend      = isTRUE(shared_state$show_legend),
    legend_position  = shared_state$legend_position  %||% "top"
  )
}
