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

  shiny::tagList(
    shiny::uiOutput(ns("pending_badge")),
    shiny::br(),
    shiny::uiOutput(ns("dimension_preview")),
    shiny::uiOutput(ns("transform_warnings")),
    shiny::br(),
    shiny::actionButton(
      ns("apply_btn"),
      label = "Apply Changes",
      icon  = shiny::icon("circle-check"),
      class = "btn-primary w-100"
    ),
    shiny::br(),
    shiny::actionButton(
      ns("reset_btn"),
      label = "Reset to Original",
      icon  = shiny::icon("rotate-left"),
      class = "btn-outline-secondary w-100"
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
      if (isTRUE(shared_state$has_pending_changes)) {
        n <- .count_pending_changes(shared_state)
        shiny::tags$span(
          class = "badge bg-warning text-dark",
          shiny::icon("clock"), " ", n, " pending change(s)"
        )
      } else {
        shiny::tags$span(
          class = "badge bg-success",
          shiny::icon("check"), " Up to date"
        )
      }
    })


    # ── Dimension preview ─────────────────────────────────────────────────────
    # apply_prepare_pipeline() isolates all reads, so we touch the relevant
    # fields here to create reactive dependencies before calling it.
    preview_dataset <- shiny::reactive({
      shared_state$included_columns       # dependency: col include/exclude
      shared_state$row_filter_specs       # dependency: row filters
      shared_state$column_transform_specs # dependency: transforms
      tryCatch(apply_prepare_pipeline(shared_state), error = function(e) NULL)
    })

    output$dimension_preview <- shiny::renderUI({
      df <- preview_dataset()
      if (is.null(df)) {
        shiny::tags$p(class = "text-danger small", "Error computing preview.")
      } else {
        shiny::tags$p(
          class = "text-muted small",
          shiny::icon("table"), " ",
          shiny::tags$strong(format(nrow(df), big.mark = ",")), " rows \u00d7 ",
          shiny::tags$strong(ncol(df)), " cols after Apply"
        )
      }
    })


    # ── Transform validation warning ──────────────────────────────────────────
    # Shows a red warning listing any staged transforms that fail validation.
    output$transform_warnings <- shiny::renderUI({
      invalid <- .find_invalid_transforms(shared_state)
      if (length(invalid) == 0) return(NULL)
      shiny::div(
        class = "alert alert-danger py-2 px-2 mt-2 mb-0 small",
        shiny::tags$strong(shiny::icon("triangle-exclamation"), " Transforms need attention:"),
        shiny::tags$ul(
          class = "mb-0 ps-3",
          lapply(invalid, function(col) shiny::tags$li(col))
        ),
        "Go to the Transforms tab to fix the configuration."
      )
    })


    # ── Shared apply helper ───────────────────────────────────────────────────
    # Extracted so both Apply and its confirm-modal path share one implementation.
    do_apply <- function() {
      df <- tryCatch(
        apply_prepare_pipeline(shared_state),
        error = function(e) {
          shiny::showNotification(
            paste("Error during Apply:", conditionMessage(e)),
            type = "error", duration = 8
          )
          NULL
        }
      )
      if (is.null(df)) return()
      shared_state$dataset_working       <- df
      shared_state$column_types          <- detect_column_types(df)
      shared_state$has_pending_changes   <- FALSE
      shared_state$explore_needs_refresh <- TRUE
      .snapshot_last_applied_specs(shared_state)
      shiny::showNotification(
        paste0("Applied! ",
               format(nrow(df), big.mark = ","), " rows \u00d7 ", ncol(df), " columns."),
        type = "message", duration = 4
      )
    }

    # Shared reset helper — same reason as above.
    do_reset <- function() {
      orig <- shared_state$dataset_original
      shared_state$included_columns       <- names(orig)
      shared_state$column_type_overrides  <- list()
      shared_state$column_transform_specs <- list()
      shared_state$row_filter_specs       <- list()
      shared_state$dataset_working        <- orig
      shared_state$column_types           <- shared_state$original_column_types
      shared_state$has_pending_changes    <- FALSE
      .snapshot_last_applied_specs(shared_state)
      shiny::showNotification("Reset to original dataset.", type = "message", duration = 3)
    }

    # Show a confirmation modal when custom report items exist.
    # Both a "Proceed" and a "Cancel & Revert" button are provided so the user
    # can roll back staged changes if they decide not to proceed.
    .custom_items_guard <- function(action_label, confirm_btn_id, cancel_btn_id) {
      n_items <- length(shiny::isolate(shared_state$custom_report_items))
      if (n_items == 0) return(FALSE)  # no guard needed
      shiny::showModal(shiny::modalDialog(
        title = "Custom Report May Be Affected",
        paste0(
            "You have ", n_items, " item(s) in your custom report. ",
            "Dataset changes will clear custom report items. Would you like to proceed?"
        ),
        footer = shiny::tagList(
          shiny::actionButton(ns(cancel_btn_id), "Go Back & Revert Changes",
                              class = "btn-outline-secondary"),
          shiny::actionButton(ns(confirm_btn_id), action_label, class = "btn-warning")
        ),
        easyClose = FALSE
      ))
      TRUE  # guard was triggered
    }

    # ── Apply button ──────────────────────────────────────────────────────────
    shiny::observeEvent(input$apply_btn, {
      # Validate transforms first
      invalid <- .find_invalid_transforms(shared_state)
      if (length(invalid) > 0) {
        # Navigate to Transforms tab so user sees what needs fixing
        bslib::nav_select("prepare_tabs", "transforms")
        shiny::showNotification(
          paste0("Fix transforms before applying: ",
                 paste(invalid, collapse = ", ")),
          type = "error", duration = 6
        )
        return()
      }

      # Warn if custom report items exist
      if (.custom_items_guard("Apply and Clear Custom Report", "confirm_apply_btn", "cancel_apply_btn")) return()

      do_apply()
    })

    shiny::observeEvent(input$confirm_apply_btn, {
      shiny::removeModal()
      do_apply()
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$cancel_apply_btn, {
      shiny::removeModal()
      .revert_to_last_applied(shared_state)
    }, ignoreInit = TRUE)


    # ── Reset button ──────────────────────────────────────────────────────────
    shiny::observeEvent(input$reset_btn, {
      # Warn if custom report items exist
      if (.custom_items_guard("Reset and Clear Custom Report", "confirm_reset_btn", "cancel_reset_btn")) return()
      do_reset()
    })

    shiny::observeEvent(input$confirm_reset_btn, {
      shiny::removeModal()
      do_reset()
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$cancel_reset_btn, {
      shiny::removeModal()
      .revert_to_last_applied(shared_state)
    }, ignoreInit = TRUE)
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


# Delegates to the canonical implementation in module_column_transform.R
# (that file is sourced by load_all / NAMESPACE, so .apply_column_transforms
#  is defined once there — this duplicate has been removed)


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
  n_transforms <- length(shared_state$column_transform_specs)
  n_filters    <- length(shared_state$row_filter_specs)
  all_cols     <- names(shared_state$dataset_original)
  n_excluded   <- length(setdiff(all_cols, shared_state$included_columns))
  n_transforms + n_filters + n_excluded
}


# Snapshot the current staged specs into shared_state$last_applied_specs.
# Called after every successful Apply or Reset so Cancel can revert to this point.
.snapshot_last_applied_specs <- function(shared_state) {
  shared_state$last_applied_specs <- list(
    included_columns       = shiny::isolate(shared_state$included_columns),
    column_type_overrides  = shiny::isolate(shared_state$column_type_overrides),
    column_transform_specs = shiny::isolate(shared_state$column_transform_specs),
    row_filter_specs       = shiny::isolate(shared_state$row_filter_specs)
  )
}


# Restore staged specs to last_applied_specs and signal all modules to sync their UIs.
# Increments shared_state$revert_trigger so modules can observe the revert event.
.revert_to_last_applied <- function(shared_state) {
  specs <- shiny::isolate(shared_state$last_applied_specs)
  if (is.null(specs)) return()
  shared_state$included_columns       <- specs$included_columns
  shared_state$column_type_overrides  <- specs$column_type_overrides
  shared_state$column_transform_specs <- specs$column_transform_specs
  shared_state$row_filter_specs       <- specs$row_filter_specs
  shared_state$has_pending_changes    <- FALSE
  shared_state$revert_trigger         <- shiny::isolate(shared_state$revert_trigger) + 1L
}


# Return names of staged transforms that fail validation.
.find_invalid_transforms <- function(shared_state) {
  specs   <- shared_state$column_transform_specs
  dataset <- shared_state$dataset_original
  invalid <- character(0)
  for (col in names(specs)) {
    spec <- specs[[col]]
    x    <- dataset[[col]]
    if (!.transform_spec_is_valid(spec, x)) invalid <- c(invalid, col)
  }
  invalid
}
