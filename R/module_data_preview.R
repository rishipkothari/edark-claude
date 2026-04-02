#' Data Preview Module
#'
#' Two sub-tabs: Original dataset and Working dataset as interactive reactable
#' tables. Each column header shows the column name and its type below it.
#' Transformed columns are tinted amber. Originally-numeric columns retain
#' right-alignment even after being recoded as factors.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_data_preview
NULL


#' @rdname module_data_preview
#' @export
data_preview_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::navset_card_tab(
    bslib::nav_panel(
      title = shiny::tagList(shiny::icon("database"), " Original"),
      shiny::tags$p(
        class = "text-muted small mb-2",
        "Dataset as passed to edark(), after auto-casting only. No filters or",
        " transforms applied."
      ),
      reactable::reactableOutput(ns("original_table"))
    ),
    bslib::nav_panel(
      title = shiny::tagList(shiny::icon("circle-check"), " Working"),
      shiny::tags$p(
        class = "text-muted small mb-2",
        "Dataset after the last Apply. Amber columns were recoded from numeric",
        " to ordered factor."
      ),
      reactable::reactableOutput(ns("working_table"))
    )
  )
}


#' @rdname module_data_preview
#' @export
data_preview_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    output$original_table <- reactable::renderReactable({
      df         <- shared_state$dataset_original
      orig_types <- shared_state$original_column_types
      shiny::req(!is.null(df))

      # For the original table, "transformed" = columns staged for transform
      staged_transforms <- names(shared_state$column_transform_specs)

      col_defs <- .make_col_defs(df, orig_types,
                                  tinted_cols    = staged_transforms,
                                  numeric_orig   = names(orig_types)[orig_types == "numeric"])

      reactable::reactable(
        df,
        columns         = col_defs,
        compact         = TRUE,
        bordered        = TRUE,
        striped         = FALSE,
        highlight       = TRUE,
        resizable       = TRUE,
        defaultPageSize = 100,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(100, 250, 500)
      )
    })

    output$working_table <- reactable::renderReactable({
      df            <- shared_state$dataset_working
      orig_types    <- shared_state$original_column_types
      current_types <- shared_state$column_types
      shiny::req(!is.null(df))

      # Tint columns whose type changed from numeric to factor after Apply
      tinted <- names(df)[vapply(names(df), function(col) {
        !is.null(orig_types[[col]]) &&
          identical(orig_types[[col]], "numeric") &&
          !is.null(current_types[[col]]) &&
          identical(current_types[[col]], "factor")
      }, logical(1))]

      col_defs <- .make_col_defs(df, current_types,
                                  tinted_cols  = tinted,
                                  numeric_orig = names(orig_types)[orig_types == "numeric"])

      reactable::reactable(
        df,
        columns         = col_defs,
        compact         = TRUE,
        bordered        = TRUE,
        striped         = FALSE,
        highlight       = TRUE,
        resizable       = TRUE,
        defaultPageSize = 100,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(100, 250, 500)
      )
    })
  })
}


# ── Internal helpers ──────────────────────────────────────────────────────────

# Build a named list of reactable colDef objects.
# - Column headers show type beneath the name
# - Tinted columns get an amber background
# - Originally-numeric columns are right-aligned even when recoded as factor
.make_col_defs <- function(df, type_map, tinted_cols, numeric_orig) {
  col_names <- names(df)

  defs <- lapply(col_names, function(col) {
    col_type   <- if (!is.null(type_map[[col]])) type_map[[col]] else "unknown"
    is_tinted  <- col %in% tinted_cols
    is_num_orig <- col %in% numeric_orig

    # Custom header: column name + type label beneath
    header_fn <- function(value) {
      shiny::tags$div(
        shiny::tags$div(value, style = "font-weight: 600;"),
        shiny::tags$div(
          col_type,
          style = paste0(
            "font-size: 0.72em; color: ",
            if (is_tinted) "#92400e" else "#6b7280",
            "; font-style: italic;"
          )
        )
      )
    }

    cell_style <- if (is_tinted) {
      list(background = "rgba(251, 191, 36, 0.15)")
    } else {
      NULL
    }

    reactable::colDef(
      header = header_fn,
      align  = if (is_num_orig) "right" else "left",
      style  = cell_style
    )
  })

  names(defs) <- col_names
  defs
}
