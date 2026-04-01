#' Column Manager Module
#'
#' Displays all columns in the dataset with their detected types. The user can
#' toggle inclusion/exclusion of individual columns and manually override a
#' column's detected type. All changes are staged — nothing is applied to the
#' working dataset until the user clicks "Apply & Proceed" in the Prepare
#' Confirm module.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object (the app-wide state).
#'
#' @name module_column_manager
NULL


#' @rdname module_column_manager
#' @export
column_manager_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    bslib::card_header(
      shiny::icon("columns"), " Column Manager",
      shiny::actionLink(
        ns("select_all"),   "Select all",   class = "ms-3 small"
      ),
      shiny::actionLink(
        ns("deselect_all"), "Deselect all", class = "ms-2 small"
      )
    ),
    bslib::card_body(
      shiny::uiOutput(ns("column_table"))
    )
  )
}


#' @rdname module_column_manager
#' @export
column_manager_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Valid type choices the user can select from
    type_choices <- c("numeric", "factor", "datetime", "character")

    # ── Render the column table ──────────────────────────────────────────────
    # One row per column: checkbox | column name | type dropdown
    output$column_table <- shiny::renderUI({
      col_names   <- names(shiny::isolate(shared_state$dataset_original))
      col_types   <- shiny::isolate(shared_state$column_types)
      included    <- shiny::isolate(shared_state$included_columns)
      overrides   <- shiny::isolate(shared_state$column_type_overrides)

      rows <- lapply(col_names, function(col) {
        current_type     <- if (!is.null(overrides[[col]])) overrides[[col]] else col_types[[col]]
        is_included      <- col %in% included
        checkbox_id      <- ns(paste0("include_", col))
        type_select_id   <- ns(paste0("type_", col))

        shiny::fluidRow(
          class = "align-items-center mb-1",
          shiny::column(1,
            shiny::checkboxInput(checkbox_id, label = NULL, value = is_included)
          ),
          shiny::column(5,
            shiny::tags$span(col, class = "fw-semibold")
          ),
          shiny::column(4,
            shinyWidgets::pickerInput(
              inputId  = type_select_id,
              label    = NULL,
              choices  = type_choices,
              selected = current_type,
              options  = shinyWidgets::pickerOptions(container = "body")
            )
          ),
          shiny::column(2,
            shiny::tags$span(
              class = paste0("badge rounded-pill bg-", .type_badge_colour(current_type)),
              current_type
            )
          )
        )
      })

      shiny::tagList(rows)
    })


    # ── React to individual checkbox / type changes ──────────────────────────
    # We use observe() on each input dynamically after the UI renders.
    shiny::observe({
      col_names <- names(shared_state$dataset_original)

      lapply(col_names, function(col) {
        checkbox_id    <- paste0("include_", col)
        type_select_id <- paste0("type_",   col)

        # Watch inclusion checkbox
        shiny::observeEvent(input[[checkbox_id]], {
          included <- shared_state$included_columns
          if (isTRUE(input[[checkbox_id]])) {
            if (!col %in% included) {
              shared_state$included_columns   <- c(included, col)
              shared_state$has_pending_changes <- TRUE
            }
          } else {
            shared_state$included_columns    <- setdiff(included, col)
            shared_state$has_pending_changes <- TRUE
          }
        }, ignoreInit = TRUE)

        # Watch type override dropdown
        shiny::observeEvent(input[[type_select_id]], {
          original_type <- shared_state$column_types[[col]]
          chosen_type   <- input[[type_select_id]]

          if (!is.null(chosen_type) && !identical(chosen_type, original_type)) {
            shared_state$column_type_overrides[[col]] <- chosen_type
          } else {
            # Revert: remove the override entry
            overrides <- shared_state$column_type_overrides
            overrides[[col]] <- NULL
            shared_state$column_type_overrides <- overrides
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
      # Update all checkboxes in the UI
      lapply(col_names, function(col) {
        shiny::updateCheckboxInput(session, paste0("include_", col), value = TRUE)
      })
    })

    shiny::observeEvent(input$deselect_all, {
      shared_state$included_columns    <- character(0)
      shared_state$has_pending_changes <- TRUE
      col_names <- names(shared_state$dataset_original)
      lapply(col_names, function(col) {
        shiny::updateCheckboxInput(session, paste0("include_", col), value = FALSE)
      })
    })
  })
}


# Returns a Bootstrap colour name for a type badge.
.type_badge_colour <- function(type) {
  switch(type,
    numeric  = "primary",
    factor   = "success",
    datetime = "warning",
    character = "secondary",
    "secondary"
  )
}
