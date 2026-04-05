#' Transform Variables Module
#'
#' Flat table showing one row per included numeric column. A selectInput
#' dropdown stages the transform type; inline config appears below the row
#' when configuration is needed.
#'
#' Available transform types:
#'   none        — no transform (unstages any existing spec)
#'   auto        — auto-factor (all unique values become ordered factor levels)
#'   cutpoints   — cut-points → ordered factor (breakpoints required)
#'   log         — log transform (base: ln / log10 / log2)
#'   winsorize   — winsorize to percentile bounds
#'   round       — round to N decimal places
#'   standardize — z-score standardise (mean=0, sd=1)
#'
#' State persistence: column_transform_specs is NOT cleared on Apply. The table
#' reflects the last-applied state when the user returns to this tab.
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
  shiny::div(
    style = "min-height: 400px; height: 100%;",
    shiny::uiOutput(ns("transform_table"))
  )
}


#' @rdname module_transform_variables
#' @export
transform_variables_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    registered_cols <- character(0)

    .transform_choices <- c(
      "None"                 = "none",
      "Auto-factor"          = "auto",
      "Cut-points"           = "cutpoints",
      "Log transform"        = "log",
      "Winsorize"            = "winsorize",
      "Round"                = "round",
      "Standardize (z-score)" = "standardize"
    )

    # ── Eligible columns: included numerics, in dataset order ─────────────────
    # Uses original_column_types so a previously-factored column still appears.
    eligible_cols <- shiny::reactive({
      all_cols   <- names(shared_state$dataset_original)
      orig_types <- shared_state$original_column_types
      incl       <- shared_state$included_columns
      all_cols[all_cols %in% incl & vapply(all_cols, function(c)
        identical(orig_types[[c]], "numeric"), logical(1))]
    })

    # Prune stale specs when eligible set changes (column excluded after Apply)
    shiny::observeEvent(eligible_cols(), {
      eligible <- eligible_cols()
      specs    <- shared_state$column_transform_specs
      stale    <- setdiff(names(specs), eligible)
      if (length(stale) > 0) {
        for (col in stale) specs[[col]] <- NULL
        shared_state$column_transform_specs <- specs
      }
    }, ignoreInit = TRUE)


    # ── Table: re-renders when eligible set changes ───────────────────────────
    output$transform_table <- shiny::renderUI({
      cols  <- eligible_cols()
      specs <- shiny::isolate(shared_state$column_transform_specs)
      ds    <- shiny::isolate(shared_state$dataset_original)

      if (length(cols) == 0) {
        return(bslib::card(
          bslib::card_body(
            shiny::tags$p(
              class = "text-muted small mb-0",
              shiny::icon("circle-info"),
              " No numeric columns available. Include numeric columns in the Columns tab."
            )
          )
        ))
      }

      header <- shiny::tags$thead(
        shiny::tags$tr(
          shiny::tags$th(style = "width:130px;", "Column"),
          shiny::tags$th(class = "text-end pe-3", style = "width:70px;", "Unique"),
          shiny::tags$th(style = "width:200px;", "Transform"),
          shiny::tags$th("Config")
        )
      )

      rows <- lapply(cols, function(col) {
        x        <- ds[[col]]
        n_unique <- length(unique(na.omit(x)))
        current  <- specs[[col]]
        selected <- if (!is.null(current)) current$method else "none"

        shiny::tags$tr(
          shiny::tags$td(class = "py-1 align-top small fw-semibold", col),
          shiny::tags$td(class = "py-1 align-top text-end pe-3 text-muted small",
            format(n_unique, big.mark = ",")),
          shiny::tags$td(class = "py-1 align-top",
            shiny::selectInput(
              ns(paste0("type_", col)),
              label    = NULL,
              choices  = .transform_choices,
              selected = selected,
              width    = "100%"
            )
          ),
          shiny::tags$td(class = "py-1 align-top",
            shiny::uiOutput(ns(paste0("config_", col)))
          )
        )
      })

      bslib::card(
        bslib::card_body(
          class = "p-0",
          shiny::tags$table(
            class = "table table-sm table-hover align-middle mb-0",
            header,
            shiny::tags$tbody(rows)
          )
        )
      )
    })


    # ── Per-column config UI + observers — registered lazily ──────────────────
    shiny::observe({
      cols     <- eligible_cols()
      new_cols <- setdiff(cols, registered_cols)
      if (length(new_cols) == 0) return()

      for (col in new_cols) {
        local({
          .col <- col

          # Config section: re-renders when transform type changes
          output[[paste0("config_", .col)]] <- shiny::renderUI({
            method <- input[[paste0("type_", .col)]]
            if (is.null(method) || method %in% c("none", "auto", "standardize"))
              return(NULL)

            specs <- shared_state$column_transform_specs
            spec  <- specs[[.col]]

            if (identical(method, "cutpoints")) {
              bp_val  <- if (!is.null(spec$breakpoints) && length(spec$breakpoints) > 0)
                           paste(spec$breakpoints, collapse = ", ") else ""
              lbl_val <- if (!is.null(spec$labels)) paste(spec$labels, collapse = ", ") else ""
              return(shiny::tagList(
                shiny::textInput(
                  ns(paste0("bp_", .col)),
                  label       = "Breakpoints (comma-separated):",
                  placeholder = "e.g. 18, 40, 65",
                  value       = bp_val
                ),
                shiny::textInput(
                  ns(paste0("lbl_", .col)),
                  label       = "Level labels (optional \u2014 defaults to numeric ranges):",
                  placeholder = "e.g. Young, Middle, Old",
                  value       = lbl_val
                )
              ))
            }

            if (identical(method, "log")) {
              return(shiny::radioButtons(
                ns(paste0("logbase_", .col)),
                label    = "Base:",
                choices  = c("Natural (ln)" = "ln", "log\u2081\u2080" = "log10", "log\u2082" = "log2"),
                selected = if (!is.null(spec$log_base)) spec$log_base else "ln",
                inline   = TRUE
              ))
            }

            if (identical(method, "winsorize")) {
              return(shiny::fluidRow(
                shiny::column(6,
                  shiny::numericInput(
                    ns(paste0("lo_", .col)),
                    label = "Lower percentile:",
                    value = if (!is.null(spec$lower_pct)) spec$lower_pct else 1,
                    min = 0, max = 100, step = 0.5
                  )
                ),
                shiny::column(6,
                  shiny::numericInput(
                    ns(paste0("hi_", .col)),
                    label = "Upper percentile:",
                    value = if (!is.null(spec$upper_pct)) spec$upper_pct else 99,
                    min = 0, max = 100, step = 0.5
                  )
                )
              ))
            }

            if (identical(method, "round")) {
              return(shiny::numericInput(
                ns(paste0("dp_", .col)),
                label = "Decimal places:",
                value = if (!is.null(spec$decimal_places)) spec$decimal_places else 0,
                min = 0, max = 10, step = 1
              ))
            }

            NULL
          })


          # Type observer — stages / unstages spec
          shiny::observeEvent(input[[paste0("type_", .col)]], {
            method <- input[[paste0("type_", .col)]]
            if (is.null(method)) return()

            specs <- shared_state$column_transform_specs

            if (identical(method, "none")) {
              specs[[.col]] <- NULL
            } else {
              existing <- specs[[.col]]
              # Preserve sub-fields if method unchanged, else reset to defaults
              if (!is.null(existing) && identical(existing$method, method)) {
                # method unchanged — leave spec alone (user may be returning to tab)
              } else {
                specs[[.col]] <- switch(method,
                  auto        = list(col = .col, method = "auto"),
                  cutpoints   = list(col = .col, method = "cutpoints",
                                     breakpoints = NULL, labels = NULL),
                  log         = list(col = .col, method = "log", log_base = "ln"),
                  winsorize   = list(col = .col, method = "winsorize",
                                     lower_pct = 1, upper_pct = 99),
                  round       = list(col = .col, method = "round", decimal_places = 0),
                  standardize = list(col = .col, method = "standardize"),
                  list(col = .col, method = method)
                )
              }
            }

            shared_state$column_transform_specs <- specs
            shared_state$has_pending_changes    <- TRUE
          }, ignoreNULL = TRUE, ignoreInit = TRUE)


          # Breakpoints observer
          shiny::observeEvent(input[[paste0("bp_", .col)]], {
            raw    <- input[[paste0("bp_", .col)]]
            parsed <- suppressWarnings(as.numeric(trimws(strsplit(raw, ",")[[1]])))
            parsed <- sort(parsed[!is.na(parsed)])
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$breakpoints, parsed)) {
              s[[.col]]$breakpoints            <- parsed
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)


          # Labels observer
          shiny::observeEvent(input[[paste0("lbl_", .col)]], {
            raw     <- input[[paste0("lbl_", .col)]]
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


          # Log base observer
          shiny::observeEvent(input[[paste0("logbase_", .col)]], {
            val <- input[[paste0("logbase_", .col)]]
            s   <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$log_base, val)) {
              s[[.col]]$log_base               <- val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)


          # Lower percentile observer
          shiny::observeEvent(input[[paste0("lo_", .col)]], {
            val <- as.numeric(input[[paste0("lo_", .col)]])
            if (is.na(val)) return()
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$lower_pct, val)) {
              s[[.col]]$lower_pct              <- val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)


          # Upper percentile observer
          shiny::observeEvent(input[[paste0("hi_", .col)]], {
            val <- as.numeric(input[[paste0("hi_", .col)]])
            if (is.na(val)) return()
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$upper_pct, val)) {
              s[[.col]]$upper_pct              <- val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)


          # Decimal places observer
          shiny::observeEvent(input[[paste0("dp_", .col)]], {
            val <- as.integer(max(0L, as.integer(input[[paste0("dp_", .col)]])))
            if (is.na(val)) return()
            s <- shared_state$column_transform_specs
            if (!is.null(s[[.col]]) && !identical(s[[.col]]$decimal_places, val)) {
              s[[.col]]$decimal_places         <- val
              shared_state$column_transform_specs  <- s
              shared_state$has_pending_changes     <- TRUE
            }
          }, ignoreNULL = TRUE, ignoreInit = TRUE)

        })  # end local()

        registered_cols <<- c(registered_cols, col)
      }
    })

  })
}
