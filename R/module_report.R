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

  shiny::tagList(
    # JS handler — updates the detail text inside the blocking progress modal
    shiny::tags$script(shiny::HTML(
      "Shiny.addCustomMessageHandler('edark_report_progress', function(msg) {",
      "  var bar = document.getElementById('edark_progress_bar');",
      "  if (bar) {",
      "    bar.style.width = (msg.frac * 100) + '%';",
      "    bar.setAttribute('aria-valuenow', Math.round(msg.frac * 100));",
      "  }",
      "  var txt = document.getElementById('edark_progress_detail');",
      "  if (txt) txt.textContent = msg.detail;",
      "});"
    )),

  bslib::navset_underline(
    id = ns("report_mode_tabs"),

    # ── Full Report pill ──────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "full_report",
      title = shiny::tagList(shiny::icon("file-lines"), " Full Report"),

      edark_page(
        # Config: settings first, then output format, then the one primary
        # action last - in every mode of every page (F3). Generate used to sit
        # at the *top* here and at the bottom in Custom (§1.3k).
        config = shiny::tagList(
          edark_section_label("Report Type", first = TRUE),
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
            edark_section_label("Primary Variable"),
            shiny::uiOutput(ns("primary_var_picker")),
            shinyWidgets::radioGroupButtons(
              ns("primary_role"),
              label    = "Role:",
              choices  = c("Exposure (X)" = "exposure",
                           "Outcome (Y)"  = "outcome"),
              selected = "exposure",
              size     = "sm",
              width    = "100%"
            )
          ),

          edark_section_label("Variables"),
          shiny::uiOutput(ns("var_selection_summary")),
          edark_button(ns, "open_var_modal", "Select Variables\u2026",
                       icon = "sliders", variant = "secondary", outline = TRUE,
                       class = "mt-1"),

          edark_section_label("Options"),
          shiny::uiOutput(ns("stratify_picker")),

          edark_section_label("Report Contents"),
          shiny::checkboxInput(ns("include_dataset_summary"),
                               "Dataset Summary", value = TRUE),
          shiny::conditionalPanel(
            condition = paste0("input['", ns("report_type"), "'] == 'all_vars'"),
            shiny::checkboxInput(ns("include_tableone"),
                                 "Table One", value = FALSE)
          ),

          edark_section_label("Output Format"),
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

          shiny::div(
            class = "mt-3",
            edark_button(ns, "download_btn", "Generate & Download",
                         icon = "download", type = "download")
          )
        ),

        # Result: the sections the current settings resolve to, in order. Not a
        # restatement of the controls (F5) - which variables survive depends on
        # eligibility, the primary variable and the stratify variable.
        result   = shiny::uiOutput(ns("report_sections_panel")),
        messages = edark_messages_ui(ns, "full_messages"),
        info     = shiny::uiOutput(ns("full_info"))
      )
    ),

    # ── Custom Report pill ────────────────────────────────────────────────────
    bslib::nav_panel(
      value = "custom_report",
      title = shiny::tagList(shiny::icon("layer-group"), " Custom Report"),

      # D11: no centre. The item list *is* the page's main presentation, and it
      # lives in the config pane because reordering and deleting are
      # configuration. The old main-panel "Preview" card showed the same list
      # again and nothing else (F5), so it is gone.
      edark_page(
        config = shiny::tagList(
          edark_section_label("Report Items", first = TRUE),
          shiny::uiOutput(ns("custom_items_gallery")),

          edark_section_label("Output Format"),
          shinyWidgets::radioGroupButtons(
            ns("custom_output_format"),
            label    = NULL,
            choices  = c("PowerPoint" = "pptx",
                         "Word"       = "docx",
                         "HTML"       = "html"),
            selected = "pptx",
            size     = "sm",
            width    = "100%"
          ),

          shiny::div(
            class = "mt-3",
            edark_button(ns, "custom_download_btn", "Generate & Download",
                         icon = "download", type = "download")
          )
        ),
        result   = NULL,
        messages = edark_messages_ui(ns, "custom_messages"),
        info     = shiny::uiOutput(ns("custom_info"))
      )
    )
  )   # closes navset_underline
  )   # closes tagList
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
        # label   = "Primary variable:",
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
          edark_button(ns, "modal_select_all", "Select All",
                       variant = "secondary", size = "dialog", outline = TRUE),
          edark_button(ns, "modal_deselect_all", "Deselect All",
                       variant = "secondary", size = "dialog", outline = TRUE,
                       class = "ms-2"),
          shiny::tags$span(class = "flex-grow-1"),
          edark_button(ns, "modal_done", "Done", size = "dialog"),
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

    # -- Full report: what the current settings resolve to ---------------------
    # Which variables become sections is derived, not stated: eligibility,
    # the primary variable and the stratify variable all remove candidates.
    full_sections <- shiny::reactive({
      elig <- eligible_vars()
      sel  <- selected_vars()
      if (is.null(sel)) sel <- elig
      sv <- input$stratify_variable

      v <- intersect(sel, elig)
      if (identical(input$report_type, "primary_vs_others") &&
          !is.null(input$primary_variable)) {
        v <- setdiff(v, input$primary_variable)
      }
      if (!is.null(sv) && nzchar(sv)) v <- setdiff(v, sv)
      v
    })


    # Info pane: the scalar facts about the file that will be produced.
    output$full_info <- shiny::renderUI({
      ds   <- shared_state$dataset_working
      elig <- eligible_vars()
      secs <- full_sections()

      type_label <- switch(input$report_type,
        all_vars          = "Describe Variables",
        primary_vs_others = "Correlation",
        "-"
      )
      format_label <- switch(input$output_format %||% "pptx",
        pptx = "PowerPoint (.pptx)",
        docx = "Word (.docx)",
        html = "HTML (.html)",
        "-"
      )
      sv <- input$stratify_variable

      shiny::tagList(
        edark_section_label("Will contain", first = TRUE),
        edark_info_row("Report type",   type_label),
        edark_info_row("Output format", format_label),
        edark_info_row("Sections",      length(secs)),
        edark_info_row("Variables",
                       sprintf("%d of %d eligible", length(secs), length(elig))),
        if (identical(input$report_type, "primary_vs_others")) {
          edark_info_row(
            "Primary variable",
            paste0(input$primary_variable %||% "-", " - ",
                   if ((input$primary_role %||% "exposure") == "exposure")
                     "Exposure (X)" else "Outcome (Y)")
          )
        },
        edark_info_row("Stratify by",
                       if (is.null(sv) || !nzchar(sv)) "None" else sv),
        edark_info_row("Dataset summary",
                       if (isTRUE(input$include_dataset_summary)) "Included" else "No"),
        if (identical(input$report_type, "all_vars")) {
          edark_info_row("Table One",
                         if (isTRUE(input$include_tableone)) "Included" else "No")
        },

        edark_section_label("Source data"),
        edark_info_row("Rows",    if (!is.null(ds)) format(nrow(ds), big.mark = ",") else "-"),
        edark_info_row("Columns", if (!is.null(ds)) ncol(ds) else "-")
      )
    })


    # Result: the ordered section list itself.
    output$report_sections_panel <- shiny::renderUI({
      secs <- full_sections()

      if (length(secs) == 0) {
        return(edark_empty_state(
          "No sections to generate",
          "Pick at least one variable under Variables, in the pane on the left.",
          icon = "file-circle-question"
        ))
      }

      bslib::card(
        bslib::card_header(shiny::icon("list-ol"), " Sections in this report"),
        bslib::card_body(
          shiny::tags$ol(
            class = "mb-0",
            lapply(secs, function(v) shiny::tags$li(v))
          )
        )
      )
    })


    # Messages for the Full Report page.
    edark_messages_server(output, shiny::reactive({
      msgs <- list()
      if (length(full_sections()) == 0) {
        msgs <- c(msgs, list(edark_message(
          "warn", "This report would have no sections.",
          detail = "Select at least one variable before generating."
        )))
      }
      if (isTRUE(shared_state$explore_needs_refresh)) {
        msgs <- c(msgs, list(edark_message(
          "stale", "The working dataset has changed since the last plot was drawn.",
          detail = "The report is generated from the current working dataset."
        )))
      }
      msgs
    }), id = "full_messages")

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

        shiny::showModal(shiny::modalDialog(
          title = shiny::tagList(
            shiny::tags$span(
              class = "spinner-border spinner-border-sm me-2",
              role  = "status",
              shiny::tags$span(class = "visually-hidden", "Loading...")
            ),
            paste0("Generating Report (", n_sections, " section",
                   if (n_sections != 1) "s" else "", ")")
          ),
          shiny::div(
            class = "progress mb-2",
            style = "height: 6px;",
            shiny::div(
              id              = "edark_progress_bar",
              class           = "progress-bar progress-bar-striped progress-bar-animated",
              role            = "progressbar",
              style           = "width: 0%;",
              `aria-valuenow` = "0",
              `aria-valuemin` = "0",
              `aria-valuemax` = "100"
            )
          ),
          shiny::tags$p(
            id    = "edark_progress_detail",
            class = "text-muted mb-0 small",
            "Starting..."
          ),
          footer    = NULL,
          easyClose = FALSE
        ))
        on.exit(shiny::removeModal(), add = TRUE)

        aes_now <- edark_current_aesthetics(shared_state)

        tryCatch({
          generate_report(
            dataset                 = shared_state$dataset_working,
            column_types            = shared_state$column_types,
            report_type             = input$report_type,
            variables               = vars,
            primary_variable        = if (input$report_type == "primary_vs_others")
                                         input$primary_variable else NULL,
            primary_role            = input$primary_role %||% "exposure",
            stratify_variable       = {
              sv <- input$stratify_variable
              if (is.null(sv) || !nzchar(sv)) NULL else sv
            },
            format                  = input$output_format,
            output_path             = file,
            include_dataset_summary = isTRUE(input$include_dataset_summary),
            include_tableone        = isTRUE(input$include_tableone) &&
                                        input$report_type == "all_vars",
            # The aesthetics on screen, not a second set owned by Report, so
            # the generated document matches the plot the user has been
            # looking at (D7 / D9).
            ggplot_theme            = aes_now$ggplot_theme,
            color_palette           = aes_now$color_palette,
            show_data_labels        = aes_now$show_data_labels,
            show_legend             = aes_now$show_legend,
            legend_position         = aes_now$legend_position,
            progress_fn             = function(frac, detail) {
              session$sendCustomMessage("edark_report_progress", list(frac = frac, detail = detail))
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
                edark_button(ns, paste0("up_", item$id), NULL, icon = "angle-up",
                             variant = "secondary", size = "toolbar", class = "p-1"),
              if (i < n)
                edark_button(ns, paste0("down_", item$id), NULL, icon = "angle-down",
                             variant = "secondary", size = "toolbar", class = "p-1"),
              edark_button(ns, paste0("remove_", item$id), NULL, icon = "trash",
                           variant = "danger", size = "toolbar", class = "p-1")
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

    # -- Custom Report: info pane ---------------------------------------------
    # The page has no centre (D11), so this is the only place that describes
    # the file. The old main-panel "Preview" card re-listed the items that the
    # config pane already shows, and nothing else (F5).
    output$custom_info <- shiny::renderUI({
      items <- shared_state$custom_report_items
      n     <- length(items)

      format_label <- switch(input$custom_output_format %||% "pptx",
        pptx = "PowerPoint (.pptx)",
        docx = "Word (.docx)",
        html = "HTML (.html)",
        "-"
      )

      if (n == 0) {
        return(shiny::tagList(
          edark_section_label("Will contain", first = TRUE),
          shiny::tags$p(
            class = "small text-muted",
            "Nothing yet. Run a plot in Explore and click ",
            shiny::tags$strong("Add to Custom Report"),
            " to queue it here."
          )
        ))
      }

      kinds <- table(vapply(items, function(it) it$plot_spec$plot_type %||% "plot",
                            character(1)))

      shiny::tagList(
        edark_section_label("Will contain", first = TRUE),
        edark_info_row("Items",         n),
        edark_info_row("Output format", format_label),

        edark_section_label("Item types"),
        lapply(names(kinds), function(k) edark_info_row(k, as.integer(kinds[[k]]))),

        edark_section_label("Source data"),
        edark_info_row("Rows",    format(nrow(shared_state$dataset_working), big.mark = ",")),
        edark_info_row("Columns", ncol(shared_state$dataset_working)),
        shiny::tags$p(
          class = "small text-muted mt-2 mb-0",
          "Each item is re-drawn from the current working dataset when the
           report is generated, so the file reflects the data as it is now."
        )
      )
    })


    # Messages for the Custom Report page. There is no centre, so the page
    # contract puts these at the top of the info column.
    edark_messages_server(output, shiny::reactive({
      msgs <- list()
      if (length(shared_state$custom_report_items) == 0) {
        msgs <- c(msgs, list(edark_message(
          "info", "Your custom report is empty.",
          detail = shiny::tagList(
            "Go to ", shiny::tags$strong("Explore"), ", run a plot, then click ",
            shiny::tags$strong("Add to Custom Report"), "."
          )
        )))
      }
      if (isTRUE(shared_state$explore_needs_refresh)) {
        msgs <- c(msgs, list(edark_message(
          "stale", "The working dataset has changed since these items were added.",
          detail = "Their thumbnails still show the earlier data; the generated report will not."
        )))
      }
      msgs
    }), id = "custom_messages")

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

        n_items <- length(items)
        shiny::showModal(shiny::modalDialog(
          title = shiny::tagList(
            shiny::tags$span(
              class = "spinner-border spinner-border-sm me-2",
              role  = "status",
              shiny::tags$span(class = "visually-hidden", "Loading...")
            ),
            paste0("Generating Custom Report (", n_items, " item",
                   if (n_items != 1) "s" else "", ")")
          ),
          shiny::div(
            class = "progress mb-2",
            style = "height: 6px;",
            shiny::div(
              id              = "edark_progress_bar",
              class           = "progress-bar progress-bar-striped progress-bar-animated",
              role            = "progressbar",
              style           = "width: 0%;",
              `aria-valuenow` = "0",
              `aria-valuemin` = "0",
              `aria-valuemax` = "100"
            )
          ),
          shiny::tags$p(
            id    = "edark_progress_detail",
            class = "text-muted mb-0 small",
            "Starting..."
          ),
          footer    = NULL,
          easyClose = FALSE
        ))
        on.exit(shiny::removeModal(), add = TRUE)

        tryCatch({
          generate_custom_report(
            items            = items,
            dataset          = shared_state$dataset_working,
            column_types     = shared_state$column_types,
            format           = input$custom_output_format,
            output_path      = file,
            # No report-level aesthetics: each item carries the appearance it
            # had on screen when it was added, so the document reproduces what
            # the user saw rather than restyling every item at once (D7).
            progress_fn      = function(frac, detail) {
              session$sendCustomMessage("edark_report_progress", detail)
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
