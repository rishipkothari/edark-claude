#' Explore Output Module
#'
#' Main panel for the Explore stage. Observes `shared_state$plot_specification`
#' and renders the plot (via `plotly::ggplotly()`) and the variable summary
#' table (via `reactable`). Also shows a "dataset has changed — re-run"
#' notice when `shared_state$explore_needs_refresh` is TRUE.
#'
#' Aesthetic changes (palette, labels, legend) re-render the plot without
#' rebuilding the spec — the spec is already stored in shared_state.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_explore_output
NULL


#' @rdname module_explore_output
#' @export
explore_output_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # Stale-data notice (hidden until needed)
    shiny::uiOutput(ns("refresh_notice")),

    # Plot area
    bslib::card(
      bslib::card_body(
        waiter::spin_flower() |> waiter::waiter_on_busy(),
        plotly::plotlyOutput(ns("main_plot"), height = "500px")
      )
    ),

    shiny::br(),

    # Summary statistics table
    bslib::card(
      bslib::card_header(shiny::icon("table"), " Variable Summary"),
      bslib::card_body(
        reactable::reactableOutput(ns("summary_table"))
      )
    )
  )
}


#' @rdname module_explore_output
#' @export
explore_output_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Stale-data notice ─────────────────────────────────────────────────────
    output$refresh_notice <- shiny::renderUI({
      if (isTRUE(shared_state$explore_needs_refresh)) {
        bslib::card(
          class = "border-warning mb-3",
          bslib::card_body(
            shiny::icon("triangle-exclamation", class = "text-warning"),
            shiny::tags$strong(" Dataset has changed."),
            " Re-run your analysis to update the plots."
          )
        )
      }
    })


    # ── Render the plot ───────────────────────────────────────────────────────
    # Rerenders whenever the spec OR any aesthetic setting changes.
    current_plot <- shiny::reactive({
      spec    <- shared_state$plot_specification
      dataset <- shared_state$dataset_working

      # Aesthetic dependencies (cheap — spec already built, no data re-query)
      shared_state$color_palette
      shared_state$show_data_labels
      shared_state$show_legend
      shared_state$legend_position

      shiny::req(!is.null(spec), !is.null(dataset))

      # Rebuild the spec with the current aesthetic values so they're reflected
      # (The spec is re-read here, not mutated — shared_state$plot_specification
      # is only updated by the Controls module on button clicks.)
      spec_with_aesthetics <- modifyList(spec, list(
        color_palette    = shiny::isolate(shared_state$color_palette),
        show_data_labels = shiny::isolate(shared_state$show_data_labels),
        show_legend      = shiny::isolate(shared_state$show_legend),
        legend_position  = shiny::isolate(shared_state$legend_position)
      ))

      gg <- render_plot(spec_with_aesthetics, dataset)

      # Store the raw ggplot for report export
      shared_state$active_plot <- gg

      # Clear the stale flag now that we've rendered
      shared_state$explore_needs_refresh <- FALSE

      gg
    })

    output$main_plot <- plotly::renderPlotly({
      gg <- current_plot()
      shiny::req(!is.null(gg))
      plotly::ggplotly(gg) |>
        plotly::layout(
          margin = list(l = 60, r = 20, t = 40, b = 60)
        )
    })


    # ── Render the summary table ──────────────────────────────────────────────
    output$summary_table <- reactable::renderReactable({
      spec    <- shared_state$plot_specification
      dataset <- shared_state$dataset_working
      types   <- shared_state$column_types

      shiny::req(!is.null(spec), !is.null(dataset))

      primary  <- spec$column_a  # column_a is always the "describe this" column
      col_type <- types[[primary]]

      summary_df <- build_variable_summary(dataset, primary, col_type)

      reactable::reactable(
        summary_df,
        compact    = TRUE,
        bordered   = TRUE,
        striped    = TRUE,
        highlight  = TRUE,
        pagination = FALSE
      )
    })
  })
}
