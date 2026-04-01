#' Prepare Confirm Module
#'
#' Displays a count of pending (unapplied) changes and a preview of the
#' resulting dataset dimensions. When the user clicks "Apply & Proceed", runs
#' the full prepare pipeline atomically and navigates to the Explore tab.
#'
#' The pipeline order (from PRD §4.5):
#'   1. Start from `dataset_original`
#'   2. Apply column type overrides
#'   3. Select included columns
#'   4. Apply column transformations (numeric → ordered factor)
#'   5. Apply row filters
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_prepare_confirm
NULL


#' @rdname module_prepare_confirm
#' @export
prepare_confirm_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    bslib::card_header(shiny::icon("circle-check"), " Apply Changes"),
    bslib::card_body(
      shiny::uiOutput(ns("pending_badge")),
      shiny::br(),
      shiny::uiOutput(ns("dimension_preview")),
      shiny::br(),
      shiny::actionButton(
        ns("apply_btn"),
        label = "Apply & Proceed  →",
        icon  = shiny::icon("play"),
        class = "btn-primary w-100"
      )
    )
  )
}


#' @rdname module_prepare_confirm
#' @export
prepare_confirm_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Pending changes badge ─────────────────────────────────────────────────
    output$pending_badge <- shiny::renderUI({
      n <- .count_pending_changes(shared_state)
      if (n == 0) {
        shiny::tags$span(class = "badge bg-secondary", "No pending changes")
      } else {
        shiny::tags$span(
          class = "badge bg-warning text-dark fs-6",
          shiny::icon("clock"), " ", n, " pending change(s)"
        )
      }
    })


    # ── Dimension preview ─────────────────────────────────────────────────────
    # Runs the full pipeline reactively so the user sees what they'll get.
    preview_dataset <- shiny::reactive({
      tryCatch(
        apply_prepare_pipeline(shared_state),
        error = function(e) NULL
      )
    })

    output$dimension_preview <- shiny::renderUI({
      df <- preview_dataset()
      if (is.null(df)) {
        shiny::tags$p(class = "text-danger small", "Error computing preview.")
      } else {
        shiny::tags$p(
          class = "text-muted",
          shiny::icon("table"), " ",
          shiny::tags$strong(format(nrow(df), big.mark = ",")), " rows × ",
          shiny::tags$strong(ncol(df)), " columns after Apply"
        )
      }
    })


    # ── Apply button ──────────────────────────────────────────────────────────
    shiny::observeEvent(input$apply_btn, {
      df <- tryCatch(
        apply_prepare_pipeline(shared_state),
        error = function(e) {
          shiny::showNotification(
            paste("Error during Apply:", conditionMessage(e)),
            type     = "error",
            duration = 8
          )
          NULL
        }
      )

      if (is.null(df)) return()

      shared_state$dataset_working        <- df
      shared_state$column_types           <- detect_column_types(df)
      shared_state$has_pending_changes    <- FALSE
      shared_state$explore_needs_refresh  <- TRUE

      # Navigate to the Explore tab
      bslib::nav_select("main_navbar", "explore")

      shiny::showNotification(
        paste0(
          "Applied! Working dataset: ",
          format(nrow(df), big.mark = ","), " rows × ", ncol(df), " columns."
        ),
        type     = "message",
        duration = 4
      )
    })
  })
}


# ── Pipeline ──────────────────────────────────────────────────────────────────

#' Apply all staged prepare-stage changes to produce the working dataset
#'
#' Runs the full prepare pipeline in order:
#' type overrides → column selection → transformations → row filters.
#' Called by `prepare_confirm_server` on Apply and used for the dimension
#' preview. Also called by `edark_report()` for the programmatic API.
#'
#' @param shared_state A Shiny `reactiveValues` object (or a plain named list
#'   with the same fields, for programmatic use).
#'
#' @return A `data.frame` — the result of applying all staged specs.
#'
#' @keywords internal
apply_prepare_pipeline <- function(shared_state) {
  dataset    <- shiny::isolate(shared_state$dataset_original)
  overrides  <- shiny::isolate(shared_state$column_type_overrides)
  included   <- shiny::isolate(shared_state$included_columns)
  transforms <- shiny::isolate(shared_state$column_transform_specs)
  filters    <- shiny::isolate(shared_state$row_filter_specs)

  # Step 1: apply column type overrides
  dataset <- .apply_column_type_overrides(dataset, overrides)

  # Step 2: select included columns only
  dataset <- dataset[, intersect(included, names(dataset)), drop = FALSE]

  # Step 3: apply column transformations (numeric → ordered factor)
  dataset <- .apply_column_transforms(dataset, transforms)

  # Step 4: apply row filters
  dataset <- .apply_row_filters(dataset, filters)

  dataset
}


# ── Step implementations ──────────────────────────────────────────────────────

.apply_column_type_overrides <- function(dataset, overrides) {
  if (length(overrides) == 0) return(dataset)
  for (col in names(overrides)) {
    if (!col %in% names(dataset)) next
    target <- overrides[[col]]
    dataset[[col]] <- switch(target,
      numeric  = suppressWarnings(as.numeric(dataset[[col]])),
      factor   = as.factor(dataset[[col]]),
      datetime = suppressWarnings(as.POSIXct(as.character(dataset[[col]]), tz = "UTC")),
      character = as.character(dataset[[col]]),
      dataset[[col]]  # unknown type — leave unchanged
    )
  }
  dataset
}


.apply_column_transforms <- function(dataset, transforms) {
  if (length(transforms) == 0) return(dataset)
  for (col in names(transforms)) {
    if (!col %in% names(dataset)) next
    spec <- transforms[[col]]
    x    <- dataset[[col]]

    if (spec$method == "auto") {
      dataset[[col]] <- factor(x, levels = sort(unique(x[!is.na(x)])),
                               ordered = TRUE)
    } else {
      # cutpoints method
      breaks <- spec$breakpoints
      if (is.null(breaks) || length(breaks) == 0) next
      breaks_full <- c(-Inf, breaks, Inf)
      labels      <- spec$labels
      if (is.null(labels) || length(labels) != length(breaks_full) - 1) {
        labels <- paste0("Level ", seq_len(length(breaks_full) - 1))
      }
      dataset[[col]] <- cut(x,
        breaks          = breaks_full,
        labels          = labels,
        include.lowest  = TRUE,
        right           = FALSE,
        ordered_result  = TRUE
      )
    }
  }
  dataset
}


.apply_row_filters <- function(dataset, filters) {
  if (length(filters) == 0) return(dataset)
  for (col in names(filters)) {
    if (!col %in% names(dataset)) next
    spec <- filters[[col]]
    if (spec$type == "numeric") {
      keep <- !is.na(dataset[[col]]) &
              dataset[[col]] >= spec$min &
              dataset[[col]] <= spec$max
    } else {
      keep <- !is.na(dataset[[col]]) &
              as.character(dataset[[col]]) %in% spec$levels_selected
    }
    dataset <- dataset[keep, , drop = FALSE]
  }
  dataset
}


# Count total pending staged items across all three prepare sub-modules.
.count_pending_changes <- function(shared_state) {
  n_overrides  <- length(shiny::isolate(shared_state$column_type_overrides))
  n_transforms <- length(shiny::isolate(shared_state$column_transform_specs))
  n_filters    <- length(shiny::isolate(shared_state$row_filter_specs))

  all_cols     <- names(shiny::isolate(shared_state$dataset_original))
  included     <- shiny::isolate(shared_state$included_columns)
  n_excluded   <- length(setdiff(all_cols, included))

  n_overrides + n_transforms + n_filters + n_excluded
}
