#' Column Manager Module
#'
#' Compact table showing all columns with Include and Transform checkboxes.
#' Checking "Transform" stages an auto-factor transform spec for that column.
#' Transform configurations (method, cutpoints, labels, preview) appear in an
#' accordion below the table. No type-override controls — use the Transform
#' checkbox to recode a numeric column as a factor.
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
      shiny::tags$p(
        class = "text-muted small px-3 pt-2 mb-1",
        "Check \u2018Transform\u2019 on any numeric column to recode it as a factor.",
        "Configure cut-points in the Transforms tab."
      ),
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
      dataset         <- shared_state$dataset_original
      col_names       <- names(dataset)
      orig_types      <- shared_state$original_column_types  # never changes
      included        <- shared_state$included_columns
      transform_specs <- shared_state$column_transform_specs

      current_types <- shared_state$column_types

      header <- shiny::tags$thead(
        shiny::tags$tr(
          shiny::tags$th(class = "text-center ps-2", style = "width:55px;",  "Include"),
          shiny::tags$th(style = "width:140px;", "Column name"),
          shiny::tags$th(class = "text-end pe-2", style = "width:60px;",    "Unique"),
          shiny::tags$th(style = "width:85px;",  "Orig. type"),
          shiny::tags$th(style = "width:85px;",  "Curr. type"),
          shiny::tags$th(class = "text-center",  style = "width:80px;",     "Transform")
        )
      )

      rows <- lapply(col_names, function(col) {
        orig_type       <- orig_types[[col]]
        curr_type       <- if (col %in% names(current_types)) current_types[[col]] else orig_type
        n_unique        <- length(unique(na.omit(dataset[[col]])))
        is_included     <- col %in% included
        is_transformed  <- col %in% names(transform_specs)
        is_orig_numeric <- identical(orig_type, "numeric")
        type_changed    <- !identical(orig_type, curr_type)
        row_class       <- if (is_transformed) "row-transformed" else ""

        shiny::tags$tr(
          class = row_class,
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
          ),
          shiny::tags$td(
            class = "text-center py-0",
            if (is_orig_numeric) {
              shiny::checkboxInput(
                ns(paste0("transform_", col)), label = NULL, value = is_transformed
              )
            } else {
              shiny::tags$span(class = "text-muted small", "\u2014")
            }
          )
        )
      })

      shiny::tags$table(
        class = "table table-sm table-hover align-middle mb-0",
        shiny::tags$style(shiny::HTML(
          ".form-check { margin-bottom: 0 !important; display: flex !important;
             justify-content: center !important; }
           .form-check-input { margin-top: 0 !important; margin-left: 0 !important; }
           tr.row-transformed { background-color: rgba(251, 191, 36, 0.08) !important; }"
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


    # ── Observe transform checkboxes — add/remove from transform_specs ─────────
    shiny::observe({
      col_names  <- names(shiny::isolate(shared_state$dataset_original))
      orig_types <- shiny::isolate(shared_state$original_column_types)
      # Use original type — checkbox stays available even after col is applied as factor
      num_cols <- col_names[
        vapply(col_names, function(c) identical(orig_types[[c]], "numeric"), logical(1))
      ]
      lapply(num_cols, function(col) {
        shiny::observeEvent(input[[paste0("transform_", col)]], {
          specs <- shared_state$column_transform_specs
          if (isTRUE(input[[paste0("transform_", col)]])) {
            if (is.null(specs[[col]])) {
              x        <- shared_state$dataset_original[[col]]
              n_unique <- length(unique(na.omit(x)))
              # > 20 unique values: force cut-points (auto would create >20 levels)
              method   <- if (n_unique > 20) "cutpoints" else "auto"
              specs[[col]] <- list(
                method      = method,
                col         = col,
                values      = sort(unique(x[!is.na(x)])),
                breakpoints = NULL,
                labels      = NULL
              )
              shared_state$column_transform_specs  <- specs
              shared_state$has_pending_changes     <- TRUE
            }
          } else {
            specs[[col]] <- NULL
            shared_state$column_transform_specs  <- specs
            shared_state$has_pending_changes     <- TRUE
          }
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
