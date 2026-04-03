#' Row Filter Module
#'
#' Allows the user to add row-filter criteria against any included column.
#' Numeric columns get a min/max range slider; factor/character columns get a
#' checkbox group of levels to retain. Multiple filters compose with AND logic.
#' All filters are staged — nothing is applied until "Apply & Proceed".
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

  shiny::tagList(
    # Add-filter controls
    shiny::fluidRow(
      class = "mb-3",
      shiny::column(8, shiny::uiOutput(ns("column_picker"))),
      shiny::column(4,
        shiny::br(),
        shiny::actionButton(
          ns("add_filter"), "Add filter",
          icon  = shiny::icon("plus"),
          class = "btn-sm btn-outline-primary w-100"
        )
      )
    ),

    # Live row-count badge
    shiny::uiOutput(ns("row_count_badge")),
    shiny::hr(),

    # Active filter cards
    shiny::uiOutput(ns("active_filters"))
  )
}


#' @rdname module_row_filter
#' @export
row_filter_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Track which columns already have input observers registered so we never
    # double-register when the specs reactive fires multiple times.
    registered_cols <- character(0)

    # ── Column picker ─────────────────────────────────────────────────────────
    output$column_picker <- shiny::renderUI({
      included <- shared_state$included_columns
      shinyWidgets::pickerInput(
        ns("filter_column"),
        label   = "Column to filter:",
        choices = included,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })


    # ── Row count badge ───────────────────────────────────────────────────────
    output$row_count_badge <- shiny::renderUI({
      specs   <- shared_state$row_filter_specs
      # Use dataset_working as the base: it already reflects all previously
      # applied pipeline steps (type overrides, column selection, transforms).
      dataset <- shared_state$dataset_working
      n_orig  <- nrow(dataset)

      n_filt <- if (length(specs) == 0) {
        n_orig
      } else {
        tryCatch(
          nrow(.apply_row_filters_preview(dataset, specs)),
          error = function(e) NA_integer_
        )
      }

      colour <- if (!is.na(n_filt) && n_filt < n_orig) "warning" else "success"
      shiny::tags$span(
        class = paste0("badge bg-", colour),
        if (is.na(n_filt)) "Error in filters" else
          paste0(format(n_filt, big.mark = ","), " / ",
                 format(n_orig, big.mark = ","), " rows retained")
      )
    })


    # ── Add filter ────────────────────────────────────────────────────────────
    shiny::observeEvent(input$add_filter, {
      col <- input$filter_column
      if (is.null(col) || col == "") return()
      if (!is.null(shared_state$row_filter_specs[[col]])) return()

      # Use dataset_working so that post-Apply transforms (e.g. numeric → factor)
      # are reflected in both the type and the data values used to build the spec.
      x        <- shared_state$dataset_working[[col]]
      col_type <- shared_state$column_types[[col]]

      if (col_type == "numeric") {
        spec <- list(
          type = "numeric",
          min  = min(x, na.rm = TRUE),
          max  = max(x, na.rm = TRUE),
          data_min = min(x, na.rm = TRUE),
          data_max = max(x, na.rm = TRUE)
        )
      } else {
        lvls <- as.character(sort(unique(x[!is.na(x)])))
        spec <- list(
          type             = "categorical",
          levels_all       = lvls,
          levels_selected  = lvls
        )
      }

      specs        <- shared_state$row_filter_specs
      specs[[col]] <- spec
      shared_state$row_filter_specs    <- specs
      shared_state$has_pending_changes <- TRUE
    })


    # ── Render filter cards ───────────────────────────────────────────────────
    output$active_filters <- shiny::renderUI({
      specs <- shared_state$row_filter_specs
      if (length(specs) == 0) {
        return(shiny::tags$p(
          class = "text-muted small",
          "No filters added yet. Select a column above and click Add filter."
        ))
      }

      lapply(names(specs), function(col) {
        spec <- specs[[col]]
        .render_filter_widget(ns, col, spec)
      })
    })


    # ── Register input observers for filter widgets ───────────────────────────
    # Re-runs when row_filter_specs changes (new filter added), but only
    # registers observers for columns not yet tracked.
    shiny::observe({
      specs    <- shared_state$row_filter_specs
      new_cols <- setdiff(names(specs), registered_cols)
      if (length(new_cols) == 0) return()

      for (col in new_cols) {
        local({
          .col     <- col
          col_type <- specs[[.col]]$type

          if (col_type == "numeric") {
            shiny::observeEvent(input[[paste0("range_", .col)]], {
              val <- input[[paste0("range_", .col)]]
              s   <- shared_state$row_filter_specs
              if (!is.null(s[[.col]]) && !is.null(val)) {
                s[[.col]]$min                <- val[1]
                s[[.col]]$max                <- val[2]
                shared_state$row_filter_specs    <- s
                shared_state$has_pending_changes <- TRUE
              }
            }, ignoreNULL = TRUE, ignoreInit = TRUE)

          } else {
            shiny::observeEvent(input[[paste0("levels_", .col)]], {
              val <- input[[paste0("levels_", .col)]]
              s   <- shared_state$row_filter_specs
              if (!is.null(s[[.col]])) {
                s[[.col]]$levels_selected        <- val
                shared_state$row_filter_specs    <- s
                shared_state$has_pending_changes <- TRUE
              }
            }, ignoreNULL = TRUE, ignoreInit = TRUE)
          }

          # Remove button
          shiny::observeEvent(input[[paste0("remove_filter_", .col)]], {
            s         <- shared_state$row_filter_specs
            s[[.col]] <- NULL
            shared_state$row_filter_specs    <- s
            shared_state$has_pending_changes <- TRUE
          }, ignoreInit = TRUE, once = TRUE)
        })

        registered_cols <<- c(registered_cols, col)
      }
    })

    # When row_filter_specs is cleared (Apply or Reset), purge the cache so
    # the same column can be re-registered with fresh observers next time.
    shiny::observeEvent(shared_state$row_filter_specs, {
      if (length(shared_state$row_filter_specs) == 0)
        registered_cols <<- character(0)
    }, ignoreInit = TRUE)
  })
}


# ── Internal helpers ──────────────────────────────────────────────────────────

.render_filter_widget <- function(ns, col, spec) {
  remove_btn <- shiny::actionLink(
    ns(paste0("remove_filter_", col)),
    label = shiny::icon("xmark"),
    class = "text-danger"
  )

  widget <- if (spec$type == "numeric") {
    shiny::sliderInput(
      ns(paste0("range_", col)),
      label = NULL,
      min   = spec$data_min,
      max   = spec$data_max,
      value = c(spec$min, spec$max),
      width = "100%"
    )
  } else {
    shinyWidgets::checkboxGroupButtons(
      ns(paste0("levels_", col)),
      label     = NULL,
      choices   = spec$levels_all,
      selected  = spec$levels_selected,
      size      = "sm",
      direction = "horizontal"
    )
  }

  bslib::card(
    class = "mb-2",
    bslib::card_header(
      class = "py-1 d-flex justify-content-between align-items-center",
      shiny::tags$strong(col),
      remove_btn
    ),
    bslib::card_body(class = "py-2", widget)
  )
}


# Apply row filter specs to a dataset (used for live preview in the badge).
.apply_row_filters_preview <- function(dataset, specs) {
  result <- dataset
  for (col in names(specs)) {
    if (!col %in% names(result)) next
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
