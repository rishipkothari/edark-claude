#' Data Preview Module
#'
#' Two nav panels: Original dataset and Working dataset. Each panel has two
#' sub-tabs: Data (interactive reactable) and Summary (EDA summary table).
#' Transformed columns are tinted amber in the Working data view.
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
      bslib::navset_tab(
        bslib::nav_panel(
          title = "Data",
          shiny::tags$p(
            class = "text-muted small mb-2 mt-2",
            "Dataset as passed to edark(), after auto-casting only. No filters or transforms applied."
          ),
          reactable::reactableOutput(ns("original_table"))
        ),
        bslib::nav_panel(
          title = "Summary",
          shiny::tags$p(
            class = "text-muted small mb-2 mt-2",
            "EDA summary for numeric and factor columns (original dataset)."
          ),
          reactable::reactableOutput(ns("original_summary"))
        )
      )
    ),
    bslib::nav_panel(
      title = shiny::tagList(shiny::icon("circle-check"), " Working"),
      bslib::navset_tab(
        bslib::nav_panel(
          title = "Data",
          shiny::tags$p(
            class = "text-muted small mb-2 mt-2",
            "Dataset after the last Apply. Amber columns have a transform applied."
          ),
          reactable::reactableOutput(ns("working_table"))
        ),
        bslib::nav_panel(
          title = "Summary",
          shiny::tags$p(
            class = "text-muted small mb-2 mt-2",
            "EDA summary for numeric and factor columns (working dataset after Apply)."
          ),
          reactable::reactableOutput(ns("working_summary"))
        )
      )
    )
  )
}


#' @rdname module_data_preview
#' @export
data_preview_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    # ── Original: data table ──────────────────────────────────────────────────
    output$original_table <- reactable::renderReactable({
      df         <- shared_state$dataset_original
      orig_types <- shared_state$original_column_types
      shiny::req(!is.null(df))

      staged_transforms <- names(shared_state$column_transform_specs)

      col_defs <- .make_col_defs(df, orig_types,
                                  tinted_cols  = staged_transforms,
                                  numeric_orig = names(orig_types)[orig_types == "numeric"])

      reactable::reactable(
        df,
        columns             = col_defs,
        compact             = TRUE,
        bordered            = TRUE,
        striped             = FALSE,
        highlight           = TRUE,
        resizable           = TRUE,
        defaultPageSize     = 100,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(100, 250, 500)
      )
    })


    # ── Original: summary table ───────────────────────────────────────────────
    output$original_summary <- reactable::renderReactable({
      df         <- shared_state$dataset_original
      orig_types <- shared_state$original_column_types
      shiny::req(!is.null(df))

      summary_df <- .build_dataset_summary(df, orig_types)
      shiny::req(!is.null(summary_df) && nrow(summary_df) > 0)

      .render_summary_reactable(summary_df)
    })


    # ── Working: data table ───────────────────────────────────────────────────
    output$working_table <- reactable::renderReactable({
      df            <- shared_state$dataset_working
      orig_types    <- shared_state$original_column_types
      current_types <- shared_state$column_types
      applied_specs <- shared_state$column_transform_specs
      shiny::req(!is.null(df))

      # Tint any column that has an applied transform spec (covers type-changing
      # transforms like auto/cutpoints AND numeric-preserving ones like log/
      # winsorize/round/standardize where curr_type == orig_type = "numeric")
      tinted <- names(df)[names(df) %in% names(applied_specs)]

      col_defs <- .make_col_defs(df, current_types,
                                  tinted_cols  = tinted,
                                  numeric_orig = names(orig_types)[orig_types == "numeric"])

      reactable::reactable(
        df,
        columns             = col_defs,
        compact             = TRUE,
        bordered            = TRUE,
        striped             = FALSE,
        highlight           = TRUE,
        resizable           = TRUE,
        defaultPageSize     = 100,
        showPageSizeOptions = TRUE,
        pageSizeOptions     = c(100, 250, 500)
      )
    })


    # ── Working: summary table ────────────────────────────────────────────────
    output$working_summary <- reactable::renderReactable({
      df            <- shared_state$dataset_working
      current_types <- shared_state$column_types
      shiny::req(!is.null(df))

      summary_df <- .build_dataset_summary(df, current_types)
      shiny::req(!is.null(summary_df) && nrow(summary_df) > 0)

      .render_summary_reactable(summary_df)
    })

  })
}


# ── Internal helpers ──────────────────────────────────────────────────────────

# Build a named list of reactable colDef objects for the raw data table.
.make_col_defs <- function(df, type_map, tinted_cols, numeric_orig) {
  col_names <- names(df)

  defs <- lapply(col_names, function(col) {
    col_type    <- if (!is.null(type_map[[col]])) type_map[[col]] else "unknown"
    is_tinted   <- col %in% tinted_cols
    is_num_orig <- col %in% numeric_orig

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

    cell_style <- if (is_tinted) list(background = "rgba(251, 191, 36, 0.15)") else NULL

    reactable::colDef(
      header = header_fn,
      align  = if (is_num_orig) "right" else "left",
      style  = cell_style
    )
  })

  names(defs) <- col_names
  defs
}


# Render a .build_dataset_summary() data frame as a compact reactable.
.render_summary_reactable <- function(summary_df) {
  # NA numerics → em-dash for display
  num_cols <- c("Min", "Max", "Mean", "SD", "Median", "IQR", "Skewness", "Kurtosis")
  disp     <- summary_df
  for (col in num_cols) {
    disp[[col]] <- ifelse(is.na(disp[[col]]), "\u2014", as.character(disp[[col]]))
  }
  disp$Top_values <- ifelse(is.na(disp$Top_values), "\u2014", disp$Top_values)

  reactable::reactable(
    disp,
    compact         = TRUE,
    bordered        = TRUE,
    striped         = FALSE,
    highlight       = TRUE,
    resizable       = TRUE,
    defaultPageSize = 250,
    columns = list(
      Variable   = reactable::colDef(minWidth = 110, sticky = "left",
                     style = list(fontWeight = "600")),
      Type       = reactable::colDef(minWidth = 75,
                     cell = function(v) shiny::tags$code(class = "small text-muted", v)),
      N          = reactable::colDef(minWidth = 60,  align = "right"),
      N_missing  = reactable::colDef(name = "Missing", minWidth = 70, align = "right"),
      Pct_miss   = reactable::colDef(name = "% Miss",  minWidth = 65, align = "right"),
      N_unique   = reactable::colDef(name = "Unique",  minWidth = 65, align = "right"),
      Min        = reactable::colDef(minWidth = 70,  align = "right"),
      Max        = reactable::colDef(minWidth = 70,  align = "right"),
      Mean       = reactable::colDef(minWidth = 70,  align = "right"),
      SD         = reactable::colDef(minWidth = 70,  align = "right"),
      Median     = reactable::colDef(minWidth = 70,  align = "right"),
      IQR        = reactable::colDef(minWidth = 60,  align = "right"),
      Skewness   = reactable::colDef(minWidth = 80,  align = "right"),
      Kurtosis   = reactable::colDef(minWidth = 80,  align = "right"),
      Top_values = reactable::colDef(name = "Top values", minWidth = 160)
    )
  )
}
