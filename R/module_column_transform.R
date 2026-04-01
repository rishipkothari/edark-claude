#' Column Transform Module
#'
#' Allows the user to recode any numeric column as an ordered factor using
#' either auto-factoring (each unique value becomes a level) or user-defined
#' cut-point breakpoints with optional level labels. A preview table shows
#' the old value distribution mapped to the new level assignment before Apply.
#' Multiple transformations can be staged simultaneously.
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_column_transform
NULL


#' @rdname module_column_transform
#' @export
column_transform_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::card(
    bslib::card_header(shiny::icon("wand-magic-sparkles"), " Variable Transformations"),
    bslib::card_body(
      shiny::fluidRow(
        shiny::column(8, shiny::uiOutput(ns("numeric_col_picker"))),
        shiny::column(4,
          shiny::br(),
          shiny::actionButton(
            ns("add_transform"), "Add transformation",
            icon  = shiny::icon("plus"),
            class = "btn-sm btn-outline-primary w-100"
          )
        )
      ),
      shiny::hr(),
      shiny::uiOutput(ns("active_transforms"))
    )
  )
}


#' @rdname module_column_transform
#' @export
column_transform_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Column picker: only included numeric columns ───────────────────────────
    output$numeric_col_picker <- shiny::renderUI({
      included  <- shared_state$included_columns
      types     <- shared_state$column_types
      overrides <- shared_state$column_type_overrides
      # Effective type accounts for user overrides
      effective_type <- function(col) {
        if (!is.null(overrides[[col]])) overrides[[col]] else types[[col]]
      }
      numeric_cols <- Filter(function(col) effective_type(col) == "numeric", included)

      shinyWidgets::pickerInput(
        ns("transform_column"),
        label   = "Recode numeric column:",
        choices = numeric_cols,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })


    # ── Add transform button ──────────────────────────────────────────────────
    shiny::observeEvent(input$add_transform, {
      col <- input$transform_column
      if (is.null(col) || col == "") return()
      # Don't duplicate
      if (!is.null(shared_state$column_transform_specs[[col]])) return()

      x      <- shared_state$dataset_original[[col]]
      x_vals <- sort(unique(x[!is.na(x)]))

      # Default: auto-factor (each unique value becomes a level)
      spec <- list(
        method     = "auto",       # "auto" or "cutpoints"
        col        = col,
        values     = x_vals,
        breakpoints = NULL,
        labels      = NULL
      )

      specs      <- shared_state$column_transform_specs
      specs[[col]] <- spec
      shared_state$column_transform_specs  <- specs
      shared_state$has_pending_changes     <- TRUE
    })


    # ── Render staged transforms ──────────────────────────────────────────────
    output$active_transforms <- shiny::renderUI({
      specs <- shared_state$column_transform_specs
      if (length(specs) == 0) {
        return(shiny::tags$p(
          class = "text-muted small",
          "No transformations staged. Select a numeric column above to add one."
        ))
      }

      cards <- lapply(names(specs), function(col) {
        spec    <- specs[[col]]
        dataset <- shared_state$dataset_original
        .render_transform_card(ns, col, spec, dataset)
      })

      shiny::tagList(cards)
    })


    # ── Observe method toggle (auto vs cutpoints) ─────────────────────────────
    shiny::observe({
      specs <- shiny::isolate(shared_state$column_transform_specs)
      lapply(names(specs), function(col) {

        method_id <- paste0("method_", col)
        shiny::observeEvent(input[[method_id]], {
          s <- shared_state$column_transform_specs
          s[[col]]$method <- input[[method_id]]
          shared_state$column_transform_specs  <- s
          shared_state$has_pending_changes     <- TRUE
        }, ignoreNULL = TRUE, ignoreInit = TRUE)

        cuts_id <- paste0("cutpoints_", col)
        shiny::observeEvent(input[[cuts_id]], {
          raw <- input[[cuts_id]]
          # Parse comma-separated numeric breakpoints
          parsed <- suppressWarnings(as.numeric(trimws(strsplit(raw, ",")[[1]])))
          parsed <- sort(parsed[!is.na(parsed)])
          s <- shared_state$column_transform_specs
          s[[col]]$breakpoints <- parsed
          shared_state$column_transform_specs  <- s
          shared_state$has_pending_changes     <- TRUE
        }, ignoreNULL = TRUE, ignoreInit = TRUE)

        labels_id <- paste0("labels_", col)
        shiny::observeEvent(input[[labels_id]], {
          raw    <- input[[labels_id]]
          parsed <- trimws(strsplit(raw, ",")[[1]])
          parsed <- parsed[nchar(parsed) > 0]
          s <- shared_state$column_transform_specs
          s[[col]]$labels <- if (length(parsed) > 0) parsed else NULL
          shared_state$column_transform_specs  <- s
          shared_state$has_pending_changes     <- TRUE
        }, ignoreNULL = TRUE, ignoreInit = TRUE)

        remove_id <- paste0("remove_transform_", col)
        shiny::observeEvent(input[[remove_id]], {
          s <- shared_state$column_transform_specs
          s[[col]] <- NULL
          shared_state$column_transform_specs  <- s
          shared_state$has_pending_changes     <- TRUE
        }, ignoreInit = TRUE, once = TRUE)
      })
    })
  })
}


# ── Internal helpers ──────────────────────────────────────────────────────────

.render_transform_card <- function(ns, col, spec, dataset) {
  x      <- dataset[[col]]
  x_vals <- sort(unique(x[!is.na(x)]))

  remove_btn <- shiny::actionLink(
    ns(paste0("remove_transform_", col)),
    label = shiny::icon("times"),
    class = "text-danger float-end"
  )

  method_toggle <- shinyWidgets::radioGroupButtons(
    ns(paste0("method_", col)),
    label    = NULL,
    choices  = c("Auto-factor" = "auto", "Cut-points" = "cutpoints"),
    selected = spec$method,
    size     = "sm"
  )

  cutpoint_ui <- if (spec$method == "cutpoints") {
    shiny::tagList(
      shiny::textInput(
        ns(paste0("cutpoints_", col)),
        label       = "Breakpoints (comma-separated):",
        placeholder = "e.g. 18, 40, 65",
        value       = if (!is.null(spec$breakpoints))
                        paste(spec$breakpoints, collapse = ", ") else ""
      ),
      shiny::textInput(
        ns(paste0("labels_", col)),
        label       = "Level labels (comma-separated, optional):",
        placeholder = "e.g. Young, Middle, Old",
        value       = if (!is.null(spec$labels))
                        paste(spec$labels, collapse = ", ") else ""
      )
    )
  } else {
    NULL
  }

  # Preview table: old values → new levels
  preview_df <- .build_transform_preview(spec, x_vals)
  preview_tbl <- if (!is.null(preview_df)) {
    reactable::reactable(
      preview_df,
      compact   = TRUE,
      bordered  = TRUE,
      striped   = TRUE,
      highlight = TRUE,
      pagination = FALSE,
      height    = 200
    )
  } else {
    shiny::tags$p(class = "text-muted small", "Configure cut-points to see preview.")
  }

  bslib::card(
    class = "mb-3 border-start border-success border-3",
    bslib::card_body(
      shiny::fluidRow(
        shiny::column(10, shiny::tags$strong(col, " → ordered factor")),
        shiny::column(2,  remove_btn)
      ),
      shiny::br(),
      method_toggle,
      cutpoint_ui,
      shiny::br(),
      shiny::tags$small(shiny::tags$strong("Preview:")),
      preview_tbl
    )
  )
}


# Build a small data frame showing value → level assignment for preview.
.build_transform_preview <- function(spec, x_vals) {
  if (spec$method == "auto") {
    data.frame(
      Original_value = as.character(x_vals),
      New_level      = as.character(seq_along(x_vals)),
      stringsAsFactors = FALSE
    )
  } else {
    breaks <- spec$breakpoints
    if (is.null(breaks) || length(breaks) == 0) return(NULL)
    breaks_full <- c(-Inf, breaks, Inf)
    labels <- spec$labels
    if (is.null(labels) || length(labels) != length(breaks_full) - 1) {
      labels <- paste0("Level ", seq_len(length(breaks_full) - 1))
    }
    level_assigned <- cut(x_vals, breaks = breaks_full, labels = labels,
                          include.lowest = TRUE, right = FALSE)
    data.frame(
      Original_value = as.character(x_vals),
      New_level      = as.character(level_assigned),
      stringsAsFactors = FALSE
    )
  }
}
