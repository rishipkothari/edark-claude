#' Analysis Step 3 — Variable Investigation Module
#'
#' UI and server for Step 3 of the Analysis workflow: univariable outcome
#' regression screen, collinearity assessment, stepwise selection, and LASSO.
#' Full implementation per PRD §5.3 Step 3, §6.5, §7.6–7.8, §8.5, §9.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_varinvestigation
NULL


# ── Shared helper: Tier 1 validation banner ───────────────────────────────────
# Returns tagList with red alert if Tier 1 errors; NULL if clean.
.tier1_banner_ui <- function(spec, data) {
  if (is.null(spec) || is.null(data)) {
    return(shiny::div(
      class = "alert alert-warning mb-2",
      shiny::icon("triangle-exclamation"),
      " Complete Step 1 (dataset freeze and role assignment) before running analysis."
    ))
  }
  val <- validate_analysis(spec, data, tier = "tier1")
  if (val$validity_flag != "invalid") return(NULL)
  errors <- Filter(function(m) m$level == "error", val$display_messages)
  shiny::div(
    class = "alert alert-danger mb-2",
    shiny::tags$ul(
      class = "mb-0 ps-3",
      lapply(errors, function(m) shiny::tags$li(m$message))
    )
  )
}


# ── Shared helper: blocking modal ─────────────────────────────────────────────
.analysis_progress_modal <- function(title_text, detail_text = "Running\u2026") {
  shiny::modalDialog(
    title = shiny::tagList(
      shiny::tags$span(
        class = "spinner-border spinner-border-sm me-2",
        role  = "status",
        shiny::tags$span(class = "visually-hidden", "Loading...")
      ),
      title_text
    ),
    shiny::div(
      class = "progress mb-2",
      style = "height: 6px;",
      shiny::div(
        id              = "edark_analysis_progress_bar",
        class           = "progress-bar progress-bar-striped progress-bar-animated",
        role            = "progressbar",
        style           = "width: 5%;",
        `aria-valuenow` = "5",
        `aria-valuemin` = "0",
        `aria-valuemax` = "100"
      )
    ),
    shiny::tags$p(
      id    = "edark_analysis_progress_detail",
      class = "text-muted mb-0 small",
      detail_text
    ),
    footer    = NULL,
    easyClose = FALSE
  )
}


#' @rdname module_analysis_varinvestigation
#' @export
analysis_varinvestigation_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::navset_pill(
    id = ns("vi_pills"),

    # ── Pill 1: Univariable Screen ──────────────────────────────────────────
    bslib::nav_panel(
      value = "univariable",
      title = "Univariable Screen",

      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          position = "left",
          width    = 360,
          shiny::tags$p("P-value Threshold",
            class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
          shiny::numericInput(
            ns("univ_threshold"), label = NULL,
            value = 0.2, min = 0.01, max = 1, step = 0.05, width = "120px"
          ),
          shiny::tags$p(
            class = "text-muted small mb-2",
            "Variables below this threshold are flagged as candidates."
          ),
          shiny::tags$hr(class = "my-2"),
          shinyjs::disabled(
            shiny::actionButton(
              ns("btn_run_univariable"),
              label = shiny::tagList(shiny::icon("play"), " Run Screen"),
              class = "btn-primary w-100"
            )
          ),
          shiny::uiOutput(ns("univ_summary"))
        ),

        shiny::tagList(
          shiny::uiOutput(ns("univ_banner")),
          shiny::uiOutput(ns("univ_results_ui"))
        )
      )
    ),

    # ── Pill 2: Collinearity ────────────────────────────────────────────────
    bslib::nav_panel(
      value = "collinearity",
      title = "Collinearity",

      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          position = "left",
          width    = 360,
          shiny::tags$p("Threshold",
            class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
          shiny::tags$p(class = "small", "Pairs above 0.7 are flagged."),
          shiny::uiOutput(ns("collin_summary"))
        ),

        shiny::tagList(
          shiny::uiOutput(ns("collin_banner")),
          shiny::uiOutput(ns("collin_results_ui"))
        )
      )
    ),

    # ── Pill 3: Stepwise / LASSO ────────────────────────────────────────────
    bslib::nav_panel(
      value = "stepwise_lasso",
      title = "Stepwise / LASSO",

      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          position = "left",
          width    = 390,
          shiny::tags$p("Method",
            class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
          shinyWidgets::radioGroupButtons(
            ns("sl_method"),
            label    = NULL,
            choices  = c("Stepwise", "LASSO"),
            selected = "Stepwise",
            size     = "sm",
            width    = "100%"
          ),

          shiny::uiOutput(ns("sl_config_ui")),

          shiny::tags$hr(class = "my-2"),
          shinyjs::disabled(
            shiny::actionButton(
              ns("btn_run_sl"),
              label = shiny::tagList(shiny::icon("play"), " Run"),
              class = "btn-primary w-100"
            )
          ),
          shiny::uiOutput(ns("sl_summary"))
        ),

        shiny::tagList(
          shiny::uiOutput(ns("sl_banner")),
          shiny::uiOutput(ns("sl_results_ui"))
        )
      )
    )
  )
}


#' @rdname module_analysis_varinvestigation
#' @export
analysis_varinvestigation_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Tier 1 validity (reactive, shared across pills) ───────────────────────
    tier1_valid <- shiny::reactive({
      spec  <- shared_state$analysis_spec
      adata <- shared_state$analysis_data
      if (is.null(spec) || is.null(adata)) return(FALSE)
      val <- validate_analysis(spec, adata, tier = "tier1")
      val$validity_flag != "invalid"
    })

    # Enable / disable run buttons based on Tier 1
    shiny::observe({
      ok <- tier1_valid()
      shinyjs::toggleState("btn_run_univariable", condition = ok)
      shinyjs::toggleState("btn_run_sl",          condition = ok)
    })

    # ── Collinearity: auto-compute on pill entry ──────────────────────────────
    collin_computed <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$vi_pills, {
      if (!identical(input$vi_pills, "collinearity")) return()
      spec  <- shiny::isolate(shared_state$analysis_spec)
      adata <- shiny::isolate(shared_state$analysis_data)
      if (is.null(spec) || is.null(adata)) return()

      candidates <- spec$variable_roles$univariable_test_pool
      if (is.null(candidates) || length(candidates) == 0L) return()

      result <- compute_collinearity(adata, candidates)
      collin_computed(result)

      # Store in analysis_result
      res <- shiny::isolate(shared_state$analysis_result)
      if (is.null(res)) res <- list()
      if (is.null(res$result_plots)) res$result_plots <- list()
      if (is.null(res$result_plots$collinearity_plots)) {
        res$result_plots$collinearity_plots <- list()
      }
      res$result_plots$collinearity_plots$flagged_pairs_table <- result$flagged_pairs
      shared_state$analysis_result <- res
    }, ignoreInit = TRUE)

    # ── UNIVARIABLE SCREEN ────────────────────────────────────────────────────

    output$univ_banner <- shiny::renderUI({
      .tier1_banner_ui(shared_state$analysis_spec, shared_state$analysis_data)
    })

    shiny::observeEvent(input$btn_run_univariable, {
      spec  <- shiny::isolate(shared_state$analysis_spec)
      adata <- shiny::isolate(shared_state$analysis_data)
      if (is.null(spec) || is.null(adata)) return()

      # Update threshold in spec
      thr <- input$univ_threshold
      if (!is.null(thr) && !is.na(thr)) {
        spec$variable_selection_specification$univariable_p_threshold <- thr
      }

      shiny::showModal(.analysis_progress_modal("Running Univariable Screen\u2026"))
      on.exit(shiny::removeModal(), add = TRUE)

      screen_result <- run_univariable_screen(adata, spec)

      # Store results
      res <- shiny::isolate(shared_state$analysis_result)
      if (is.null(res)) res <- list()
      if (is.null(res$variable_investigation)) res$variable_investigation <- list()
      if (is.null(res$result_tables)) res$result_tables <- list()

      res$variable_investigation$univariable     <- screen_result
      res$result_tables$univariable_screen        <- screen_result
      shared_state$analysis_result <- res

      # Persist threshold
      cur_spec <- shiny::isolate(shared_state$analysis_spec)
      if (!is.null(cur_spec) && !is.null(thr)) {
        cur_spec$variable_selection_specification$univariable_p_threshold <- thr
        shared_state$analysis_spec <- cur_spec
      }
    }, ignoreInit = TRUE)

    output$univ_summary <- shiny::renderUI({
      res <- shared_state$analysis_result
      tbl <- res$variable_investigation$univariable
      if (is.null(tbl)) return(NULL)

      thr       <- input$univ_threshold
      if (is.null(thr) || is.na(thr)) thr <- 0.2
      n_total   <- nrow(tbl)
      n_suggest <- sum(tbl$suggested, na.rm = TRUE)

      shiny::tagList(
        shiny::tags$hr(class = "my-2"),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", "Variables tested"),
          shiny::tags$span(class = "small fw-semibold",
                           length(unique(tbl$variable)))
        ),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small",
                           sprintf("Suggested (p < %.2f)", thr)),
          shiny::tags$span(class = "small fw-semibold text-success", n_suggest)
        )
      )
    })

    output$univ_results_ui <- shiny::renderUI({
      res <- shared_state$analysis_result
      tbl <- res$variable_investigation$univariable
      if (is.null(tbl)) {
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::icon("magnifying-glass-chart", style = "font-size:2rem; opacity:0.3;"),
          shiny::tags$p(class = "mt-2", "Click \u201cRun Screen\u201d to run univariable regressions.")
        ))
      }
      DT::dataTableOutput(ns("univ_dt"))
    })

    output$univ_dt <- DT::renderDataTable({
      res <- shared_state$analysis_result
      tbl <- res$variable_investigation$univariable
      shiny::req(!is.null(tbl))

      thr <- input$univ_threshold
      if (is.null(thr) || is.na(thr)) thr <- 0.2

      display <- tbl %>%
        dplyr::mutate(
          estimate  = round(.data$estimate, 3L),
          conf.low  = if ("conf.low"  %in% names(.)) round(.data$conf.low,  3L) else NA,
          conf.high = if ("conf.high" %in% names(.)) round(.data$conf.high, 3L) else NA,
          p.value   = signif(.data$p.value, 3L)
        ) %>%
        dplyr::select(
          Variable  = variable,
          Term      = term,
          Reference = dplyr::any_of("reference_level"),
          Estimate  = estimate,
          `CI Low`  = dplyr::any_of("conf.low"),
          `CI High` = dplyr::any_of("conf.high"),
          `P-value` = p.value
        )

      DT::datatable(
        display,
        rownames  = FALSE,
        selection = "none",
        options   = list(
          pageLength = 20,
          dom        = "t"
        )
      ) %>%
        DT::formatStyle(
          "P-value",
          target          = "row",
          backgroundColor = DT::styleInterval(
            thr,
            c("#d4edda", "transparent")
          )
        )
    })

    # ── COLLINEARITY ──────────────────────────────────────────────────────────

    output$collin_banner <- shiny::renderUI({
      .tier1_banner_ui(shared_state$analysis_spec, shared_state$analysis_data)
    })

    output$collin_summary <- shiny::renderUI({
      coll <- collin_computed()
      if (is.null(coll)) return(NULL)

      n_flagged <- nrow(coll$flagged_pairs)

      shiny::tagList(
        shiny::tags$hr(class = "my-2"),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", "Numeric vars"),
          shiny::tags$span(class = "small fw-semibold", length(coll$num_vars))
        ),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", "Factor vars"),
          shiny::tags$span(class = "small fw-semibold", length(coll$fac_vars))
        ),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", "Flagged pairs (> 0.7)"),
          shiny::tags$span(
            class = if (n_flagged > 0) "small fw-semibold text-warning" else "small fw-semibold",
            n_flagged
          )
        )
      )
    })

    output$collin_results_ui <- shiny::renderUI({
      coll <- collin_computed()
      spec  <- shared_state$analysis_spec
      adata <- shared_state$analysis_data

      if (is.null(spec) || is.null(adata)) {
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::tags$p("Assign candidates in Step 1 first.")
        ))
      }

      if (is.null(coll)) {
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::tags$span(
            class = "spinner-border spinner-border-sm me-2", role = "status"
          ),
          " Computing collinearity\u2026"
        ))
      }

      tabs <- list()

      if (!is.null(coll$cor_matrix) && ncol(coll$cor_matrix) >= 2L) {
        tabs[[length(tabs) + 1L]] <- bslib::nav_panel(
          "Correlation (Numeric)", shiny::plotOutput(ns("collin_heatmap"))
        )
      }
      if (!is.null(coll$cramers_v_mat) && ncol(coll$cramers_v_mat) >= 2L) {
        tabs[[length(tabs) + 1L]] <- bslib::nav_panel(
          "Cram\u00e9r's V (Factor)", shiny::plotOutput(ns("collin_cramers"))
        )
      }
      tabs[[length(tabs) + 1L]] <- bslib::nav_panel(
        "Flagged Pairs", reactable::reactableOutput(ns("collin_flagged"))
      )

      if (length(tabs) == 1L) {
        # Only flagged pairs (no matrices to show)
        tabs[[1L]]$children
      } else {
        do.call(bslib::navset_card_tab, tabs)
      }
    })

    # Correlation heatmap
    output$collin_heatmap <- shiny::renderPlot({
      coll <- collin_computed()
      shiny::req(!is.null(coll), !is.null(coll$cor_matrix))

      mat        <- coll$cor_matrix
      n_vars     <- nrow(mat)
      label_size <- max(2, min(5, 10 - 0.6 * n_vars))
      base_size  <- max(9, min(16, round(18 - 0.6 * n_vars)))
      df  <- as.data.frame(as.table(mat))
      names(df) <- c("Var1", "Var2", "r")
      df$r <- as.numeric(df$r)

      ggplot2::ggplot(df, ggplot2::aes(x = .data$Var1, y = .data$Var2, fill = .data$r)) +
        ggplot2::geom_tile(color = "white") +
        ggplot2::geom_text(ggplot2::aes(label = round(.data$r, 2L)),
                           size = label_size, color = "black") +
        ggplot2::scale_fill_gradient2(
          low     = "#2166ac",
          mid     = "white",
          high    = "#d6604d",
          midpoint = 0,
          limits  = c(-1, 1),
          name    = "r"
        ) +
        ggplot2::theme_minimal(base_size = base_size) +
        ggplot2::theme(
          axis.text.x  = ggplot2::element_text(angle = 45, hjust = 1),
          panel.grid   = ggplot2::element_blank()
        ) +
        ggplot2::labs(x = NULL, y = NULL,
                      title = "Pearson Correlation Matrix (Numeric Candidates)")
    })

    # Cramér's V heatmap
    output$collin_cramers <- shiny::renderPlot({
      coll <- collin_computed()
      shiny::req(!is.null(coll), !is.null(coll$cramers_v_mat))

      mat        <- coll$cramers_v_mat
      n_vars     <- nrow(mat)
      label_size <- max(2, min(5, 10 - 0.6 * n_vars))
      base_size  <- max(9, min(16, round(18 - 0.6 * n_vars)))
      df  <- as.data.frame(as.table(mat))
      names(df) <- c("Var1", "Var2", "V")
      df$V <- as.numeric(df$V)

      ggplot2::ggplot(df, ggplot2::aes(x = .data$Var1, y = .data$Var2, fill = .data$V)) +
        ggplot2::geom_tile(color = "white") +
        ggplot2::geom_text(ggplot2::aes(label = ifelse(is.na(.data$V), "",
                                                        round(.data$V, 2L))),
                           size = label_size, color = "black") +
        ggplot2::scale_fill_gradient(
          low  = "white",
          high = "#d6604d",
          limits = c(0, 1),
          na.value = "grey90",
          name = "V"
        ) +
        ggplot2::theme_minimal(base_size = base_size) +
        ggplot2::theme(
          axis.text.x  = ggplot2::element_text(angle = 45, hjust = 1),
          panel.grid   = ggplot2::element_blank()
        ) +
        ggplot2::labs(x = NULL, y = NULL,
                      title = "Cram\u00e9r's V Matrix (Factor Candidates)")
    })

    # Flagged pairs table
    output$collin_flagged <- reactable::renderReactable({
      coll <- collin_computed()
      shiny::req(!is.null(coll))

      fp <- coll$flagged_pairs
      if (nrow(fp) == 0L) fp <- data.frame(
        var1 = "No pairs exceed threshold",
        var2 = "",
        type = "",
        value = NA_real_,
        stringsAsFactors = FALSE
      )

      reactable::reactable(
        fp,
        columns = list(
          var1  = reactable::colDef(name = "Variable 1"),
          var2  = reactable::colDef(name = "Variable 2"),
          type  = reactable::colDef(name = "Metric"),
          value = reactable::colDef(
            name   = "Value",
            format = reactable::colFormat(digits = 3L)
          )
        ),
        pagination = FALSE,
        highlight  = TRUE,
        compact    = TRUE
      )
    })

    # ── STEPWISE / LASSO ─────────────────────────────────────────────────────

    output$sl_banner <- shiny::renderUI({
      .tier1_banner_ui(shared_state$analysis_spec, shared_state$analysis_data)
    })

    output$sl_config_ui <- shiny::renderUI({
      method <- input$sl_method
      if (is.null(method)) method <- "Stepwise"

      if (method == "Stepwise") {
        shiny::tagList(
          shiny::tags$p("Direction",
            class = "text-muted small text-uppercase fw-semibold mt-3 mb-1"),
          shiny::selectInput(
            ns("sw_direction"), label = NULL,
            choices  = c("Backward" = "backward", "Forward" = "forward"),
            selected = "backward"
          ),
          shiny::tags$p("Criterion",
            class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
          shiny::selectInput(
            ns("sw_criterion"), label = NULL,
            choices  = c("BIC", "AIC"),
            selected = "BIC"
          )
        )
      } else {
        shiny::tagList(
          shiny::tags$p("Lambda Selection",
            class = "text-muted small text-uppercase fw-semibold mt-3 mb-1"),
          shiny::selectInput(
            ns("lasso_lambda"), label = NULL,
            choices  = c(
              "lambda.1se (more regularized)" = "lambda.1se",
              "lambda.min (least error)"      = "lambda.min"
            ),
            selected = "lambda.1se"
          )
        )
      }
    })

    shiny::observeEvent(input$sw_direction, {
      new_criterion <- if (isTRUE(input$sw_direction == "forward")) "AIC" else "BIC"
      shiny::updateSelectInput(session, "sw_criterion", selected = new_criterion)
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    shiny::observeEvent(input$btn_run_sl, {
      spec   <- shiny::isolate(shared_state$analysis_spec)
      adata  <- shiny::isolate(shared_state$analysis_data)
      method <- input$sl_method
      if (is.null(spec) || is.null(adata) || is.null(method)) return()

      # Update spec with current parameters
      if (method == "Stepwise") {
        spec$variable_selection_specification$stepwise_direction <- input$sw_direction
        spec$variable_selection_specification$stepwise_criterion <- input$sw_criterion
        modal_title <- sprintf("Running Stepwise (%s, %s)\u2026",
                               input$sw_direction, input$sw_criterion)
      } else {
        spec$variable_selection_specification$lasso_lambda <- input$lasso_lambda
        modal_title <- sprintf("Running LASSO (%s)\u2026", input$lasso_lambda)
      }

      shiny::showModal(.analysis_progress_modal(modal_title))
      on.exit(shiny::removeModal(), add = TRUE)

      sl_result <- if (method == "Stepwise") {
        run_stepwise(adata, spec)
      } else {
        run_lasso(adata, spec)
      }

      # Store in analysis_result — each method gets its own slot
      res <- shiny::isolate(shared_state$analysis_result)
      if (is.null(res)) res <- list()
      if (is.null(res$variable_investigation)) res$variable_investigation <- list()

      if (method == "Stepwise") {
        res$variable_investigation$stepwise <- sl_result
      } else {
        res$variable_investigation$lasso <- sl_result
      }
      shared_state$analysis_result <- res

      # Persist updated spec parameters
      cur_spec <- shiny::isolate(shared_state$analysis_spec)
      if (!is.null(cur_spec)) {
        cur_spec$variable_selection_specification <- spec$variable_selection_specification
        shared_state$analysis_spec <- cur_spec
      }
    }, ignoreInit = TRUE)

    output$sl_summary <- shiny::renderUI({
      method <- input$sl_method
      if (is.null(method)) return(NULL)
      res <- shared_state$analysis_result

      result <- if (method == "Stepwise") {
        res$variable_investigation$stepwise
      } else {
        res$variable_investigation$lasso
      }
      if (is.null(result)) return(NULL)

      n_sel <- length(result$selected_variables)
      shiny::tagList(
        shiny::tags$hr(class = "my-2"),
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", "Variables suggested"),
          shiny::tags$span(class = "small fw-semibold text-success", n_sel)
        )
      )
    })

    output$sl_results_ui <- shiny::renderUI({
      method <- input$sl_method
      if (is.null(method)) method <- "Stepwise"
      res <- shared_state$analysis_result

      result <- if (method == "Stepwise") {
        res$variable_investigation$stepwise
      } else {
        res$variable_investigation$lasso
      }

      if (is.null(result)) {
        label <- if (method == "Stepwise") "Stepwise" else "LASSO"
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::icon("list-check", style = "font-size:2rem; opacity:0.3;"),
          shiny::tags$p(class = "mt-2",
                        paste0("Click \u201cRun\u201d to run ", label, " selection."))
        ))
      }

      sel_vars <- result$selected_variables
      err      <- result$error

      shiny::tagList(
        if (!is.null(err)) {
          shiny::div(class = "alert alert-danger mb-3",
                     shiny::icon("circle-xmark"), " ", err)
        },
        bslib::card(
          bslib::card_header("Suggested Variables"),
          bslib::card_body(
            if (length(sel_vars) == 0L) {
              shiny::tags$p(class = "text-muted", "No variables selected.")
            } else {
              shiny::tags$ul(
                class = "mb-0",
                lapply(sel_vars, function(v) shiny::tags$li(v))
              )
            }
          )
        ),
        if (method == "LASSO" && !is.null(result$coef_data) &&
            nrow(result$coef_data) > 0L) {
          bslib::card(
            class = "mt-2",
            bslib::card_header("Non-zero Coefficients"),
            bslib::card_body(
              reactable::reactable(
                result$coef_data %>%
                  dplyr::mutate(estimate = round(.data$estimate, 4L)) %>%
                  dplyr::select(Term = term, Estimate = estimate),
                compact    = TRUE,
                pagination = FALSE,
                highlight  = TRUE
              )
            )
          )
        },
        if (method == "Stepwise" && !is.null(result$step_trace)) {
          crit_label <- if (isTRUE(result$criterion == "BIC")) "BIC" else "AIC"
          direction_label <- paste0(
            toupper(substring(result$direction, 1L, 1L)),
            substring(result$direction, 2L)
          )
          trace_df <- result$step_trace
          if ("AIC" %in% names(trace_df))
            names(trace_df)[names(trace_df) == "AIC"] <- crit_label
          num_cols <- intersect(c(crit_label, "Df", "Sum of Sq", "RSS",
                                  "Deviance", "Resid. Df", "Resid. Dev"), names(trace_df))
          trace_df[num_cols] <- lapply(trace_df[num_cols], function(x) round(x, 2L))

          bslib::card(
            class = "mt-2",
            bslib::card_header("Selection Steps"),
            bslib::card_body(
              shiny::tags$p(
                class = "text-muted small mb-2",
                paste0(
                  direction_label, " stepwise selection (", crit_label, "). ",
                  "Each row shows a variable added or removed and the resulting ",
                  crit_label, " score. Lower ", crit_label,
                  " is better; a step is accepted when it reduces the score."
                )
              ),
              reactable::reactable(
                trace_df,
                compact    = TRUE,
                pagination = FALSE,
                highlight  = TRUE
              )
            )
          )
        }
      )
    })

  })
}
