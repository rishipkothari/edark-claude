#' Column Manager Module
#'
#' Compact table showing all columns with an Include checkbox per column.
#' Transform staging and configuration is handled entirely in the Transforms tab.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_column_manager
NULL


#' @rdname module_column_manager
#' @export
column_manager_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    bslib::card_header(
      shiny::icon("table-columns"), " Columns",
      shiny::actionLink(ns("select_all"),   "Select all",   class = "ms-3 small"),
      shiny::actionLink(ns("deselect_all"), "Deselect all", class = "ms-2 small")
    ),
    bslib::card_body(
      class = "p-0",
      shiny::uiOutput(ns("column_table"))
    )
  )
}


#' @rdname module_column_manager
#' @export
column_manager_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Render compact column table ──────────────────────────────────────────
    output$column_table <- shiny::renderUI({
      dataset    <- shared_state$dataset_original
      col_names  <- names(dataset)
      orig_types <- shared_state$original_column_types  # never changes
      included   <- shared_state$included_columns

      current_types <- shared_state$column_types

      header <- shiny::tags$thead(
        shiny::tags$tr(
          shiny::tags$th(class = "text-center ps-2", style = "width:55px;",  "Include"),
          shiny::tags$th(style = "width:120px;", "Column name"),
          shiny::tags$th(class = "text-end pe-2", style = "width:60px;",    "Unique"),
          shiny::tags$th(style = "width:85px;",  "Orig. type"),
          shiny::tags$th(style = "width:85px;",  "Curr. type")
        )
      )

      rows <- lapply(col_names, function(col) {
        orig_type    <- orig_types[[col]]
        curr_type    <- if (col %in% names(current_types)) current_types[[col]] else orig_type
        n_unique     <- length(unique(na.omit(dataset[[col]])))
        is_included  <- col %in% included
        type_changed <- !identical(orig_type, curr_type)

        shiny::tags$tr(
          shiny::tags$td(
            class = "text-center ps-2 py-0",
            shiny::checkboxInput(ns(paste0("include_", col)), label = NULL, value = is_included)
          ),
          shiny::tags$td(class = "py-1 align-middle small fw-semibold", col),
          shiny::tags$td(
            class = "py-1 align-middle text-end pe-2 text-muted small",
            format(n_unique, big.mark = ",")
          ),
          shiny::tags$td(
            class = "py-1 align-middle",
            shiny::tags$code(class = "small text-muted", orig_type)
          ),
          shiny::tags$td(
            class = "py-1 align-middle",
            if (type_changed) {
              shiny::tags$code(class = "small text-warning fw-bold", curr_type)
            } else {
              shiny::tags$code(class = "small text-muted", curr_type)
            }
          )
        )
      })

      shiny::tags$table(
        class = "table table-sm table-hover align-middle mb-0",
        shiny::tags$style(shiny::HTML(
          ".form-check { margin-bottom: 0 !important; display: flex !important;
             justify-content: center !important; }
           .form-check-input { margin-top: 0 !important; margin-left: 0 !important; }"
        )),
        header,
        shiny::tags$tbody(rows)
      )
    })


    # ── Observe include checkboxes ────────────────────────────────────────────
    # Register once for all columns (column list never changes within a session).
    shiny::observe({
      col_names <- names(shiny::isolate(shared_state$dataset_original))
      lapply(col_names, function(col) {
        shiny::observeEvent(input[[paste0("include_", col)]], {
          included <- shared_state$included_columns
          if (isTRUE(input[[paste0("include_", col)]])) {
            if (!col %in% included)
              shared_state$included_columns <- c(included, col)
          } else {
            shared_state$included_columns <- setdiff(included, col)
          }
          shared_state$has_pending_changes <- TRUE
        }, ignoreInit = TRUE)
      })
    })


    # ── Select / Deselect all ────────────────────────────────────────────────
    shiny::observeEvent(input$select_all, {
      col_names <- names(shared_state$dataset_original)
      shared_state$included_columns    <- col_names
      shared_state$has_pending_changes <- TRUE
      lapply(col_names, function(col)
        shiny::updateCheckboxInput(session, paste0("include_", col), value = TRUE))
    })

    shiny::observeEvent(input$deselect_all, {
      shared_state$included_columns    <- character(0)
      shared_state$has_pending_changes <- TRUE
      col_names <- names(shared_state$dataset_original)
      lapply(col_names, function(col)
        shiny::updateCheckboxInput(session, paste0("include_", col), value = FALSE))
    })
  })
}
