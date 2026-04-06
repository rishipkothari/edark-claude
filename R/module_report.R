#' Report Module
#'
#' UI and server for the Report stage. Lets the user configure and download a
#' report from the current working dataset. Provides two top-level pill tabs:
#' \itemize{
#'   \item \strong{Full Report} — auto-generated report (Describe Variables or
#'     Correlation mode).
#'   \item \strong{Custom Report} — user-curated collection of plots added from
#'     the Explore tab.
#' }
#' Output formats: PowerPoint (\code{.pptx}), Word (\code{.docx}),
#' or HTML (\code{.html}).
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object (shared across modules).
#'
#' @name module_report
NULL


# Helper: encode a thumbnail PNG as a base64 data URI for inline <img> display.
.thumb_src <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return("")
  paste0("data:image/png;base64,", base64enc::base64encode(path))
}


#' @rdname module_report
#' @export
report_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::navset_pill(
    id = ns("report_mode_tabs"),

    # ── Full Report pill ──────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "full_report",
      title = shiny::tagList(shiny::icon("file-lines"), " Full Report"),

      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 300,

          # ── Report type ────────────────────────────────────────────────────
          shinyWidgets::radioGroupButtons(
            ns("report_type"),
            label    = NULL,
            choices  = c("Describe Variables" = "all_vars",
                         "Correlation"        = "primary_vs_others"),
            selected = "all_vars",
            size     = "sm",
            width    = "100%"
          ),

          # ── Primary variable (Correlation only) ────────────────────────────
          shiny::conditionalPanel(
            condition = paste0("input['", ns("report_type"), "'] == 'primary_vs_others'"),
            shiny::tags$p(class = "fw-semibold mb-1 mt-2",
                          shiny::icon("crosshairs"), " Primary Variable"),
            shiny::uiOutput(ns("primary_var_picker")),
            shinyWidgets::radioGroupButtons(
              ns("primary_role"),
              label    = "Role:",
              choices  = c("Exposure (X-axis)" = "exposure",
                           "Outcome (Y-axis)"  = "outcome"),
              selected = "exposure",
              size     = "sm",
              width    = "100%"
            )
          ),

          # ── Stratify By ────────────────────────────────────────────────────
          shiny::tags$p(class = "fw-semibold mb-1 mt-2",
                        shiny::icon("layer-group"), " Stratify By"),
          shiny::uiOutput(ns("stratify_picker")),

          # ── Variable selection ─────────────────────────────────────────────
          shiny::tags$p(class = "fw-semibold mb-1 mt-2",
                        shiny::icon("list-check"), " Variables"),
          shiny::uiOutput(ns("var_selection_summary")),
          shiny::actionButton(
            ns("open_var_modal"),
            label = "Select Variables\u2026",
            icon  = shiny::icon("sliders"),
            class = "btn-outline-secondary w-100 mt-1"
          ),

          # ── Output format ──────────────────────────────────────────────────
          shiny::tags$p(class = "fw-semibold mb-1 mt-2",
                        shiny::icon("download"), " Output Format"),
          shinyWidgets::radioGroupButtons(
            ns("output_format"),
            label    = NULL,
            choices  = c("PowerPoint" = "pptx",
                         "Word"       = "docx",
                         "HTML"       = "html"),
            selected = "pptx",
            size     = "sm",
            width    = "100%"
          ),

          shiny::br(),

          # ── Generate ──────────────────────────────────────────────────────
          shiny::downloadButton(
            ns("download_btn"),
            label = "Generate & Download",
            class = "btn-primary w-100"
          )
        ),

        # Main panel
        bslib::card(
          full_screen = FALSE,
          bslib::card_header(shiny::icon("file-export"), " Report Preview"),
          bslib::card_body(
            shiny::uiOutput(ns("report_summary_panel"))
          )
        )
      )
    ),

    # ── Custom Report pill ────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "custom_report",
      title = shiny::tagList(shiny::icon("layer-group"), " Custom Report"),

      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 320,

          # ── Item gallery ───────────────────────────────────────────────────
          bslib::card(
            bslib::card_header(shiny::icon("images"), " Report Items"),
            bslib::card_body(
              shiny::uiOutput(ns("custom_items_gallery"))
            )
          ),

          shiny::br(),

          # ── Output format ──────────────────────────────────────────────────
          bslib::card(
            bslib::card_header(shiny::icon("download"), " Output Format"),
            bslib::card_body(
              shinyWidgets::radioGroupButtons(
                ns("custom_output_format"),
                label    = NULL,
                choices  = c("PowerPoint" = "pptx",
                             "Word"       = "docx",
                             "HTML"       = "html"),
                selected = "pptx",
                size     = "sm",
                width    = "100%"
              )
            )
          ),

          shiny::br(),

          # ── Generate ──────────────────────────────────────────────────────
          shiny::downloadButton(
            ns("custom_download_btn"),
            label = "Generate & Download",
            class = "btn-primary w-100"
          )
        ),

        # Main panel — preview of items
        bslib::card(
          full_screen = FALSE,
          bslib::card_header(shiny::icon("eye"), " Preview"),
          bslib::card_body(
            shiny::uiOutput(ns("custom_preview_panel"))
          )
        )
      )
    )
  )
}


#' @rdname module_report
#' @export
report_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Navigate to a report sub-tab when requested externally (e.g. "View Report")
    shiny::observeEvent(shared_state$requested_report_subtab, {
      shiny::req(!is.null(shared_state$requested_report_subtab))
      bslib::nav_select("report_mode_tabs", shared_state$requested_report_subtab, session = session)
      shared_state$requested_report_subtab <- NULL
    })

    # Track which variables the user has selected (NULL = all eligible)
    selected_vars <- shiny::reactiveVal(NULL)

    # Helper: eligible columns (numeric + factor only, no datetime/character)
    eligible_vars <- shiny::reactive({
      types <- shared_state$column_types
      names(types)[types %in% c("numeric", "factor")]
    })

    # Initialise selected_vars when the working dataset is first available
    shiny::observe({
      req(shared_state$dataset_working)
      if (is.null(selected_vars()))
        selected_vars(eligible_vars())
    })

    # When the dataset changes (after Apply), reset selection to new eligible set
    shiny::observeEvent(shared_state$dataset_working, {
      selected_vars(eligible_vars())
    }, ignoreInit = TRUE)

    # ── Dynamic pickers ───────────────────────────────────────────────────────

    output$primary_var_picker <- shiny::renderUI({
      types    <- shared_state$column_types
      eligible <- names(types)[types %in% c("numeric", "factor")]
      shinyWidgets::pickerInput(
        ns("primary_variable"),
        label   = "Primary variable:",
        choices = eligible,
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      # In correlation mode, exclude the primary variable
      if (isTRUE(input$report_type == "primary_vs_others"))
        factor_cols <- setdiff(factor_cols, input$primary_variable)
      shinyWidgets::pickerInput(
        ns("stratify_variable"),
        label    = "Stratify by:",
        choices  = c("None" = "", factor_cols),
        selected = "",
        options  = shinyWidgets::pickerOptions(container = "body")
      )
    })

    # ── Variable selection summary ────────────────────────────────────────────

    output$var_selection_summary <- shiny::renderUI({
      elig  <- eligible_vars()
      sel   <- selected_vars()
      if (is.null(sel)) sel <- elig
      # In correlation mode, exclude primary and stratify variables from the count
      if (input$report_type == "primary_vs_others" && !is.null(input$primary_variable)) {
        sel  <- setdiff(sel, input$primary_variable)
        elig <- setdiff(elig, input$primary_variable)
        sv <- input$stratify_variable
        if (!is.null(sv) && nzchar(sv)) {
          sel  <- setdiff(sel, sv)
          elig <- setdiff(elig, sv)
        }
      }
      n_sel   <- length(intersect(sel, elig))
      n_total <- length(elig)
      shiny::tags$p(
        class = "text-muted small mb-1",
        paste0(n_sel, " of ", n_total, " variables selected")
      )
    })

    # ── Variable selection modal ──────────────────────────────────────────────

    shiny::observeEvent(input$open_var_modal, {
      elig      <- eligible_vars()
      currently <- selected_vars()
      if (is.null(currently)) currently <- elig

      # In correlation mode, exclude primary and stratify variables from the selector.
      if (input$report_type == "primary_vs_others" && !is.null(input$primary_variable)) {
        elig      <- setdiff(elig, input$primary_variable)
        currently <- setdiff(currently, input$primary_variable)
        sv <- input$stratify_variable
        if (!is.null(sv) && nzchar(sv)) {
          elig      <- setdiff(elig, sv)
          currently <- setdiff(currently, sv)
        }
      }

      shiny::showModal(shiny::modalDialog(
        title = "Select Variables for Report",
        shiny::checkboxGroupInput(
          ns("modal_vars"),
          label    = NULL,
          choices  = elig,
          selected = currently
        ),
        footer = shiny::tagList(
          shiny::actionButton(ns("modal_select_all"),   "Select All",
                              class = "btn-sm btn-outline-secondary"),
          shiny::actionButton(ns("modal_deselect_all"), "Deselect All",
                              class = "btn-sm btn-outline-secondary ms-2"),
          shiny::tags$span(class = "flex-grow-1"),
          shiny::actionButton(ns("modal_done"), "Done",
                              class = "btn-primary"),
          shiny::modalButton("Cancel")
        ),
        easyClose = FALSE,
        size      = "m"
      ))
    })

    shiny::observeEvent(input$modal_select_all, {
      elig <- eligible_vars()
      if (input$report_type == "primary_vs_others" && !is.null(input$primary_variable)) {
        elig <- setdiff(elig, input$primary_variable)
        sv <- input$stratify_variable
        if (!is.null(sv) && nzchar(sv)) elig <- setdiff(elig, sv)
      }
      shiny::updateCheckboxGroupInput(session, "modal_vars", selected = elig)
    })

    shiny::observeEvent(input$modal_deselect_all, {
      shiny::updateCheckboxGroupInput(session, "modal_vars", selected = character(0))
    })

    shiny::observeEvent(input$modal_done, {
      selected_vars(input$modal_vars)
      shiny::removeModal()
    })

    # ── Full report: main panel summary ──────────────────────────────────────

    output$report_summary_panel <- shiny::renderUI({
      ds   <- shared_state$dataset_working
      elig <- eligible_vars()
      sel  <- selected_vars()
      if (is.null(sel)) sel <- elig

      type_label <- switch(input$report_type,
        all_vars          = "Describe Variables",
        primary_vs_others = "Correlation",
        "\u2014"
      )
      format_label <- switch(input$output_format %||% "pptx",
        pptx = "PowerPoint (.pptx)",
        docx = "Word (.docx)",
        html = "HTML (.html)",
        "\u2014"
      )

      n_rows <- if (!is.null(ds)) nrow(ds) else "\u2014"
      n_cols <- if (!is.null(ds)) ncol(ds) else "\u2014"

      sv <- input$stratify_variable
      strat_label <- if (is.null(sv) || !nzchar(sv)) "None" else sv

      sec_vars <- if (input$report_type == "primary_vs_others" && !is.null(input$primary_variable)) {
        v <- setdiff(intersect(sel, elig), input$primary_variable)
        if (!is.null(sv) && nzchar(sv)) setdiff(v, sv) else v
      } else {
        v <- intersect(sel, elig)
        if (!is.null(sv) && nzchar(sv)) setdiff(v, sv) else v
      }
      n_sections <- length(sec_vars)

      primary_row <- if (input$report_type == "primary_vs_others") {
        pv   <- input$primary_variable %||% "\u2014"
        role <- if ((input$primary_role %||% "exposure") == "exposure") "Exposure (X)" else "Outcome (Y)"
        shiny::tagList(
          shiny::tags$tr(
            shiny::tags$th("Primary variable"),
            shiny::tags$td(paste0(pv, " \u2014 ", role))
          ),
          shiny::tags$tr(
            shiny::tags$th("Stratify by"),
            shiny::tags$td(strat_label)
          )
        )
      } else {
        shiny::tags$tr(
          shiny::tags$th("Stratify by"),
          shiny::tags$td(strat_label)
        )
      }

      shiny::tagList(
        shiny::tags$table(
          class = "table table-sm table-borderless mb-3",
          style = "max-width: 480px;",
          shiny::tags$tbody(
            shiny::tags$tr(
              shiny::tags$th(style = "width:180px;", "Report type"),
              shiny::tags$td(type_label)
            ),
            shiny::tags$tr(
              shiny::tags$th("Output format"),
              shiny::tags$td(format_label)
            ),
            shiny::tags$tr(
              shiny::tags$th("Dataset"),
              shiny::tags$td(paste0(n_rows, " rows \u00d7 ", n_cols, " columns"))
            ),
            primary_row,
            shiny::tags$tr(
              shiny::tags$th("Sections"),
              shiny::tags$td(paste0(n_sections, " variable", if (n_sections != 1) "s" else ""))
            )
          )
        ),
        if (n_sections > 0) {
          shiny::tags$div(
            class = "text-muted small",
            shiny::tags$strong("Variables: "),
            paste(sec_vars, collapse = ", ")
          )
        } else {
          shiny::tags$p(class = "text-warning small",
                        shiny::icon("triangle-exclamation"), " No variables selected.")
        },
        shiny::tags$hr(),
        shiny::tags$p(
          class = "text-muted small",
          shiny::icon("circle-info"), " ",
          "Configure your report in the sidebar, then click ",
          shiny::tags$strong("Generate & Download"), ".",
          shiny::tags$br(),
          "Generation time scales with the number of variables."
        )
      )
    })

    # ── Full report: download handler ─────────────────────────────────────────

    output$download_btn <- shiny::downloadHandler(
      filename = function() {
        ext <- switch(input$output_format,
                      pptx = ".pptx", docx = ".docx", html = ".html")
        paste0("edark_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
      },
      content = function(file) {
        vars <- selected_vars()
        if (is.null(vars) || length(vars) == 0) vars <- eligible_vars()

        n_sections <- if (input$report_type == "primary_vs_others") {
          length(setdiff(vars, input$primary_variable))
        } else {
          length(vars)
        }

        tryCatch({
          shiny::withProgress(
            message = paste0("Generating report (", n_sections, " sections)\u2026"),
            value   = 0,
            {
              generate_report(
                dataset           = shared_state$dataset_working,
                column_types      = shared_state$column_types,
                report_type       = input$report_type,
                variables         = vars,
                primary_variable  = if (input$report_type == "primary_vs_others")
                                       input$primary_variable else NULL,
                primary_role      = input$primary_role %||% "exposure",
                stratify_variable = {
                  sv <- input$stratify_variable
                  if (is.null(sv) || !nzchar(sv)) NULL else sv
                },
                format      = input$output_format,
                output_path = file,
                progress_fn = function(frac, detail) {
                  shiny::setProgress(value = frac, detail = detail)
                }
              )
            }
          )
        }, error = function(e) {
          shiny::showNotification(
            paste("Report generation failed:", conditionMessage(e)),
            type     = "error",
            duration = 10
          )
          stop(e)
        })
      }
    )


    # ── Custom Report: gallery ────────────────────────────────────────────────

    output$custom_items_gallery <- shiny::renderUI({
      items <- shared_state$custom_report_items
      n     <- length(items)

      if (n == 0) {
        return(shiny::tags$p(
          class = "text-muted small",
          shiny::icon("circle-info"), " No items yet.",
          shiny::tags$br(),
          "Add plots from the Explore tab using the",
          shiny::tags$strong("Add to Custom Report"), "button."
        ))
      }

      shiny::tagList(
        lapply(seq_along(items), function(i) {
          item <- items[[i]]
          shiny::div(
            class = "d-flex align-items-center gap-2 mb-2 p-2 border rounded",
            # Thumbnail
            shiny::tags$img(
              src   = .thumb_src(item$thumb_path),
              width = "80px", height = "60px",
              style = "object-fit:cover; border-radius:4px; flex-shrink:0;"
            ),
            # Title
            shiny::div(
              class = "flex-grow-1 small",
              shiny::tags$strong(item$title)
            ),
            # Reorder and remove controls
            shiny::div(
              class = "d-flex flex-column gap-1",
              if (i > 1)
                shiny::actionButton(
                  ns(paste0("up_", item$id)),
                  label = NULL, icon = shiny::icon("angle-up"),
                  class = "btn-sm btn-outline-secondary p-1"
                ),
              if (i < n)
                shiny::actionButton(
                  ns(paste0("down_", item$id)),
                  label = NULL, icon = shiny::icon("angle-down"),
                  class = "btn-sm btn-outline-secondary p-1"
                ),
              shiny::actionButton(
                ns(paste0("remove_", item$id)),
                label = NULL, icon = shiny::icon("trash"),
                class = "btn-sm btn-outline-danger p-1"
              )
            )
          )
        })
      )
    })

    # Dynamic observer registration for per-item up/down/remove buttons.
    # Uses the same lazy-registration + local() closure pattern as module_row_filter.R
    # to avoid double-registration and R closure capture issues.
    registered_item_ids <- shiny::reactiveVal(character(0))

    shiny::observe({
      items   <- shared_state$custom_report_items
      ids     <- vapply(items, `[[`, character(1), "id")
      new_ids <- setdiff(ids, registered_item_ids())
      if (!length(new_ids)) return()

      for (item_id in new_ids) {
        local({
          iid <- item_id

          shiny::observeEvent(input[[paste0("remove_", iid)]], {
            shared_state$custom_report_items <-
              Filter(function(x) x$id != iid, shared_state$custom_report_items)
          }, ignoreInit = TRUE)

          shiny::observeEvent(input[[paste0("up_", iid)]], {
            curr <- shared_state$custom_report_items
            idx  <- which(vapply(curr, `[[`, character(1), "id") == iid)
            if (length(idx) == 1 && idx > 1) {
              curr[c(idx - 1, idx)] <- curr[c(idx, idx - 1)]
              shared_state$custom_report_items <- curr
            }
          }, ignoreInit = TRUE)

          shiny::observeEvent(input[[paste0("down_", iid)]], {
            curr <- shared_state$custom_report_items
            idx  <- which(vapply(curr, `[[`, character(1), "id") == iid)
            if (length(idx) == 1 && idx < length(curr)) {
              curr[c(idx, idx + 1)] <- curr[c(idx + 1, idx)]
              shared_state$custom_report_items <- curr
            }
          }, ignoreInit = TRUE)
        })
      }

      registered_item_ids(c(registered_item_ids(), new_ids))
    })

    # ── Custom Report: preview panel ──────────────────────────────────────────

    output$custom_preview_panel <- shiny::renderUI({
      items <- shared_state$custom_report_items
      n     <- length(items)

      if (n == 0) {
        return(shiny::tagList(
          shiny::tags$p(
            class = "text-muted",
            shiny::icon("circle-info"), " Your custom report is empty.",
            shiny::tags$br(),
            "Go to the ", shiny::tags$strong("Explore"), " tab, run a plot, then click ",
            shiny::tags$strong("Add to Custom Report"), "."
          )
        ))
      }

      shiny::tagList(
        shiny::tags$p(
          class = "text-muted small mb-3",
          shiny::icon("layer-group"),
          paste0(" ", n, " item", if (n != 1) "s" else "", " queued for export.")
        ),
        # Thumbnail grid preview
        shiny::div(
          class = "d-flex flex-wrap gap-3",
          lapply(seq_along(items), function(i) {
            item <- items[[i]]
            shiny::div(
              class = "text-center",
              style = "width:140px;",
              shiny::tags$img(
                src   = .thumb_src(item$thumb_path),
                width = "140px", height = "105px",
                style = "object-fit:cover; border-radius:6px; border:1px solid #dee2e6;"
              ),
              shiny::tags$div(
                class = "small text-muted mt-1",
                style = "word-break:break-word;",
                paste0(i, ". ", item$title)
              )
            )
          })
        ),
        shiny::tags$hr(),
        shiny::tags$p(
          class = "text-muted small",
          shiny::icon("circle-info"), " ",
          "Select output format and click ",
          shiny::tags$strong("Generate & Download"), " in the sidebar.",
          shiny::tags$br(),
          "Plots are re-rendered using the current working dataset."
        )
      )
    })

    # ── Custom Report: download handler ───────────────────────────────────────

    output$custom_download_btn <- shiny::downloadHandler(
      filename = function() {
        ext <- switch(input$custom_output_format,
                      pptx = ".pptx", docx = ".docx", html = ".html")
        paste0("edark_custom_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
      },
      content = function(file) {
        items <- shiny::isolate(shared_state$custom_report_items)

        if (length(items) == 0) {
          shiny::showNotification(
            "Custom report is empty. Add plots from the Explore tab first.",
            type = "warning", duration = 6
          )
          stop("No items in custom report.")
        }

        tryCatch({
          shiny::withProgress(
            message = paste0("Generating custom report (", length(items), " items)\u2026"),
            value   = 0,
            {
              generate_custom_report(
                items        = items,
                dataset      = shared_state$dataset_working,
                column_types = shared_state$column_types,
                format       = input$custom_output_format,
                output_path  = file,
                progress_fn  = function(frac, detail) {
                  shiny::setProgress(value = frac, detail = detail)
                }
              )
            }
          )
        }, error = function(e) {
          shiny::showNotification(
            paste("Custom report generation failed:", conditionMessage(e)),
            type     = "error",
            duration = 10
          )
          stop(e)
        })
      }
    )
  })
}


# Null-coalescing helper (avoids taking a dependency on rlang)
`%||%` <- function(x, y) if (is.null(x)) y else x
