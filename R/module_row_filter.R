#' Row Filter Module
#'
#' Allows the user to add row-filter criteria against any included column.
#' Numeric columns get a min/max range input; factor/character/logical columns
#' get a checkbox group of levels to retain. Multiple filters compose with AND
#' logic. All filters are staged — nothing is applied until "Apply & Proceed".
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_row_filter
NULL


#' @rdname module_row_filter
#' @export
row_filter_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    bslib::card_header(shiny::icon("filter"), " Row Filters"),
    bslib::card_body(
      shiny::fluidRow(
        shiny::column(8,
          shiny::uiOutput(ns("column_picker"))
        ),
        shiny::column(4,
          shiny::br(),
          shiny::actionButton(
            ns("add_filter"), "Add filter",
            icon  = shiny::icon("plus"),
            class = "btn-sm btn-outline-primary w-100"
          )
        )
      ),
      shiny::hr(),
      # Live row count feedback
      shiny::uiOutput(ns("row_count_badge")),
      shiny::br(),
      # Active filter widgets render here
      shiny::uiOutput(ns("active_filters"))
    )
  )
}


#' @rdname module_row_filter
#' @export
row_filter_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Column picker: only included columns ─────────────────────────────────
    output$column_picker <- shiny::renderUI({
      included <- shared_state$included_columns
      shinyWidgets::pickerInput(
        ns("filter_column"),
        label   = "Add filter for column:",
        choices = included,
        options = shinyWidgets::pickerOptions(
          liveSearch = TRUE, container = "body"
        )
      )
    })


    # ── Row count badge ───────────────────────────────────────────────────────
    # Recompute the row count whenever filter specs change
    filtered_n <- shiny::reactive({
      specs   <- shared_state$row_filter_specs
      dataset <- shared_state$dataset_original
      if (length(specs) == 0) return(nrow(dataset))
      tryCatch(
        nrow(.apply_row_filters_preview(dataset, specs)),
        error = function(e) NA_integer_
      )
    })

    output$row_count_badge <- shiny::renderUI({
      n_orig <- nrow(shared_state$dataset_original)
      n_filt <- filtered_n()
      colour <- if (!is.na(n_filt) && n_filt < n_orig) "warning" else "success"
      shiny::tags$span(
        class = paste0("badge bg-", colour, " fs-6"),
        if (is.na(n_filt)) "Error in filters" else
          paste0(format(n_filt, big.mark = ","), " / ",
                 format(n_orig, big.mark = ","), " rows retained")
      )
    })


    # ── Add filter button ─────────────────────────────────────────────────────
    shiny::observeEvent(input$add_filter, {
      col     <- input$filter_column
      dataset <- shared_state$dataset_original
      types   <- shared_state$column_types

      if (is.null(col) || col == "") return()
      # Don't add a duplicate
      if (!is.null(shared_state$row_filter_specs[[col]])) return()

      col_type <- types[[col]]
      x        <- dataset[[col]]

      if (col_type == "numeric") {
        spec <- list(
          type = "numeric",
          min  = min(x, na.rm = TRUE),
          max  = max(x, na.rm = TRUE)
        )
      } else {
        # factor, character, logical
        levels_present <- as.character(sort(unique(x[!is.na(x)])))
        spec <- list(
          type           = "categorical",
          levels_all     = levels_present,
          levels_selected = levels_present   # default: keep all
        )
      }

      specs      <- shared_state$row_filter_specs
      specs[[col]] <- spec
      shared_state$row_filter_specs    <- specs
      shared_state$has_pending_changes <- TRUE
    })


    # ── Render active filter widgets ──────────────────────────────────────────
    output$active_filters <- shiny::renderUI({
      specs <- shared_state$row_filter_specs
      if (length(specs) == 0) {
        return(shiny::tags$p(
          class = "text-muted small",
          "No filters added. Use the picker above to add a filter."
        ))
      }

      filter_cards <- lapply(names(specs), function(col) {
        spec <- specs[[col]]
        .render_filter_widget(ns, col, spec)
      })

      shiny::tagList(filter_cards)
    })


    # ── Observe filter widget inputs (numeric range) ──────────────────────────
    shiny::observe({
      specs <- shiny::isolate(shared_state$row_filter_specs)
      lapply(names(specs), function(col) {
        spec <- specs[[col]]
        if (spec$type == "numeric") {
          range_id <- paste0("range_", col)
          shiny::observeEvent(input[[range_id]], {
            s <- shared_state$row_filter_specs
            s[[col]]$min <- input[[range_id]][1]
            s[[col]]$max <- input[[range_id]][2]
            shared_state$row_filter_specs    <- s
            shared_state$has_pending_changes <- TRUE
          }, ignoreNULL = TRUE, ignoreInit = TRUE)

        } else {
          levels_id <- paste0("levels_", col)
          shiny::observeEvent(input[[levels_id]], {
            s <- shared_state$row_filter_specs
            s[[col]]$levels_selected <- input[[levels_id]]
            shared_state$row_filter_specs    <- s
            shared_state$has_pending_changes <- TRUE
          }, ignoreNULL = TRUE, ignoreInit = TRUE)
        }
      })
    })


    # ── Remove filter buttons ─────────────────────────────────────────────────
    shiny::observe({
      specs <- shiny::isolate(shared_state$row_filter_specs)
      lapply(names(specs), function(col) {
        remove_id <- paste0("remove_filter_", col)
        shiny::observeEvent(input[[remove_id]], {
          s <- shared_state$row_filter_specs
          s[[col]] <- NULL
          shared_state$row_filter_specs    <- s
          shared_state$has_pending_changes <- TRUE
        }, ignoreInit = TRUE, once = TRUE)
      })
    })
  })
}


# ── Internal helpers ──────────────────────────────────────────────────────────

# Build the UI widget for one filter entry.
.render_filter_widget <- function(ns, col, spec) {
  remove_btn <- shiny::actionLink(
    ns(paste0("remove_filter_", col)),
    label = shiny::icon("times"),
    class = "text-danger float-end"
  )

  if (spec$type == "numeric") {
    widget <- shiny::sliderInput(
      ns(paste0("range_", col)),
      label = NULL,
      min   = spec$min,
      max   = spec$max,
      value = c(spec$min, spec$max),
      width = "100%"
    )
  } else {
    widget <- shinyWidgets::checkboxGroupButtons(
      ns(paste0("levels_", col)),
      label     = NULL,
      choices   = spec$levels_all,
      selected  = spec$levels_selected,
      size      = "sm",
      direction = "horizontal"
    )
  }

  bslib::card(
    class = "mb-2 border-start border-primary border-3",
    bslib::card_body(
      class = "py-2",
      shiny::fluidRow(
        shiny::column(10, shiny::tags$strong(col)),
        shiny::column(2,  remove_btn)
      ),
      widget
    )
  )
}


# Apply row filter specs to a dataset (used for live row-count preview).
# This is the same logic as apply_row_filters() in the pipeline, kept here
# so this module has no dependency on prepare_confirm internals.
.apply_row_filters_preview <- function(dataset, specs) {
  result <- dataset
  for (col in names(specs)) {
    spec <- specs[[col]]
    if (spec$type == "numeric") {
      result <- result[
        !is.na(result[[col]]) &
          result[[col]] >= spec$min &
          result[[col]] <= spec$max, ,
        drop = FALSE
      ]
    } else {
      result <- result[
        !is.na(result[[col]]) &
          as.character(result[[col]]) %in% spec$levels_selected, ,
        drop = FALSE
      ]
    }
  }
  result
}
