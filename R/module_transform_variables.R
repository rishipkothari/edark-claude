#' Transform Variables Module
#'
#' Displays an accordion of staged transforms, ordered by original column
#' position. Each panel's cut-point UI renders independently so that toggling
#' the method does not collapse the accordion panel.
#'
#' Rules:
#' - Columns with ≤ 20 unique values: Auto-factor or Cut-points available
#' - Columns with > 20 unique values: Cut-points only (method selector hidden)
#'
#' @param id Character. The module namespace ID.
#' @param shared_state A Shiny `reactiveValues` object.
#'
#' @name module_transform_variables
NULL


#' @rdname module_transform_variables
#' @export
transform_variables_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("transform_accordion"))
}


#' @rdname module_transform_variables
#' @export
transform_variables_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    registered_cols <- character(0)

    # ── Structural reactive: fires only when the SET of staged columns changes ─
    # Method changes do NOT trigger a full accordion re-render — the cut-point
    # section inside each panel is its own renderUI, keyed off method alone.
    staged_col_names <- shiny::reactive({
      # Preserve original column order rather than click order
      all_cols    <- names(shiny::isolate(shared_state$dataset_original))
      staged_keys <- names(shared_state$column_transform_specs)
      all_cols[all_cols %in% staged_keys]
    })


    # ── Accordion: re-renders only when staged columns are added/removed ───────
    output$transform_accordion <- shiny::renderUI({
      cols <- staged_col_names()

      if (length(cols) == 0) {
        return(shiny::tags$p(
          class = "text-muted small",
          shiny::icon("circle-info"),
          " No transforms staged. Go to the Columns tab and check",
          " \u2018Transform\u2019 next to any numeric column."
        ))
      }

      # Keep all panels open — avoids collapse when method input fires
      panel_values <- paste0("panel_", cols)
      dataset      <- shiny::isolate(shared_state$dataset_original)
      specs        <- shiny::isolate(shared_state$column_transform_specs)

      panels <- lapply(cols, function(col) {
        spec     <- specs[[col]]
        x        <- dataset[[col]]
        n_unique <- length(unique(na.omit(x)))
        force_cutpoints <- n_unique > 20

        method_ui <- if (force_cutpoints) {
          shiny::tags$p(
            class = "text-muted small",
            shiny::icon("circle-info"),
            " This column has ", n_unique,
            " unique values \u2014 cut-points required."
          )
        } else {
          shinyWidgets::radioGroupButtons(
            ns(paste0("method_", col)),
            label    = "Method:",
            choices  = c("Auto-factor" = "auto", "Cut-points" = "cutpoints"),
            selected = as.character(spec$method),
            size     = "sm"
          )
        }

        # Cut-point inputs live in their own renderUI so toggling method only
        # re-renders this section, not the entire accordion.
        bslib::accordion_panel(
          value = paste0("panel_", col),
          title = shiny::tags$span(
            shiny::tags$strong(col),
            shiny::tags$span(" \u2192 ordered factor", class = "text-muted small ms-2"),
            if (force_cutpoints)
              shiny::tags$span(
                class = "badge bg-warning text-dark ms-2 small",
                "cut-points required"
              )
          ),
          method_ui,
          shiny::uiOutput(ns(paste0("cutpoints_ui_", col)))
        )
      })

      do.call(bslib::accordion, c(list(open = panel_values), panels))
    })


    # ── Per-column cutpoint UI — re-renders when method changes ──────────────
    # Registered whenever a new column appears in staged_col_names.
    shiny::observe({
      cols     <- staged_col_names()
      new_cols <- setdiff(cols, registered_cols)
      if (length(new_cols) == 0) return()

      for (col in new_cols) {
        local({
          .col <- col

          # Cut-point section: only shows when method == "cutpoints"
          output[[paste0("cutpoints_ui_", .col)]] <- shiny::renderUI({
            specs <- shared_state$column_transform_specs
            spec  <- specs[[.col]]
            if (is.null(spec)) return(NULL)

            if (!identical(spec$method, "cutpoints")) return(NULL)

            bp_val    <- if (!is.null(spec$breakpoints) && length(spec$breakpoints) > 0)
                           paste(spec$breakpoints, collapse = ", ") else ""
            label_val <- if (!is.null(spec$labels)) paste(spec$labels, collapse = ", ") else ""

            shiny::tagList(
              shiny::textInput(
                ns(paste0("cutpoints_", .col)),
                label       = "Breakpoints (comma-separated):",
                placeholder = "e.g. 18, 40, 65",
                value       = bp_val
              ),
              shiny::textInput(
                ns(paste0("labels_", .col)),
                label       = "Level labels (optional — defaults to numeric ranges):",
                placeholder = "e.g. Young, Middle, Old",
                value       = label_val
              )
            )
          })

          # Method observer
          shiny::observeEvent(input[[paste0("method_", .col)]], {
            val <- input[[paste0("method_", .col)]]
            s   <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$method, val)) {
              s[[.col]]$method                 <- val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)

          # Breakpoints observer — !identical guard prevents feedback loops
          shiny::observeEvent(input[[paste0("cutpoints_", .col)]], {
            raw    <- input[[paste0("cutpoints_", .col)]]
            parsed <- suppressWarnings(
              as.numeric(trimws(strsplit(raw, ",")[[1]])))
            parsed <- sort(parsed[!is.na(parsed)])
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$breakpoints, parsed)) {
              s[[.col]]$breakpoints            <- parsed
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)

          # Labels observer
          shiny::observeEvent(input[[paste0("labels_", .col)]], {
            raw     <- input[[paste0("labels_", .col)]]
            parsed  <- trimws(strsplit(raw, ",")[[1]])
            parsed  <- parsed[nchar(parsed) > 0]
            new_val <- if (length(parsed) > 0) parsed else NULL
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$labels, new_val)) {
              s[[.col]]$labels                 <- new_val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)
        })

        registered_cols <<- c(registered_cols, col)
      }
    })
  })
}
