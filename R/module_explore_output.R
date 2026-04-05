#' Explore Output Module
#'
#' Main panel for the Explore stage. Observes `shared_state$plot_specification`
#' and renders the plot and the variable summary table (via `reactable`). Also
#' shows a "dataset has changed — re-run" notice when
#' `shared_state$explore_needs_refresh` is TRUE.
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
        shiny::plotOutput(ns("main_plot"), height = "500px", width = "100%")
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
      shiny::req(!is.null(spec), !is.null(dataset))

      # Read aesthetic values directly — creates reactive dependencies so that
      # palette/legend changes re-render without requiring a button re-click.
      # Do NOT use isolate() here: it can return a stale value when this reactive
      # re-runs due to an aesthetic change.
      color_palette    <- shared_state$color_palette
      show_data_labels <- shared_state$show_data_labels
      show_legend      <- shared_state$show_legend
      legend_position  <- shared_state$legend_position

      spec_with_aesthetics <- modifyList(spec, list(
        color_palette    = color_palette,
        show_data_labels = show_data_labels,
        show_legend      = show_legend,
        legend_position  = legend_position
      ))

      gg <- render_plot(spec_with_aesthetics, dataset)

      # Store the raw ggplot for report export
      shared_state$active_plot <- gg

      # Clear the stale flag now that we've rendered
      shared_state$explore_needs_refresh <- FALSE

      gg
    })

    output$main_plot <- shiny::renderPlot({
      gg <- current_plot()
      shiny::req(!is.null(gg))

      spec_now <- shiny::isolate(shared_state$plot_specification)

      # Suppress legend for plot types where axes/facet strips make it redundant.
      # This overrides the user's show_legend toggle for these types only.
      is_violin        <- !is.null(spec_now) && identical(spec_now$plot_type, "violin_jitter")
      is_scatter_strat <- !is.null(spec_now) &&
        identical(spec_now$plot_type, "scatter_loess") &&
        !is.null(spec_now$stratify_by)

      if (is_violin || is_scatter_strat) {
        gg <- gg + ggplot2::theme(legend.position = "none")
      }

      gg
    }, res = 96)


    # ── Render the summary table ──────────────────────────────────────────────
    output$summary_table <- reactable::renderReactable({
      spec    <- shared_state$plot_specification
      dataset <- shared_state$dataset_working
      types   <- shared_state$column_types

      shiny::req(!is.null(spec), !is.null(dataset))

      # For trend plots the meaningful variable is column_b (the trend variable).
      # Fall back to column_a (the datetime timestamp) for trend_count (no column_b).
      trend_types <- c("trend_count", "trend_numeric", "trend_proportion")
      is_trend    <- !is.null(spec$plot_type) && spec$plot_type %in% trend_types
      primary     <- if (is_trend && !is.null(spec$column_b)) spec$column_b else spec$column_a
      col_type    <- if (primary %in% names(types)) types[[primary]] else "datetime"

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
