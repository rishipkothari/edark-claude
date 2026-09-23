#' Analysis Step 5 — Model › Performance Module
#'
#' UI and server for the Performance sub-tab of Step 5 (Model): how well the
#' model predicts. Sidebar: the measures to compute (all ticked), the
#' validation chosen in Step 1 with its settings (folds / repeats, bootstrap
#' resamples, seed), and Run Performance. Main panel: an Overview tab
#' comparing every value across the sets of rows, then one tab per set.
#'
#' Sets of rows: \strong{Apparent} (the rows the model was fitted to —
#' always, and optimistic), plus one validated set for a prediction model,
#' from the Step 1 validation method: \strong{Test set} (held-out rows),
#' \strong{Cross-validated} or \strong{Bootstrap-corrected}. Association
#' models get the apparent set only.
#'
#' Resampling runs a few refits per reactive tick (\code{invalidateLater}) so
#' the progress modal's Cancel button is heard between ticks. Mixed models
#' ask first when more than \code{.PERF_MIXED_FIT_WARN} refits are needed.
#' Settings are written live to \code{analysis_spec$validation_settings}.
#'
#' Advisory, like diagnostics: nothing here blocks Results or Export.
#' Stored in \code{analysis_result$performance},
#' \code{result_plots$performance_plots} (per set) and
#' \code{result_tables$performance_summary}; a new fit or any model-affecting
#' change clears them. Computation lives in
#' \code{service_analysis_performance.R}.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_performance
NULL


.PM_PLOT_KEYS <- c("roc_curve", "calibration_plot", "calibration_curve", "predicted_probs")
.PM_SETS      <- c("apparent", "test", "cv", "bootstrap")
# Seconds of work per reactive tick while resampling: long enough to keep
# overhead low, short enough that Cancel responds promptly.
.PM_TICK_SECS <- 0.4

# Reading guide shown next to a value in the Overview
.PM_HINTS <- c(
  auc           = "0.5 = chance, 1 = perfect",
  brier         = "lower is better",
  brier_null    = "score from predicting the event rate for everyone",
  cal_slope     = "1 = ideal; below 1 = predictions too extreme, a sign of overfitting",
  cal_intercept = "0 = ideal; average over- or under-prediction"
)


#' @rdname module_analysis_performance
#' @export
analysis_performance_ui <- function(id) {
  ns <- shiny::NS(id)

  edark_page(
    config = shiny::tagList(
      edark_section_label("Measures", first = TRUE),
      shiny::uiOutput(ns("checks_ui")),
      edark_section_label("Validation"),
      shiny::uiOutput(ns("validation_ui")),
      shiny::tags$hr(class = "my-2"),
      edark_run_button(ns, "btn_run", "Run Performance"),
      shiny::tags$p(class = "small text-muted mt-2 mb-0",
                    "Performance is advisory - it never blocks the next steps.")
    ),
    result = shiny::uiOutput(ns("results_ui")),
    info   = shiny::uiOutput(ns("header_ui"))
  )
}


#' @rdname module_analysis_performance
#' @export
analysis_performance_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # Model type of the fitted model (not the live spec). A reactiveVal so the
    # checkbox list is only rebuilt when it really changes.
    model_type <- shiny::reactiveVal(NULL)
    shiny::observe({
      res <- shared_state$analysis_result
      mt  <- if (!is.null(res$fitted_models$primary_model)) {
        res$specification_snapshot$model_design$model_type
      }
      model_type(mt)
    })
    is_mixed <- shiny::reactive(isTRUE(model_type() %in% c("linear_mixed", "logistic_mixed")))

    # The validation method from Step 1 (live spec: switching between
    # bootstrap and cross-validation does not change the model, so it needs no
    # refit; adding or removing a held-out set does, and Step 1 resets).
    method <- shiny::reactiveVal("none")
    shiny::observe({
      spec <- shared_state$analysis_spec
      m <- if (is.null(spec)) "none" else analysis_validation(spec)$method
      method(m)
    })

    # The split the fitted model was built with (not the live spec)
    fitted_split <- shiny::reactive({
      res <- shared_state$analysis_result
      if (is.null(res$fitted_models$primary_model)) return(NULL)
      analysis_split_rows(res$specification_snapshot, shared_state$analysis_data)
    })

    # Settings as the spec holds them, with defaults filled
    .current_validation <- function() {
      spec <- shiny::isolate(shared_state$analysis_spec)
      analysis_validation(spec, mixed = shiny::isolate(is_mixed()))
    }

    output$checks_ui <- shiny::renderUI({
      o <- analysis_performance_options(model_type())
      if (is.null(o)) {
        return(shiny::tags$p(class = "small text-muted", edark_lock_reason("fit_model")))
      }
      shiny::checkboxGroupInput(
        ns("checks"), label = NULL, width = "100%",
        choiceNames = lapply(seq_len(nrow(o)), function(i) {
          shiny::span(o$label[i], shiny::tags$br(),
                      shiny::span(class = "small text-muted", o$description[i]))
        }),
        choiceValues = o$id, selected = o$id)
    })
    shiny::outputOptions(output, "checks_ui", suspendWhenHidden = FALSE)

    # ── Sidebar: validation method and its settings ─────────────────────────
    output$validation_ui <- shiny::renderUI({
      if (is.null(model_type())) return(NULL)
      m  <- method()
      sr <- fitted_split()
      vl <- .current_validation()
      .item <- function(icon, cls, title, detail) {
        shiny::div(class = "d-flex gap-2 small mb-2",
                   shiny::span(class = cls, shiny::icon(icon)),
                   shiny::div(shiny::div(class = "fw-semibold", title),
                              shiny::div(class = "text-muted", detail)))
      }
      .num <- function(id, label, value, min, max) {
        shiny::numericInput(ns(id), label, value = value, min = min, max = max, step = 1, width = "100%")
      }
      apparent <- .item("circle-check", "text-success", "Apparent (model rows)",
                        "The rows the model was fitted to. Always optimistic.")

      method_block <- switch(m,
        none = .item("circle-minus", "text-muted", "No validation",
                     "Association model. To validate predictions, choose Prediction as the model purpose in Step 1."),
        split = if (!is.null(sr)) {
          .item("circle-check", "text-success", "Held-out test set",
                sprintf("%s = %s (%d rows), kept out of Steps 3\u20135.",
                        sr$variable, paste(sr$test_levels, collapse = ", "), sum(sr$test)))
        } else {
          .item("triangle-exclamation", "text-warning", "Held-out test set",
                "Not set up for this model. Choose the variable and training level in Step 1, then refit.")
        },
        cv = shiny::tagList(
          .item("circle-check", "text-success", "Cross-validation",
                paste("Each fold's model is refitted to the other folds with the same covariates and",
                      "predicts the rows left out.",
                      if (is_mixed()) "Folds hold whole clusters." else "")),
          shiny::div(class = "d-flex gap-2",
                     .num("cv_folds", "Folds", vl$cv_folds, 2, 20),
                     .num("cv_repeats", "Repeats", vl$cv_repeats, 1, 50))
        ),
        bootstrap = shiny::tagList(
          .item("circle-check", "text-success", "Bootstrap optimism correction",
                paste("The model is refitted in each resample with the same covariates.",
                      if (is_mixed()) "Resamples draw whole clusters." else "")),
          .num("bootstrap_reps", "Resamples", vl$bootstrap_reps, 10, 2000),
          if (is_mixed()) {
            shiny::tags$p(class = "small text-muted mt-n2",
                          sprintf("Mixed models refit slowly; above %d you will be asked to confirm.",
                                  .PERF_MIXED_FIT_WARN))
          }
        )
      )
      shiny::tagList(
        apparent,
        method_block,
        if (m %in% c("cv", "bootstrap")) .num("seed", "Random seed", vl$seed, 1, .Machine$integer.max)
      )
    })
    shiny::outputOptions(output, "validation_ui", suspendWhenHidden = FALSE)

    # Settings are written live. Inputs of the other method keep stale values
    # once removed, so only the current method's inputs are read, and a value
    # equal to the effective setting (default included) writes nothing.
    shiny::observeEvent(
      list(input$cv_folds, input$cv_repeats, input$bootstrap_reps, input$seed), {
      spec <- shiny::isolate(shared_state$analysis_spec)
      if (is.null(spec)) return()
      m  <- method()
      vl <- analysis_validation(spec, mixed = is_mixed())
      vs <- spec$validation_settings %||% .default_validation_settings()
      .val <- function(x) {
        x <- suppressWarnings(as.integer(x))
        if (length(x) == 1L && !is.na(x)) x
      }
      .set <- function(vs, field, x) {
        x <- .val(x)
        if (!is.null(x) && !identical(x, vl[[field]])) vs[[field]] <- x
        vs
      }
      if (m == "cv") {
        vs <- .set(vs, "cv_folds", input$cv_folds)
        vs <- .set(vs, "cv_repeats", input$cv_repeats)
      }
      if (m == "bootstrap") vs <- .set(vs, "bootstrap_reps", input$bootstrap_reps)
      if (m %in% c("cv", "bootstrap")) vs <- .set(vs, "seed", input$seed)
      if (!identical(vs, spec$validation_settings)) {
        spec$validation_settings <- vs
        shared_state$analysis_spec <- spec
      }
    }, ignoreInit = TRUE)

    # A fitted model, and at least one measure ticked.
    perf_block <- shiny::reactive({
      if (is.null(model_type())) return("fit_model")
      if (length(input$checks) == 0L) return("pick_measure")
      NULL
    })
    edark_run_gate(output, "btn_run",
                   enabled = shiny::reactive(is.null(perf_block())),
                   reason  = shiny::reactive(edark_lock_reason(perf_block())))

    # ── Run ──────────────────────────────────────────────────────────────────
    # The job runs in ticks; `runner` holds it between ticks (not reactive).
    runner  <- new.env(parent = emptyenv())
    runner$job <- NULL
    runner$cancel <- FALSE
    running <- shiny::reactiveVal(FALSE)
    pending <- shiny::reactiveVal(NULL)

    .progress <- function(frac, detail) {
      session$sendCustomMessage("edark_analysis_progress", list(frac = frac, detail = detail))
    }

    .start <- function(checks, vl) {
      res   <- shiny::isolate(shared_state$analysis_result)
      adata <- shiny::isolate(shared_state$analysis_data)
      if (is.null(res$fitted_models$primary_model)) return()
      shiny::showModal(.analysis_progress_modal(
        "Evaluating Performance\u2026",
        cancel_id = if (vl$method %in% c("cv", "bootstrap")) ns("cancel_run")))
      job <- tryCatch(analysis_performance_job(res, adata, checks, vl), error = function(e) e)
      if (inherits(job, "error")) {
        shiny::removeModal()
        shiny::showNotification(paste("Performance failed:", conditionMessage(job)),
                                type = "error", duration = 8)
        return()
      }
      runner$job       <- job
      runner$cancel    <- FALSE
      runner$fitted_at <- res$run_status$fitted_at
      .progress(.perf_job_progress(job), .perf_job_detail(job))
      running(TRUE)
    }

    shiny::observeEvent(input$btn_run, {
      if (!is.null(shiny::isolate(perf_block()))) return()   # the button is disabled
      checks <- input$checks
      vl <- .current_validation()
      n_fits <- switch(vl$method, cv = vl$cv_folds * vl$cv_repeats, bootstrap = vl$bootstrap_reps, 0L)
      if (is_mixed() && n_fits > .PERF_MIXED_FIT_WARN) {
        pending(list(checks = checks, vl = vl))
        shiny::showModal(shiny::modalDialog(
          title = "Many Mixed-Model Refits",
          shiny::p(sprintf(paste(
            "%s will refit the mixed model %d times. Each refit can take a second or more,",
            "so this may take several minutes. %d is usually enough for mixed models."),
            if (vl$method == "cv") "Cross-validation" else "The bootstrap",
            n_fits, .PERF_MIXED_FIT_WARN)),
          shiny::tags$small(class = "text-muted", "You can cancel while it runs; nothing is lost."),
          footer = shiny::tagList(
            edark_button(ns, "heavy_cancel", "Back", variant = "secondary", size = "dialog"),
            edark_button(ns, "heavy_confirm", "Proceed", variant = "warning", size = "dialog")
          ),
          easyClose = FALSE
        ))
        return()
      }
      .start(checks, vl)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$heavy_cancel, {
      shiny::removeModal()
      pending(NULL)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$heavy_confirm, {
      shiny::removeModal()
      p <- pending()
      pending(NULL)
      if (!is.null(p)) .start(p$checks, p$vl)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$cancel_run, { runner$cancel <- TRUE }, ignoreInit = TRUE)

    # One tick: run refits for up to .PM_TICK_SECS, then yield so Shiny can
    # handle the Cancel click and repaint the progress bar.
    shiny::observe({
      if (!running()) return()
      shiny::invalidateLater(10)
      shiny::isolate({
        if (isTRUE(runner$cancel)) {
          running(FALSE)
          runner$job <- NULL
          shiny::removeModal()
          shiny::showNotification("Performance cancelled - previous results kept.",
                                  type = "warning", duration = 5)
          return()
        }
        job <- runner$job
        t0  <- Sys.time()
        repeat {
          if (job$done || as.numeric(difftime(Sys.time(), t0, units = "secs")) > .PM_TICK_SECS) break
          job <- .perf_job_step(job)
        }
        runner$job <- job
        .progress(.perf_job_progress(job), .perf_job_detail(job))
        if (!job$done) return()

        running(FALSE)
        runner$job <- NULL
        pf <- tryCatch(.perf_job_finish(job), error = function(e) e)
        shiny::removeModal()
        .store(pf)
      })
    })

    .store <- function(pf) {
      if (inherits(pf, "error")) {
        shiny::showNotification(paste("Performance failed:", conditionMessage(pf)),
                                type = "error", duration = 8)
        return()
      }
      res <- shiny::isolate(shared_state$analysis_result)
      # The model may have been refitted or cleared meanwhile
      if (is.null(res$fitted_models$primary_model) ||
          !identical(res$run_status$fitted_at, runner$fitted_at)) return()
      res$performance <- pf[setdiff(names(pf), "plots")]
      if (is.null(res$result_plots)) res$result_plots <- list()
      res$result_plots["performance_plots"] <- list(pf$plots)
      if (is.null(res$result_tables)) res$result_tables <- list()
      res$result_tables["performance_summary"] <- list(pf$metrics)
      shared_state$analysis_result <- res

      n_warn <- sum(pf$messages$level == "warning")
      shiny::showNotification(
        sprintf("Performance evaluated%s.",
                if (n_warn > 0L) sprintf(" - %d warning%s", n_warn, if (n_warn == 1L) "" else "s") else ""),
        type = "message", duration = 4)
    }

    perf  <- shiny::reactive(shared_state$analysis_result$performance)
    plots <- shiny::reactive(shared_state$analysis_result$result_plots$performance_plots)

    # ── Main: header ─────────────────────────────────────────────────────────
    output$header_ui <- shiny::renderUI({
      mt  <- model_type()
      if (is.null(mt)) return(.ms_placeholder(edark_lock_reason("fit_model")))
      purpose <- shared_state$analysis_spec$purpose_specification$model_purpose %||% "association"
      pf <- perf()
      edark_model_header(
        title  = .ANALYSIS_MODEL_LABELS[[mt]],
        fields = list(
          `Model purpose` = if (identical(purpose, "prediction")) "Prediction" else "Association",
          Validation      = .PERF_METHOD_LABELS[[method()]]
        ),
        notes  = c(
          if (!identical(purpose, "prediction"))
            paste("An association model is judged by its estimates, not its predictions.",
                  "Apparent discrimination and calibration are shown as a description of fit;",
                  "they are not evidence about the exposure effect, and are not validated."),
          if (!is.null(pf))
            sprintf("Evaluated %s - %s", format(pf$run_at, "%H:%M:%S"),
                    .pm_validation_text(pf$validation))
        )
      )
    })

    # ── Main: results ────────────────────────────────────────────────────────
    output$results_ui <- shiny::renderUI({
      pf <- perf()
      if (is.null(model_type())) return(NULL)
      if (is.null(pf)) {
        return(.ms_placeholder("Choose the measures in the sidebar and click Run Performance."))
      }
      tabs <- list(bslib::nav_panel("Overview", .pm_overview(pf)))
      for (s in names(pf$sets)) {
        tabs <- c(tabs, list(bslib::nav_panel(pf$sets[[s]]$label, .pm_set_tab(pf, s, ns, plots()[[s]]))))
      }
      do.call(bslib::navset_card_tab, c(list(id = ns("perf_tabs")), tabs))
    })

    # Plots: one output per set and key; each renders only when that plot exists
    for (set in .PM_SETS) {
      for (key in .PM_PLOT_KEYS) {
        local({
          s <- set; k <- key
          output[[paste0("plot_", s, "_", k)]] <- shiny::renderPlot({
            p <- plots()[[s]][[k]]
            shiny::req(!is.null(p))
            p
          }, res = 96)
        })
      }
    }
  })
}


# ── Rendering helpers ─────────────────────────────────────────────────────────

.pm_validation_text <- function(vl) {
  if (is.null(vl)) return("")
  switch(vl$method,
    cv        = sprintf("%d-fold cross-validation \u00d7 %d repeat%s, seed %d",
                        vl$cv_folds, vl$cv_repeats, if (vl$cv_repeats == 1L) "" else "s", vl$seed),
    bootstrap = sprintf("bootstrap optimism correction, %d resamples, seed %d", vl$bootstrap_reps, vl$seed),
    split     = "held-out test set",
    "apparent performance only")
}

# Settings alone, for notes that already name the method
.pm_settings_text <- function(vl) {
  switch(vl$method,
    cv        = sprintf("%d folds \u00d7 %d repeat%s, seed %d",
                        vl$cv_folds, vl$cv_repeats, if (vl$cv_repeats == 1L) "" else "s", vl$seed),
    bootstrap = sprintf("%d resamples, seed %d", vl$bootstrap_reps, vl$seed),
    "")
}

# Estimates for display; float noise (e.g. an in-sample intercept of 1e-14) shows as 0
.pm_est <- function(x) {
  if (is.null(x) || !is.finite(x)) return("-")
  edark_format_est(if (abs(x) < 1e-10) 0 else x)
}

.pm_basis_note <- function(pf) {
  if (identical(pf$basis, "marginal")) {
    "Predictions use the fixed effects only (cluster effects set to zero), as for a patient from a new cluster."
  }
}

.pm_set_note <- function(set, pf) {
  switch(set,
    apparent = paste(
      "Apparent (in-sample) performance: measured on the rows the model was fitted to, so it is",
      "optimistic. A prediction model needs validation on rows it has not seen before it is reported."),
    test = paste(
      "Test set performance: measured on held-out rows the model never saw during variable",
      "investigation, covariate selection or fitting. The calibration slope and intercept are",
      "meaningful here (in-sample they are 1 and 0 by construction)."),
    cv = paste0(
      "Cross-validated performance (", .pm_settings_text(pf$validation), "): each fold's model was ",
      "refitted to the other folds with the same covariates and predicted the rows left out. Values ",
      "are computed on the pooled out-of-fold predictions and averaged over repeats (SD across repeats). ",
      "This estimates how a model built this way performs on new patients from the same population; ",
      "the coefficients reported are those of the model fitted to all rows."),
    bootstrap = paste0(
      "Bootstrap optimism correction (", .pm_settings_text(pf$validation), "): the model was refitted ",
      "in each resample with the same covariates, and the average drop in performance from the resample ",
      "to the original rows (the optimism) is subtracted from the apparent value. The corrected ",
      "calibration slope is also a shrinkage factor: well below 1 (e.g. < 0.9) means the coefficients ",
      "are overfitted. The coefficients reported are those of the model fitted to all rows."))
}


.pm_fmt_cell <- function(m, s, k) {
  r <- m[m$set == s & m$key == k, , drop = FALSE]
  if (nrow(r) == 0L) return("-")
  if (k == "auc") {
    lo <- m$value[m$set == s & m$key == "auc_low"]
    hi <- m$value[m$set == s & m$key == "auc_high"]
    if (length(lo) && length(hi)) return(edark_format_ci(r$value, lo, hi))
  }
  out <- .ms_fmt_stat(r$value, r$format)
  if ("sd" %in% names(r) && is.finite(r$sd)) out <- sprintf("%s (SD %s)", out, .ms_fmt_stat(r$sd, "number"))
  out
}


.pm_overview <- function(pf) {
  m    <- pf$metrics
  msgs <- pf$messages
  sets <- names(pf$sets)

  table <- if (is.null(m)) {
    shiny::tags$p(class = "small text-muted mb-0", "No values computed.")
  } else {
    # CI bounds are shown with the AUC, not as rows of their own
    keys <- setdiff(unique(m$key), c("auc_low", "auc_high"))
    shiny::tags$table(
      class = "table table-sm small mb-0",
      shiny::tags$thead(shiny::tags$tr(
        shiny::tags$th("Measure"),
        lapply(sets, function(s) shiny::tags$th(class = "text-end", pf$sets[[s]]$label))
      )),
      shiny::tags$tbody(lapply(keys, function(k) {
        label <- m$label[m$key == k][1L]
        hint  <- .PM_HINTS[k]
        shiny::tags$tr(
          shiny::tags$td(class = "text-muted", label,
                         if (!is.na(hint)) shiny::span(class = "fst-italic", paste0(" (", hint, ")"))),
          lapply(sets, function(s) shiny::tags$td(class = "text-end fw-semibold text-nowrap", .pm_fmt_cell(m, s, k)))
        )
      }))
    )
  }
  validated <- intersect(c("test", "cv", "bootstrap"), sets)

  shiny::div(
    class = "pt-2",
    bslib::card(
      class = "mb-3",
      bslib::card_header("Messages"),
      bslib::card_body(
        class = "py-2",
        if (is.null(msgs) || nrow(msgs) == 0L) {
          shiny::tags$p(class = "small text-muted mb-0", "None.")
        } else {
          lapply(seq_len(nrow(msgs)), function(i) .ms_check_item(msgs$level[i], msgs$message[i]))
        }
      )
    ),
    bslib::card(
      class = "mb-3",
      bslib::card_header("Performance by set of rows"),
      bslib::card_body(
        class = "py-2",
        table,
        shiny::tags$p(class = "small text-muted mt-2 mb-0",
                      .pm_set_note("apparent", pf), " ",
                      if (length(validated)) "The validated column is the one to report. ",
                      .pm_basis_note(pf))
      )
    )
  )
}


.pm_set_tab <- function(pf, set, ns, pl) {
  v <- pf$sets[[set]]
  .stat <- function(label, key) {
    value <- v[[key]]
    if (is.null(value)) return(NULL)
    sd <- v$sd[[key]]
    shiny::div(class = "me-4",
               shiny::div(class = "small text-muted", label),
               shiny::div(class = "fw-semibold", .pm_est(value),
                          if (!is.null(sd)) shiny::span(class = "text-muted fw-normal small",
                                                        sprintf(" SD %s", .pm_est(sd)))))
  }
  keys <- intersect(.PM_PLOT_KEYS, names(pl))
  shiny::tagList(
    shiny::div(class = "border rounded bg-body-tertiary small text-muted p-2 mb-2",
               shiny::icon("circle-info"), " ", .pm_set_note(set, pf), " ", .pm_basis_note(pf)),
    shiny::div(
      class = "d-flex flex-wrap mb-3",
      shiny::div(class = "me-4",
                 shiny::div(class = "small text-muted", "Rows"),
                 shiny::div(class = "fw-semibold", format(v$n, big.mark = ","),
                            if (!is.null(v$n_events)) sprintf(" (%d events)", v$n_events))),
      if (!is.null(v$n_fits)) {
        shiny::div(class = "me-4",
                   shiny::div(class = "small text-muted", "Model refits"),
                   shiny::div(class = "fw-semibold", v$n_fits,
                              if (isTRUE(v$n_failed > 0L)) {
                                shiny::span(class = "text-warning small", sprintf(" (%d skipped)", v$n_failed))
                              }))
      },
      if (!is.null(v$auc)) {
        shiny::div(class = "me-4",
                   shiny::div(class = "small text-muted", if (is.null(v$auc_low)) "AUC" else "AUC (95% CI)"),
                   shiny::div(class = "fw-semibold",
                              if (is.null(v$auc_low)) edark_format_est(v$auc) else edark_format_ci(v$auc, v$auc_low, v$auc_high),
                              if (!is.null(v$sd$auc)) shiny::span(class = "text-muted fw-normal small",
                                                                  sprintf(" SD %s", edark_format_est(v$sd$auc)))))
      },
      .stat("Brier score", "brier"),
      .stat("No-information Brier", "brier_null"),
      .stat("Calibration intercept", "cal_intercept"),
      .stat("Calibration slope", "cal_slope"),
      .stat("RMSE", "rmse"),
      .stat("MAE", "mae"),
      .stat("R\u00b2", "r2")
    ),
    if (!is.null(v$optimism) && nrow(v$optimism) > 0L) .pm_optimism_table(v$optimism),
    if (length(keys) > 0L) {
      do.call(bslib::layout_columns, c(
        list(col_widths = if (length(keys) == 1L) 12 else c(6, 6)),
        lapply(keys, function(k) shiny::plotOutput(ns(paste0("plot_", set, "_", k)), height = "400px"))
      ))
    }
  )
}


# Apparent | optimism | corrected, one row per measure
.pm_optimism_table <- function(op) {
  shiny::div(
    class = "mb-3",
    shiny::tags$table(
      class = "table table-sm small mb-1", style = "max-width: 640px;",
      shiny::tags$thead(shiny::tags$tr(
        shiny::tags$th("Measure"),
        shiny::tags$th(class = "text-end", "Apparent"),
        shiny::tags$th(class = "text-end", "Optimism"),
        shiny::tags$th(class = "text-end", "Corrected")
      )),
      shiny::tags$tbody(lapply(seq_len(nrow(op)), function(i) {
        shiny::tags$tr(
          shiny::tags$td(class = "text-muted", op$label[i]),
          shiny::tags$td(class = "text-end", .pm_est(op$apparent[i])),
          shiny::tags$td(class = "text-end", .pm_est(op$optimism[i])),
          shiny::tags$td(class = "text-end fw-semibold", .pm_est(op$corrected[i]))
        )
      }))
    ),
    shiny::tags$p(class = "small text-muted mb-0",
                  "Optimism = mean over resamples of (performance on the resample \u2212 performance on the original rows).",
                  "Corrected = apparent \u2212 optimism.")
  )
}
