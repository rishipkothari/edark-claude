#' Report Module
#'
#' UI and server for the Report stage. Lets the user configure and download a
#' report from the current working dataset. Supports two report types:
#' \itemize{
#'   \item \strong{All Variables} — one section per variable, univariate plots
#'     and summary stats.
#'   \item \strong{Primary vs All Others} — one bivariate section per secondary
#'     variable, with an optional global stratification variable.
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
            choices  = c("All Variables"        = "all_vars",
                         "Primary vs All Others" = "primary_vs_others"),
            selected = "all_vars",
            size     = "sm",
            width    = "100%"
          )
        )
      ),

      shiny::br(),

      # ── Primary variable (type B only) ───────────────────────────────────
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
        shiny::br(),
        bslib::card(
          bslib::card_header(shiny::icon("layer-group"), " Stratify By"),
          bslib::card_body(
            shiny::uiOutput(ns("stratify_picker"))
          )
        ),
        shiny::br()
      ),

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
      bslib::card_header(shiny::icon("file-export"), " Report"),
      bslib::card_body(
        shiny::uiOutput(ns("status_message"))
      )
    )
  )
}


#' @rdname module_report
#' @export
report_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Track which variables the user has selected (NULL = all)
    selected_vars <- shiny::reactiveVal(NULL)

    # Initialise selected_vars when the working dataset is first available
    shiny::observe({
      req(shared_state$dataset_working)
      if (is.null(selected_vars()))
        selected_vars(names(shared_state$dataset_working))
    })

    # When the dataset changes (after Apply), reset selection to new column set
    shiny::observeEvent(shared_state$dataset_working, {
      selected_vars(names(shared_state$dataset_working))
    }, ignoreInit = TRUE)

    # ── Dynamic pickers ─────────────────────────────────────────────────────

    output$primary_var_picker <- shiny::renderUI({
      shinyWidgets::pickerInput(
        ns("primary_variable"),
        label   = "Primary variable:",
        choices = names(shared_state$dataset_working),
        options = shinyWidgets::pickerOptions(liveSearch = TRUE, container = "body")
      )
    })

    output$stratify_picker <- shiny::renderUI({
      types       <- shared_state$column_types
      factor_cols <- names(types)[types == "factor"]
      primary     <- input$primary_variable
      factor_cols <- setdiff(factor_cols, primary)
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
      all_vars <- names(shared_state$dataset_working)
      sel      <- selected_vars()
      if (is.null(sel)) sel <- all_vars
      n_sel    <- length(intersect(sel, all_vars))
      n_total  <- length(all_vars)
      shiny::tags$p(
        class = "text-muted small mb-1",
        paste0(n_sel, " of ", n_total, " variables selected")
      )
    })

    # ── Variable selection modal ────────────────────────────────────────────

    shiny::observeEvent(input$open_var_modal, {
      all_vars  <- names(shared_state$dataset_working)
      currently <- selected_vars()
      if (is.null(currently)) currently <- all_vars

      shiny::showModal(shiny::modalDialog(
        title = "Select Variables for Report",
        shiny::checkboxGroupInput(
          ns("modal_vars"),
          label    = NULL,
          choices  = all_vars,
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
      all_vars <- names(shared_state$dataset_working)
      shiny::updateCheckboxGroupInput(session, "modal_vars",
                                      selected = all_vars)
    })

    shiny::observeEvent(input$modal_deselect_all, {
      shiny::updateCheckboxGroupInput(session, "modal_vars", selected = character(0))
    })

    shiny::observeEvent(input$modal_done, {
      selected_vars(input$modal_vars)
      shiny::removeModal()
    })

    # ── Status message ──────────────────────────────────────────────────────

    output$status_message <- shiny::renderUI({
      shiny::tagList(
        shiny::tags$p(
          shiny::icon("circle-info"), " ",
          "Configure your report in the sidebar, then click ",
          shiny::tags$strong("Generate & Download"),
          "."
        ),
        shiny::tags$ul(
          shiny::tags$li(shiny::tags$strong("All Variables:"),
            " One section per variable — describe plot + summary stats."),
          shiny::tags$li(shiny::tags$strong("Primary vs All Others:"),
            " One bivariate section per secondary variable.")
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
        all_vars <- names(shared_state$dataset_working)
        if (is.null(vars) || length(vars) == 0) vars <- all_vars

        shiny::showNotification(
          "Generating report\u2026 this may take a moment.",
          id       = "rpt_progress",
          duration = NULL,
          type     = "message"
        )
        on.exit(shiny::removeNotification("rpt_progress"), add = TRUE)

        tryCatch({
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
            output_path = file
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
