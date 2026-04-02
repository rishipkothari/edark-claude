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


# Maps a legend_position string ("top"/"bottom"/"left"/"right") to a plotly
# legend layout list. ggplotly() ignores ggplot2's theme(legend.position),
# so this is the only way to honour the user's choice after conversion.
.plotly_legend_config <- function(position) {
  switch(position,
    top    = list(orientation = "h", x = 0.5,   xanchor = "center", y = 1.02,  yanchor = "bottom"),
    bottom = list(orientation = "h", x = 0.5,   xanchor = "center", y = -0.15, yanchor = "top"),
    right  = list(orientation = "v", x = 1.02,  xanchor = "left",   y = 0.5,   yanchor = "middle"),
    left   = list(orientation = "v", x = -0.15, xanchor = "right",  y = 0.5,   yanchor = "middle"),
    list()
  )
}


#' @rdname module_explore_output
#' @export
explore_output_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # Stale-data notice (hidden until needed)
    shiny::uiOutput(ns("refresh_notice")),

    # Plot title — rendered separately so it sits above the plotly div and
    # never overlaps facet strips (ggplotly has no reliable title-to-strip gap)
    shiny::uiOutput(ns("plot_title")),

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


    # ── Plot title (above the card, outside plotly) ───────────────────────────
    output$plot_title <- shiny::renderUI({
      spec <- shared_state$plot_specification
      shiny::req(!is.null(spec))

      title <- spec$column_a
      if (!is.null(spec$column_b)) {
        title <- paste0(title, "  \u00d7  ", spec$column_b)
      }
      if (!is.null(spec$stratify_by)) {
        title <- paste0(title, "  \u00b7  stratified by ", spec$stratify_by)
      }

      shiny::tags$h5(
        title,
        style = "margin: 8px 4px 4px 4px; color: #444; font-weight: 600;"
      )
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

    output$main_plot <- plotly::renderPlotly({
      gg <- current_plot()
      shiny::req(!is.null(gg))

      margins      <- list(l = 60, r = 20, t = 40, b = 60)
      spec_now     <- shiny::isolate(shared_state$plot_specification)
      show_leg     <- shiny::isolate(shared_state$show_legend)
      leg_position <- shiny::isolate(shared_state$legend_position)

      if (inherits(gg, "edark_two_panel")) {
        # ggplotly() silently drops patchwork's second panel — convert each
        # panel separately and combine with subplot().
        # QQ panel traces are hidden from the shared legend; only density
        # stratum colours appear. Legend position/visibility honours the
        # aesthetic panel selection.
        #
        # ggplotly() may suppress legend entries when both colour + fill scales
        # share the same name (known limitation). Force exactly one trace per
        # legendgroup visible on the left (density) panel.
        p_left <- plotly::ggplotly(gg$left)
        seen_groups <- character(0)
        for (i in seq_along(p_left$x$data)) {
          lg <- p_left$x$data[[i]]$legendgroup
          if (!is.null(lg) && nzchar(lg)) {
            if (!(lg %in% seen_groups)) {
              p_left$x$data[[i]]$showlegend <- TRUE
              seen_groups <- c(seen_groups, lg)
            } else {
              p_left$x$data[[i]]$showlegend <- FALSE
            }
          }
        }
        p_right <- plotly::style(plotly::ggplotly(gg$right), showlegend = FALSE)

        pl <- plotly::subplot(p_left, p_right,
                              nrows  = 1,
                              shareX = FALSE, shareY = FALSE,
                              titleX = TRUE,  titleY = TRUE,
                              widths = c(0.45, 0.55))

        if (isTRUE(show_leg)) {
          pl <- plotly::layout(pl, legend = .plotly_legend_config(leg_position))
        } else {
          pl <- plotly::style(pl, showlegend = FALSE)
        }
        pl |> plotly::layout(margin = margins)

      } else {
        pl <- plotly::ggplotly(gg)

        # Plot types where legend is always redundant (axes/facet strips cover it)
        is_violin        <- !is.null(spec_now) && identical(spec_now$plot_type, "violin_jitter")
        is_scatter_strat <- !is.null(spec_now) &&
          identical(spec_now$plot_type, "scatter_loess") &&
          !is.null(spec_now$stratify_by)

        if (is_violin || is_scatter_strat || !isTRUE(show_leg)) {
          pl <- plotly::style(pl, showlegend = FALSE)
          pl |> plotly::layout(margin = margins)
        } else {
          pl |> plotly::layout(
            legend = .plotly_legend_config(leg_position),
            margin = margins
          )
        }
      }
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
