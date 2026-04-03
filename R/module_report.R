#' Report Module
#'
#' UI and server for the Report stage. Lets the user configure and download a
#' report from the current working dataset. Supports two report types:
#' \itemize{
#'   \item \strong{Describe Variables} — one section per variable, univariate plots
#'     and summary stats.
#'   \item \strong{Correlation} — one bivariate section per secondary variable,
#'     with an optional global stratification variable.
#' }
#' Output formats: PowerPoint (\code{.pptx}), Word (\code{.docx}),
#' or HTML (\code{.html}).
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object (shared across modules).
#'
#' @name module_report
NULL


#' @rdname module_report
#' @export
report_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 320,

      # ── Report type ──────────────────────────────────────────────────────
      bslib::card(
        bslib::card_header(shiny::icon("file-alt"), " Report Type"),
        bslib::card_body(
          shinyWidgets::radioGroupButtons(
            ns("report_type"),
            label    = NULL,
            choices  = c("Describe Variables" = "all_vars",
                         "Correlation"        = "primary_vs_others"),
            selected = "all_vars",
            size     = "sm",
            width    = "100%"
          )
        )
      ),

      shiny::br(),

      # ── Primary variable (Correlation only) ──────────────────────────────
      shiny::conditionalPanel(
        condition = paste0("input['", ns("report_type"), "'] == 'primary_vs_others'"),
        bslib::card(
          bslib::card_header(shiny::icon("crosshairs"), " Primary Variable"),
          bslib::card_body(
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
          )
        ),
        shiny::br()
      ),

      # ── Stratify By (all modes) ───────────────────────────────────────────
      bslib::card(
        bslib::card_header(shiny::icon("layer-group"), " Stratify By"),
        bslib::card_body(
          shiny::uiOutput(ns("stratify_picker"))
        )
      ),

      shiny::br(),

      # ── Variable selection ───────────────────────────────────────────────
      bslib::card(
        bslib::card_header(shiny::icon("list-check"), " Variables"),
        bslib::card_body(
          shiny::uiOutput(ns("var_selection_summary")),
          shiny::actionButton(
            ns("open_var_modal"),
            label = "Select Variables\u2026",
            icon  = shiny::icon("sliders"),
            class = "btn-outline-secondary w-100 mt-1"
          )
        )
      ),

      shiny::br(),

      # ── Output format ────────────────────────────────────────────────────
      bslib::card(
        bslib::card_header(shiny::icon("download"), " Output Format"),
        bslib::card_body(
          shinyWidgets::radioGroupButtons(
            ns("output_format"),
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

      # ── Generate ─────────────────────────────────────────────────────────
      shiny::downloadButton(
        ns("download_btn"),
        label = "Generate & Download",
        class = "btn-primary w-100"
      )
    ),

    # ── Main panel ───────────────────────────────────────────────────────────
    bslib::card(
      full_screen = FALSE,
      bslib::card_header(shiny::icon("file-export"), " Report Preview"),
      bslib::card_body(
        shiny::uiOutput(ns("report_summary_panel"))
      )
    )
  )
}


#' @rdname module_report
#' @export
report_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

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

    # ── Dynamic pickers ─────────────────────────────────────────────────────

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

    # ── Variable selection summary ──────────────────────────────────────────

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

    # ── Variable selection modal ────────────────────────────────────────────

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

    # ── Main panel: report summary ──────────────────────────────────────────

    output$report_summary_panel <- shiny::renderUI({
      ds   <- shared_state$dataset_working
      elig <- eligible_vars()
      sel  <- selected_vars()
      if (is.null(sel)) sel <- elig

      type_label <- switch(input$report_type,
        all_vars         = "Describe Variables",
        primary_vs_others = "Correlation",
        "—"
      )
      format_label <- switch(input$output_format %||% "pptx",
        pptx = "PowerPoint (.pptx)",
        docx = "Word (.docx)",
        html = "HTML (.html)",
        "—"
      )

      n_rows <- if (!is.null(ds)) nrow(ds) else "—"
      n_cols <- if (!is.null(ds)) ncol(ds) else "—"

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
        pv   <- input$primary_variable %||% "—"
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

    # ── Download handler ────────────────────────────────────────────────────

    output$download_btn <- shiny::downloadHandler(
      filename = function() {
        ext <- switch(input$output_format,
                      pptx = ".pptx", docx = ".docx", html = ".html")
        paste0("edark_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
      },
      content = function(file) {
        vars <- selected_vars()
        if (is.null(vars) || length(vars) == 0) vars <- eligible_vars()

        # Determine total section count for progress labelling
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
  })
}


# Null-coalescing helper (avoids taking a dependency on rlang)
`%||%` <- function(x, y) if (is.null(x)) y else x
