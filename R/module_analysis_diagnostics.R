#' Analysis Step 6 — Diagnostics Module
#'
#' UI and server for Step 6 of the Analysis workflow. Sidebar: the checks to
#' run, in two groups — \strong{Model assumptions} (all ticked by default)
#' and \strong{Prediction performance} (optional, unticked, collapsed; for
#' prediction studies only) — and the Run Diagnostics button. Main panel: an
#' Overview tab with every computed value and warning at a glance, then one
#' tab per computed check.
#'
#' Diagnostics are advisory: nothing here blocks Step 7 or 8. Results are
#' stored in \code{analysis_result$diagnostics},
#' \code{result_plots$diagnostic_plots}, \code{result_tables$diagnostic_summary}
#' and \code{inference_summary$influence_measures}; a new fit or any
#' model-affecting change clears them (\code{reset_analysis_pipeline()}).
#' Computation lives in \code{service_analysis_diagnostics.R}.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_diagnostics
NULL


.DG_PLOT_KEYS <- c("residuals_vs_fitted", "qq_plot", "scale_location", "binned_residuals",
                   "influence_plot", "leverage_plot", "random_effects_qq", "cluster_size_plot",
                   "roc_curve", "calibration_plot", "predicted_probs")

# Reading guide shown next to a value in the Overview
.DG_HINTS <- c(
  bp_p          = "< 0.05 suggests the residual spread is not constant",
  binned_inside = "expect about 95%",
  n_above       = "rows worth a look, not rows to delete",
  vif_max       = "5\u201310 moderate, > 10 high",
  auc           = "0.5 = chance, 1 = perfect",
  brier         = "lower is better",
  brier_null    = "score from predicting the event rate for everyone",
  icc_adjusted  = "share of the outcome variance between clusters"
)

.DG_SECTIONS <- c(
  sample = "Sample", fit = "Fit", residuals = "Residuals", influence = "Influence",
  vif = "Collinearity", separation = "Separation", random_effects = "Random effects",
  prediction = "Prediction performance"
)


#' @rdname module_analysis_diagnostics
#' @export
analysis_diagnostics_ui <- function(id) {
  ns <- shiny::NS(id)
  .hdr <- function(x) shiny::tags$p(x, class = "text-muted small text-uppercase fw-semibold mt-2 mb-1")
  .links <- function(all_id, none_id) {
    shiny::div(class = "small mb-1",
               shiny::actionLink(ns(all_id), "Select all"), " \u00b7 ",
               shiny::actionLink(ns(none_id), "Deselect all"))
  }

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      position = "left",
      width    = 340,
      .hdr("Model assumptions"),
      .links("assump_all", "assump_none"),
      shiny::uiOutput(ns("assump_ui")),
      bslib::accordion(
        open = FALSE, class = "mt-2",
        bslib::accordion_panel(
          "Prediction performance (optional)", value = "prediction",
          shiny::tags$p(class = "small text-muted mb-2",
                        "For studies that build a model to predict outcomes. Not needed to report",
                        "an association between an exposure and an outcome."),
          .links("pred_all", "pred_none"),
          shiny::uiOutput(ns("pred_ui"))
        )
      ),
      shiny::tags$hr(class = "my-2"),
      shiny::actionButton(ns("btn_run"),
                          label = shiny::tagList(shiny::icon("play"), " Run Diagnostics"),
                          class = "btn-primary w-100"),
      shiny::tags$p(class = "small text-muted mt-2 mb-0",
                    "Sample accounting and fitting warnings are always included.",
                    "Diagnostics are advisory \u2014 they never block the next steps.")
    ),
    shiny::uiOutput(ns("header_ui")),
    shiny::uiOutput(ns("results_ui"))
  )
}


#' @rdname module_analysis_diagnostics
#' @export
analysis_diagnostics_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # Model type of the fitted model (not the live spec). A reactiveVal so the
    # checkbox lists are only rebuilt when it really changes.
    model_type <- shiny::reactiveVal(NULL)
    shiny::observe({
      res <- shared_state$analysis_result
      mt  <- if (!is.null(res$fitted_models$primary_model)) {
        res$specification_snapshot$model_design$model_type
      }
      model_type(mt)
    })

    options_tbl <- shiny::reactive(analysis_diagnostic_options(model_type()))

    .choices <- function(o) {
      list(names  = lapply(seq_len(nrow(o)), function(i) {
             shiny::span(o$label[i],
                         shiny::tags$br(),
                         shiny::span(class = "small text-muted", o$description[i]))
           }),
           values = o$id)
    }

    output$assump_ui <- shiny::renderUI({
      o <- options_tbl()
      if (is.null(o)) return(shiny::tags$p(class = "small text-muted", "Fit a model in Step 5 first."))
      o <- o[o$category == "assumptions", , drop = FALSE]
      ch <- .choices(o)
      shiny::checkboxGroupInput(ns("assump"), label = NULL, choiceNames = ch$names,
                                choiceValues = ch$values, selected = o$id, width = "100%")
    })

    output$pred_ui <- shiny::renderUI({
      o <- options_tbl()
      if (is.null(o)) return(NULL)
      o <- o[o$category == "prediction", , drop = FALSE]
      ch <- .choices(o)
      shiny::checkboxGroupInput(ns("pred"), label = NULL, choiceNames = ch$names,
                                choiceValues = ch$values, selected = character(0), width = "100%")
    })

    # Render even while hidden (the prediction list sits in a collapsed
    # accordion) so a new model type always resets both lists — otherwise the
    # hidden input would keep ticks from the previous model.
    shiny::outputOptions(output, "assump_ui", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "pred_ui",   suspendWhenHidden = FALSE)

    .set_group <- function(input_id, category, all) {
      o <- options_tbl()
      if (is.null(o)) return()
      ids <- o$id[o$category == category]
      shiny::updateCheckboxGroupInput(session, input_id, selected = if (all) ids else character(0))
    }
    shiny::observeEvent(input$assump_all,  .set_group("assump", "assumptions", TRUE))
    shiny::observeEvent(input$assump_none, .set_group("assump", "assumptions", FALSE))
    shiny::observeEvent(input$pred_all,    .set_group("pred", "prediction", TRUE))
    shiny::observeEvent(input$pred_none,   .set_group("pred", "prediction", FALSE))

    shiny::observe({
      shinyjs::toggleState("btn_run", condition = !is.null(model_type()))
    })

    # ── Run ──────────────────────────────────────────────────────────────────
    shiny::observeEvent(input$btn_run, {
      res   <- shiny::isolate(shared_state$analysis_result)
      adata <- shiny::isolate(shared_state$analysis_data)
      if (is.null(res$fitted_models$primary_model)) return()
      # Inputs keep stale values across model types; the service drops ids
      # that do not apply to this model.
      checks <- c(input$assump, input$pred)

      shiny::showModal(.analysis_progress_modal("Running Diagnostics\u2026"))
      on.exit(shiny::removeModal(), add = TRUE)
      progress <- function(frac, detail) {
        session$sendCustomMessage("edark_analysis_progress", list(frac = frac, detail = detail))
      }

      dg <- tryCatch(run_analysis_diagnostics(res, adata, checks, progress_fn = progress),
                     error = function(e) e)
      if (inherits(dg, "error")) {
        shiny::showNotification(paste("Diagnostics failed:", conditionMessage(dg)),
                                type = "error", duration = 8)
        return()
      }

      res <- shiny::isolate(shared_state$analysis_result)
      res$diagnostics <- dg[setdiff(names(dg), c("plots", "influence_measures"))]
      if (is.null(res$result_plots)) res$result_plots <- list()
      res$result_plots$diagnostic_plots <- dg$plots
      if (is.null(res$result_tables)) res$result_tables <- list()
      res$result_tables["diagnostic_summary"] <- list(dg$metrics)
      if (is.null(res$inference_summary)) res$inference_summary <- list()
      res$inference_summary["influence_measures"] <- list(dg$influence_measures)
      shared_state$analysis_result <- res

      n_warn <- sum(dg$messages$level == "warning")
      shiny::showNotification(
        sprintf("Diagnostics complete%s.",
                if (n_warn > 0L) sprintf(" \u2014 %d warning%s", n_warn, if (n_warn == 1L) "" else "s") else ""),
        type = "message", duration = 4)
    }, ignoreInit = TRUE)

    diag <- shiny::reactive(shared_state$analysis_result$diagnostics)
    diag_plots <- shiny::reactive(shared_state$analysis_result$result_plots$diagnostic_plots)

    # ── Main: header ─────────────────────────────────────────────────────────
    output$header_ui <- shiny::renderUI({
      res <- shared_state$analysis_result
      mt  <- model_type()
      if (is.null(mt)) return(.ms_placeholder("Fit a model in Step 5 to run diagnostics."))
      rs  <- res$run_status
      dg  <- diag()
      bslib::card(
        bslib::card_body(
          class = "py-2",
          shiny::div(class = "fw-semibold", .ANALYSIS_MODEL_LABELS[[mt]]),
          shiny::div(class = "small mt-1",
                     shiny::span(class = "text-muted", "Formula: "),
                     shiny::tags$code(paste(deparse(rs$formula, width.cutoff = 500L), collapse = " "))),
          if (!is.null(dg)) {
            shiny::div(class = "small text-muted mt-1",
                       sprintf("Diagnostics run %s", format(dg$run_at, "%H:%M:%S")))
          }
        )
      )
    })

    # ── Main: results ────────────────────────────────────────────────────────
    output$results_ui <- shiny::renderUI({
      dg <- diag()
      if (is.null(model_type())) return(NULL)
      if (is.null(dg)) {
        return(.ms_placeholder("Choose the checks in the sidebar and click Run Diagnostics."))
      }
      pl <- diag_plots()

      tabs <- list(bslib::nav_panel("Overview", .dg_overview(dg)))
      if (!is.null(dg$residuals)) {
        tabs <- c(tabs, list(bslib::nav_panel("Residuals", .dg_residuals_tab(dg, ns))))
      }
      if (!is.null(dg$influence)) {
        tabs <- c(tabs, list(bslib::nav_panel("Influence", .dg_influence_tab(dg, ns))))
      }
      if (!is.null(dg$vif)) {
        tabs <- c(tabs, list(bslib::nav_panel("Collinearity", .dg_vif_tab(dg, ns))))
      }
      if (!is.null(dg$random_effects)) {
        tabs <- c(tabs, list(bslib::nav_panel("Random effects", .dg_ranef_tab(dg, ns))))
      }
      if (!is.null(dg$prediction)) {
        tabs <- c(tabs, list(bslib::nav_panel("Prediction", .dg_prediction_tab(dg, ns, pl))))
      }
      do.call(bslib::navset_card_tab, c(list(id = ns("diag_tabs")), tabs))
    })

    # Plots: one output per known key; each renders only when that plot exists
    lapply(.DG_PLOT_KEYS, function(key) {
      output[[paste0("plot_", key)]] <- shiny::renderPlot({
        p <- diag_plots()[[key]]
        shiny::req(!is.null(p))
        p
      }, res = 96)
    })

    output$influence_table <- reactable::renderReactable({
      top <- diag()$influence$top
      shiny::req(!is.null(top))
      cols <- list(
        .edark_row_id = reactable::colDef(name = "Row ID", minWidth = 70),
        cooks     = reactable::colDef(name = "Cook's D", format = reactable::colFormat(digits = 3)),
        leverage  = reactable::colDef(name = "Leverage", format = reactable::colFormat(digits = 3)),
        std_resid = reactable::colDef(name = "Std. residual", format = reactable::colFormat(digits = 2))
      )
      reactable::reactable(top, columns = cols, compact = TRUE, pagination = FALSE,
                           highlight = TRUE, defaultColDef = reactable::colDef(minWidth = 110))
    })

    output$vif_table <- reactable::renderReactable({
      v <- diag()$vif
      shiny::req(is.data.frame(v))
      reactable::reactable(
        v, compact = TRUE, pagination = FALSE, highlight = TRUE,
        columns = list(
          term = reactable::colDef(name = "Predictor", minWidth = 200),
          vif  = reactable::colDef(name = "VIF", align = "right",
                                   format = reactable::colFormat(digits = 2)),
          flag = reactable::colDef(
            name = "", align = "left",
            cell = function(value) {
              switch(value,
                high     = shiny::span(class = "text-danger", "High"),
                moderate = shiny::span(class = "text-warning", "Moderate"),
                shiny::span(class = "text-muted", "OK"))
            })
        )
      )
    })

    output$ranef_table <- reactable::renderReactable({
      comp <- diag()$random_effects$components
      shiny::req(!is.null(comp))
      reactable::reactable(
        comp, compact = TRUE, pagination = FALSE,
        columns = list(
          group       = reactable::colDef(name = "Cluster variable", minWidth = 160),
          variance    = reactable::colDef(name = "Variance", format = reactable::colFormat(digits = 3)),
          sd          = reactable::colDef(name = "SD", format = reactable::colFormat(digits = 3)),
          icc         = reactable::colDef(name = "ICC", format = reactable::colFormat(digits = 3)),
          n_groups    = reactable::colDef(name = "Clusters"),
          min_size    = reactable::colDef(name = "Min rows"),
          median_size = reactable::colDef(name = "Median rows"),
          max_size    = reactable::colDef(name = "Max rows")
        )
      )
    })
  })
}


# ── Rendering helpers ─────────────────────────────────────────────────────────

.dg_fmt <- function(value, format) {
  if (identical(format, "yesno")) return(if (isTRUE(value == 1)) "Yes" else "No")
  .ms_fmt_stat(value, format)
}

.dg_plot <- function(ns, key, height = "380px") {
  shiny::plotOutput(ns(paste0("plot_", key)), height = height)
}

.dg_note <- function(...) shiny::tags$p(class = "small text-muted mb-2", ...)


.dg_overview <- function(dg) {
  m <- dg$metrics
  msgs <- dg$messages
  sections <- if (is.null(m)) character(0) else intersect(names(.DG_SECTIONS), unique(m$section))

  .rows <- function(sec) {
    mm <- m[m$section == sec, , drop = FALSE]
    lapply(seq_len(nrow(mm)), function(i) {
      hint <- .DG_HINTS[mm$key[i]]
      shiny::div(
        class = "d-flex justify-content-between gap-3 small mb-1",
        shiny::span(class = "text-muted", mm$label[i],
                    if (!is.na(hint)) shiny::span(class = "fst-italic", paste0(" (", hint, ")"))),
        shiny::span(class = "fw-semibold text-nowrap",
                    if (identical(mm$level[i], "warning")) .ms_level_icon("warning"),
                    " ", .dg_fmt(mm$value[i], mm$format[i]))
      )
    })
  }

  missing <- dg$sample$missing
  missing <- missing[missing$n_missing > 0L, , drop = FALSE]

  cards <- lapply(sections, function(sec) {
    bslib::card(
      class = "mb-3",
      bslib::card_header(.DG_SECTIONS[[sec]]),
      bslib::card_body(
        class = "py-2",
        .rows(sec),
        if (sec == "sample" && nrow(missing) > 0L) {
          shiny::div(
            class = "small mt-2",
            shiny::span(class = "text-muted", "Missing values by variable (a row can miss several):"),
            shiny::tags$ul(class = "mb-0 ps-3",
                           lapply(seq_len(nrow(missing)), function(i) {
                             shiny::tags$li(sprintf("%s: %d", missing$variable[i], missing$n_missing[i]))
                           }))
          )
        },
        if (sec == "prediction") {
          shiny::tags$p(class = "small text-muted mt-2 mb-0", .dg_apparent_note(dg$prediction$basis))
        }
      )
    )
  })

  warn_card <- bslib::card(
    class = "mb-3",
    bslib::card_header("Warnings"),
    bslib::card_body(
      class = "py-2",
      if (is.null(msgs) || nrow(msgs) == 0L) {
        shiny::tags$p(class = "small text-muted mb-0", "None.")
      } else {
        lapply(seq_len(nrow(msgs)), function(i) .ms_check_item(msgs$level[i], msgs$message[i]))
      }
    )
  )

  half <- ceiling(length(cards) / 2)
  shiny::div(
    class = "pt-2",
    warn_card,
    bslib::layout_columns(
      col_widths = c(6, 6),
      shiny::tagList(cards[seq_len(half)]),
      shiny::tagList(cards[setdiff(seq_along(cards), seq_len(half))])
    )
  )
}


.dg_apparent_note <- function(basis) {
  paste0(
    "Apparent (in-sample) performance: measured on the same rows the model was fitted to, ",
    "so it is optimistic. A prediction model needs internal validation (e.g. bootstrap) ",
    "or external validation before it is reported.",
    if (identical(basis, "marginal")) {
      " Predictions use the fixed effects only (cluster effects set to zero), as for a patient from a new cluster."
    } else ""
  )
}


.dg_residuals_tab <- function(dg, ns) {
  r <- dg$residuals
  if (identical(r$type, "binned")) {
    return(shiny::tagList(
      .dg_note("Raw residuals of a 0/1 outcome form two bands and cannot be read like",
               "linear-model residuals. Binned residuals group rows by predicted probability",
               "and plot the average residual in each bin (Gelman & Hill, 2007). A pattern",
               "or many bins outside their interval suggests a missing non-linear term or",
               "interaction."),
      .dg_plot(ns, "binned_residuals", "420px"),
      shiny::tags$p(class = "small mt-2 mb-0",
                    sprintf("%.0f%% of bins include zero (expect about 95%%).", 100 * r$binned_inside))
    ))
  }
  shiny::tagList(
    if (identical(r$type, "conditional")) {
      .dg_note("Conditional residuals: observed minus fitted values including each cluster's intercept.")
    },
    bslib::layout_columns(
      col_widths = c(6, 6),
      .dg_plot(ns, "residuals_vs_fitted"),
      .dg_plot(ns, "qq_plot")
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      .dg_plot(ns, "scale_location"),
      if (!is.null(r$bp)) {
        shiny::div(
          class = "small pt-4",
          shiny::tags$strong("Breusch-Pagan test"),
          shiny::tags$p(class = "mb-1",
                        sprintf("BP = %.2f, df = %d, p %s", r$bp$statistic, as.integer(r$bp$df),
                                { p <- .ms_fmt_p(r$bp$p.value); if (startsWith(p, "<")) p else paste("=", p) })),
          .dg_note("Tests whether the residual spread changes with the predictors. With large samples",
                   "it flags trivial differences, so judge it together with the scale-location plot.",
                   "Unequal spread mainly affects standard errors, not the estimates.")
        )
      }
    )
  )
}


.dg_influence_tab <- function(dg, ns) {
  inf <- dg$influence
  shiny::tagList(
    .dg_note(sprintf(paste(
      "%d of %d rows have Cook's distance above 4 / n (%.3f). Influential rows are worth checking",
      "for data-entry errors; they should not be removed just for being influential."),
      inf$n_above, dg$sample$n_used, inf$threshold)),
    bslib::layout_columns(
      col_widths = c(6, 6),
      .dg_plot(ns, "influence_plot"),
      .dg_plot(ns, "leverage_plot")
    ),
    shiny::tags$p(class = "small fw-semibold mt-3 mb-1",
                  sprintf("Most influential rows (top %d by Cook's distance)", nrow(inf$top))),
    reactable::reactableOutput(ns("influence_table"))
  )
}


.dg_vif_tab <- function(dg, ns) {
  shiny::tagList(
    .dg_note(sprintf(paste(
      "How much each estimate's variance is inflated by correlation with the other predictors.",
      "%d\u2013%d is moderate and > %d high. Factors use the generalised VIF. VIF is shown for",
      "transparency \u2014 correlated confounders often belong in the model together."),
      .DIAG_VIF_MODERATE, .DIAG_VIF_HIGH, .DIAG_VIF_HIGH)),
    reactable::reactableOutput(ns("vif_table"))
  )
}


.dg_ranef_tab <- function(dg, ns) {
  re <- dg$random_effects
  shiny::tagList(
    .dg_note(sprintf(paste(
      "One random intercept per cluster variable. ICC = that variable's variance / total variance",
      "(%s scale). A variance of 0 means the model found no clustering for that variable (a singular fit)."),
      re$residual_scale)),
    reactable::reactableOutput(ns("ranef_table")),
    bslib::layout_columns(
      col_widths = c(6, 6), class = "mt-3",
      .dg_plot(ns, "random_effects_qq"),
      .dg_plot(ns, "cluster_size_plot")
    )
  )
}


.dg_prediction_tab <- function(dg, ns, pl) {
  p <- dg$prediction
  .stat <- function(label, value, fmt = "%.3f") {
    if (is.null(value)) return(NULL)
    shiny::div(class = "me-4",
               shiny::div(class = "small text-muted", label),
               shiny::div(class = "fw-semibold", sprintf(fmt, value)))
  }
  plots <- intersect(c("roc_curve", "calibration_plot", "predicted_probs"), names(pl))
  shiny::tagList(
    shiny::div(class = "border rounded bg-body-tertiary small text-muted p-2 mb-2",
               shiny::icon("circle-info"), " ", .dg_apparent_note(p$basis)),
    shiny::div(
      class = "d-flex flex-wrap mb-3",
      if (!is.null(p$auc)) {
        shiny::div(class = "me-4",
                   shiny::div(class = "small text-muted", "AUC (95% CI)"),
                   shiny::div(class = "fw-semibold",
                              sprintf("%.3f (%.3f\u2013%.3f)", p$auc, p$auc_low, p$auc_high)))
      },
      .stat("Brier score", p$brier),
      .stat("No-information Brier", p$brier_null),
      .stat("RMSE", p$rmse),
      .stat("MAE", p$mae),
      .stat("R\u00b2", p$r2)
    ),
    if (length(plots) > 0L) {
      do.call(bslib::layout_columns, c(
        list(col_widths = if (length(plots) == 1L) 12 else c(6, 6)),
        lapply(plots, function(k) .dg_plot(ns, k, "400px"))
      ))
    }
  )
}
