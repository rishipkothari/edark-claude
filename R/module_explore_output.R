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

    # Action button row (right-justified, above plot card)
    shiny::div(
      class = "d-flex justify-content-end align-items-center gap-2 mb-2",
      shiny::downloadButton(
        ns("save_plot_btn"), "Save Plot",
        icon  = shiny::icon("download"),
        class = "btn-sm btn-outline-primary"
      ),
      shiny::actionButton(
        ns("copy_plot_btn"), "Copy to Clipboard",
        icon  = shiny::icon("copy"),
        class = "btn-sm btn-outline-primary"
      ),
      shiny::actionButton(
        ns("add_to_custom_btn"), "Add to Custom Report",
        icon  = shiny::icon("plus"),
        class = "btn-sm btn-outline-primary"
      ),
      shiny::uiOutput(ns("view_report_btn_ui"))
    ),

    # JS for copy-to-clipboard: reads the rendered plot <img> and writes to clipboard
    shiny::tags$script(shiny::HTML(paste0(
      "$(document).on('click', '#", ns("copy_plot_btn"), "', function() {",
      "  var imgEl = document.querySelector('#", ns("main_plot"), " img');",
      "  if (!imgEl) { alert('No plot to copy. Run a plot first.'); return; }",
      "  fetch(imgEl.src)",
      "    .then(function(r) { return r.blob(); })",
      "    .then(function(blob) {",
      "      return navigator.clipboard.write([new ClipboardItem({'image/png': blob})]);",
      "    })",
      "    .then(function() {",
      "      var btn = document.querySelector('#", ns("copy_plot_btn"), "');",
      "      var orig = btn.innerHTML;",
      "      btn.innerHTML = '<i class=\"fa fa-check\"></i> Copied!';",
      "      setTimeout(function() { btn.innerHTML = orig; }, 1800);",
      "    })",
      "    .catch(function(e) { alert('Clipboard write failed: ' + e.message); });",
      "});"
    ))),

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
      ggplot_theme        <- shared_state$ggplot_theme
      color_palette       <- shared_state$color_palette
      show_data_labels    <- shared_state$show_data_labels
      show_legend         <- shared_state$show_legend
      legend_position     <- shared_state$legend_position
      trend_zero_baseline <- shared_state$trend_zero_baseline

      spec_with_aesthetics <- modifyList(spec, list(
        ggplot_theme        = ggplot_theme,
        color_palette       = color_palette,
        show_data_labels    = show_data_labels,
        show_legend         = show_legend,
        legend_position     = legend_position,
        trend_zero_baseline = trend_zero_baseline
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


    # ── Save Plot download ────────────────────────────────────────────────────
    output$save_plot_btn <- shiny::downloadHandler(
      filename = function() {
        spec <- shiny::isolate(shared_state$plot_specification)
        stem <- if (!is.null(spec$column_a)) spec$column_a else "plot"
        if (!is.null(spec$column_b)) stem <- paste0(stem, "_x_", spec$column_b)
        paste0("edark_", stem, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".png")
      },
      content = function(file) {
        gg <- shiny::isolate(shared_state$active_plot)
        if (is.null(gg)) stop("No plot to save. Run a plot first.")
        ggplot2::ggsave(file, plot = gg, width = 16, height = 9,
                        units = "in", dpi = 150)
      }
    )

    # ── Custom report buttons ─────────────────────────────────────────────────

    # "View Report" button — rendered dynamically so its badge stays live
    output$view_report_btn_ui <- shiny::renderUI({
      n     <- length(shared_state$custom_report_items)
      label <- if (n > 0)
        shiny::tagList("View Report",
                       shiny::tags$span(class = "badge bg-primary ms-1", n))
      else "View Report"
      shiny::actionButton(
        ns("view_report_btn"), label = label,
        icon  = shiny::icon("file-export"),
        class = "btn-sm btn-outline-primary"
      )
    })

    # Add current plot to the custom report
    shiny::observeEvent(input$add_to_custom_btn, {
      spec <- shiny::isolate(shared_state$plot_specification)
      gg   <- shiny::isolate(shared_state$active_plot)

      if (is.null(spec) || is.null(gg)) {
        shiny::showNotification("No plot to add. Run a plot first.", type = "warning")
        return()
      }

      # Save thumbnail PNG (active_plot is always the patchwork, safe for ggsave)
      thumb_path <- tempfile(pattern = "edark_thumb_", fileext = ".png")
      ggplot2::ggsave(thumb_path, plot = gg, width = 4, height = 3,
                      units = "in", dpi = 96)

      # Build human-readable title from spec
      title <- spec$column_a
      if (!is.null(spec$column_b))    title <- paste0(title, " \u00d7 ", spec$column_b)
      if (!is.null(spec$stratify_by) && nzchar(spec$stratify_by))
        title <- paste0(title, " \u00b7 by ", spec$stratify_by)

      new_item <- list(
        id         = paste0("item_", as.numeric(Sys.time()), "_", sample.int(1e6, 1)),
        plot_spec  = spec,
        thumb_path = thumb_path,
        title      = title,
        added_at   = Sys.time()
      )

      shared_state$custom_report_items <- c(
        shiny::isolate(shared_state$custom_report_items),
        list(new_item)
      )

      n <- length(shared_state$custom_report_items)
      shiny::showNotification(
        paste0("\u2713 Added (", n, " item", if (n != 1) "s" else "", " in custom report)"),
        type = "message", duration = 3
      )
    })

    # Navigate to Report tab → Custom Report pill
    shiny::observeEvent(input$view_report_btn, {
      shared_state$requested_report_subtab <- "custom_report"
      if (!identical(shared_state$requested_tab, "report"))
        shared_state$requested_tab <- "report"
    })
  })
}
