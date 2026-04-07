#' Prepare Confirm Module
#'
#' Displays dataset dimensions (original / current / pending), grouped warnings,
#' and a pending-changes status badge. When the user clicks "Apply Changes",
#' runs the full prepare pipeline atomically.
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
    # 1. Dimensions
    shiny::tags$p(
      class = "mt-2 mb-1 fw-semibold",
      shiny::icon("table"), " Dimensions"
    ),
    shiny::uiOutput(ns("dimension_cards")),
    shiny::hr(class = "my-2"),

    # 1.5. Warnings
    shiny::uiOutput(ns("prepare_warnings")),

    # 2. Status badge (full-width, alert-style, same size as button)
    shiny::uiOutput(ns("pending_badge")),

    # 3. Apply button
    shiny::actionButton(
      ns("apply_btn"),
      label = "Apply Changes",
      icon  = shiny::icon("circle-check"),
      class = "btn-primary w-100"
    ),

    # 4. Reset button
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

    # ── Pending dataset preview ───────────────────────────────────────────────
    # apply_prepare_pipeline() isolates all reads, so we touch the relevant
    # fields here to create reactive dependencies before calling it.
    preview_dataset <- shiny::reactive({
      shared_state$included_columns       # dependency: col include/exclude
      shared_state$row_filter_specs       # dependency: row filters
      shared_state$column_transform_specs # dependency: transforms
      tryCatch(apply_prepare_pipeline(shared_state), error = function(e) NULL)
    })


    # ── Dimension cards ───────────────────────────────────────────────────────
    output$dimension_cards <- shiny::renderUI({
      orig       <- shared_state$dataset_original
      curr       <- shared_state$dataset_working
      pending    <- preview_dataset()
      is_pending <- isTRUE(shared_state$has_pending_changes)

      pend_r <- if (!is.null(pending)) nrow(pending) else NA
      pend_c <- if (!is.null(pending)) ncol(pending) else NA

      .dim_row <- function(label, r, c, highlight = FALSE) {
        badge_class <- if (highlight) "bg-primary" else "bg-secondary"
        shiny::tags$tr(
          shiny::tags$td(
            class = "pe-2 text-muted small align-middle",
            style = "width:62px;",
            label
          ),
          shiny::tags$td(
            class = "small align-middle",
            if (is.null(r) || is.na(r)) {
              shiny::tags$em(class = "text-muted", "\u2014")
            } else {
              shiny::tags$span(
                class = paste0("badge ", badge_class),
                paste0(format(r, big.mark = ","), " rows \u00d7 ", c, " columns")
              )
            }
          )
        )
      }

      shiny::tags$table(
        class = "w-100 mb-1",
        shiny::tags$tbody(
          .dim_row("Original", nrow(orig), ncol(orig)),
          .dim_row("Current",  nrow(curr), ncol(curr)),
          .dim_row("Pending",  pend_r, pend_c, highlight = is_pending)
        )
      )
    })


    # ── Pending changes badge ─────────────────────────────────────────────────
    output$pending_badge <- shiny::renderUI({
      if (isTRUE(shared_state$has_pending_changes)) {
        n <- .count_pending_changes(shared_state)
        shiny::div(
          class = "alert alert-warning mb-0 py-2 text-center w-100",
          style = "font-size: 0.95rem; font-weight: 600;",
          shiny::icon("clock"), " ", n, " pending change(s)"
        )
      } else {
        shiny::div(
          class = "alert alert-success mb-0 py-2 text-center w-100",
          style = "font-size: 0.95rem; font-weight: 600;",
          shiny::icon("check"), " Up to date"
        )
      }
    })


    # ── Warnings panel ────────────────────────────────────────────────────────
    output$prepare_warnings <- shiny::renderUI({
      # Read all relevant fields at this level so Shiny registers them as
      # reactive dependencies of this output — do not rely solely on reads
      # buried inside helper-function calls.
      specs        <- shared_state$column_transform_specs
      filters      <- shared_state$row_filter_specs
      included     <- shared_state$included_columns
      last_applied <- shared_state$last_applied_specs
      has_pending  <- shared_state$has_pending_changes

      # No pending changes → nothing can be in conflict
      if (!isTRUE(has_pending)) return(NULL)

      warn_groups <- .build_prepare_warnings(specs, filters, included,
                                             last_applied,
                                             shared_state$dataset_original)
      if (length(warn_groups) == 0) return(NULL)

      shiny::div(
        class = "alert alert-danger py-2 px-2 mb-2 small",
        shiny::tags$strong(shiny::icon("triangle-exclamation"), " Warning(s):"),
        lapply(warn_groups, function(grp) {
          shiny::tagList(
            shiny::tags$div(class = "mt-1 fw-semibold small", grp$title),
            shiny::tags$ul(
              class = "mb-0 ps-3",
              lapply(grp$items, shiny::tags$li)
            )
          )
        })
      )
    })


    # ── Shared apply helper ───────────────────────────────────────────────────
    do_apply <- function() {
      # Remove filter specs that would be invalidated by staged transforms or
      # by column exclusion, before running the pipeline.
      .prune_conflicting_filter_specs(shared_state)

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

    # Shared reset helper — increments revert_trigger so module UIs sync.
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
      shared_state$revert_trigger <- shiny::isolate(shared_state$revert_trigger) + 1L
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
  names(.find_invalid_transforms_in(
    shiny::isolate(shared_state$column_transform_specs),
    shiny::isolate(shared_state$dataset_original)
  ))
}


# Return named list of col → reason string for the supplied transform specs.
# Accepts plain values so it can be called from both reactive and non-reactive contexts.
.find_invalid_transforms_in <- function(specs, dataset) {
  result  <- list()

  for (col in names(specs)) {
    spec <- specs[[col]]
    x    <- dataset[[col]]

    reason <- if (identical(spec$method, "cutpoints")) {
      breaks <- spec$breakpoints
      if (is.null(breaks) || length(breaks) == 0) {
        "no cutpoints specified"
      } else {
        x_min <- min(x, na.rm = TRUE)
        x_max <- max(x, na.rm = TRUE)
        if (length(breaks[breaks > x_min & breaks < x_max]) == 0)
          "cutpoints do not discriminate (all outside data range)"
        else
          NULL
      }
    } else if (identical(spec$method, "log")) {
      if (any(!is.na(x) & x <= 0)) "contains non-positive values (log undefined)" else NULL
    } else if (identical(spec$method, "winsorize")) {
      lo <- if (!is.null(spec$lower_pct)) spec$lower_pct else 1
      hi <- if (!is.null(spec$upper_pct)) spec$upper_pct else 99
      if (lo >= hi) "lower percentile must be less than upper" else NULL
    } else {
      NULL
    }

    if (!is.null(reason)) result[[col]] <- reason
  }
  result
}


# Build grouped warning list for the warnings panel.
# Accepts pre-read values (already extracted from shared_state in the renderUI)
# so all reactive dependencies are registered at the caller level.
# Returns a list of groups, each with $title (character) and $items (list of character).
.build_prepare_warnings <- function(specs, filters, included, last_applied, dataset) {
  groups <- list()

  # Group 1: columns with PENDING (changed-since-last-apply) transforms that also
  # have active row filters. A transform that was already applied and whose filter
  # was added afterward is not a conflict — only flag changes to the transform spec.
  if (length(specs) > 0 && length(filters) > 0) {
    last_tx <- if (!is.null(last_applied$column_transform_specs))
                 last_applied$column_transform_specs else list()
    pending_tx_cols <- Filter(function(col) {
      !identical(specs[[col]], last_tx[[col]])
    }, names(specs))
    conflict_cols <- intersect(pending_tx_cols, names(filters))
    if (length(conflict_cols) > 0) {
      groups <- c(groups, list(list(
        title = "Transform staged on column(s) with active row filter \u2014 filter will be removed on Apply:",
        items = as.list(conflict_cols)
      )))
    }
  }

  # Group 2: columns with row filters that are now excluded
  # (filter will be dropped on Apply since column is not in working dataset)
  if (length(filters) > 0) {
    excluded_filtered <- setdiff(names(filters), included)
    if (length(excluded_filtered) > 0) {
      groups <- c(groups, list(list(
        title = "Excluded column(s) have active row filters \u2014 filters will be removed on Apply:",
        items = as.list(excluded_filtered)
      )))
    }
  }

  # Group 3: transform validation issues (only for pending transforms)
  if (length(specs) > 0) {
    last_tx <- if (!is.null(last_applied$column_transform_specs))
                 last_applied$column_transform_specs else list()
    pending_specs <- specs[vapply(names(specs), function(col) {
      !identical(specs[[col]], last_tx[[col]])
    }, logical(1))]
    invalid_detail <- .find_invalid_transforms_in(pending_specs, dataset)
    if (length(invalid_detail) > 0) {
      items <- lapply(names(invalid_detail), function(col) {
        paste0(col, ": ", invalid_detail[[col]])
      })
      groups <- c(groups, list(list(
        title = "These variable transforms need attention:",
        items = items
      )))
    }
  }

  groups
}


# Remove row filter specs that would be invalidated before running the pipeline.
# Called at the top of do_apply() and .do_nav_apply().
#   - Pending transforms: only transforms that differ from last_applied_specs
#     (i.e., changed since the last Apply). A filter added on an already-applied
#     transform's output is valid and must not be removed.
#   - Excluded columns: column won't be in the working dataset.
.prune_conflicting_filter_specs <- function(shared_state) {
  specs        <- shiny::isolate(shared_state$column_transform_specs)
  filters      <- shiny::isolate(shared_state$row_filter_specs)
  included     <- shiny::isolate(shared_state$included_columns)
  last_applied <- shiny::isolate(shared_state$last_applied_specs)

  if (length(filters) == 0) return(invisible(NULL))

  last_tx <- if (!is.null(last_applied$column_transform_specs))
               last_applied$column_transform_specs else list()
  pending_tx_cols <- Filter(function(col) {
    !identical(specs[[col]], last_tx[[col]])
  }, names(specs))

  to_remove <- union(
    intersect(pending_tx_cols, names(filters)),  # pending-transform conflicts
    setdiff(names(filters), included)            # excluded column filters
  )

  if (length(to_remove) > 0) {
    for (col in to_remove) filters[[col]] <- NULL
    shared_state$row_filter_specs <- filters
  }

  invisible(NULL)
}
