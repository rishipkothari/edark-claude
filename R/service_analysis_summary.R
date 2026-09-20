#' Analysis Summary Service
#'
#' Builds the Step 5 "Summary" — a read-only, top-to-bottom account of how
#' the model was arrived at: data preparation, the frozen dataset, roles,
#' Table 1, variable investigation, covariates, the model, and every
#' preflight check. It reflects the current state of each step, not a history
#' of clicks. Pure (no Shiny) so the export can reuse it.
#'
#' @name service_analysis_summary
NULL


.STUDY_TYPE_LABELS <- c(
  exposure_outcome     = "Exposure-outcome association study",
  risk_factor          = "Risk factor / association study",
  descriptive_exposure = "Descriptive (exposure distribution)",
  descriptive          = "Descriptive cohort"
)


#' Build the Step 5 analysis summary
#'
#' @param spec The current \code{analysis_spec}.
#' @param result The \code{analysis_result} (may be \code{NULL}).
#' @param data The frozen analysis dataset.
#' @param validation Output of \code{validate_analysis(spec, data, verbose =
#'   TRUE)}; computed here when \code{NULL}.
#'
#' @return A list of sections, each \code{list(id, title, rows)}; each row is
#'   \code{list(label, value, items, level)} where \code{items} is an optional
#'   character vector shown as a list under the row and \code{level} is
#'   \code{NULL} or one of \code{"error"}, \code{"warning"}, \code{"note"},
#'   \code{"pass"}.
#' @export
build_analysis_summary <- function(spec, result, data, validation = NULL) {
  if (is.null(spec) || is.null(data)) return(list())
  if (is.null(validation)) validation <- validate_analysis(spec, data, verbose = TRUE)

  vr <- spec$variable_roles
  list(
    .summary_prepare(spec),
    .summary_dataset(spec, data),
    .summary_roles(spec, data),
    .summary_table1(spec, result),
    .summary_investigation(spec, result),
    .summary_covariates(spec, result, data),
    .summary_model(spec, result, data),
    .summary_checks(validation)
  )
}


# ── Row / section helpers ─────────────────────────────────────────────────────

.srow <- function(label, value = "", items = NULL, level = NULL) {
  list(label = label, value = value, items = items, level = level)
}
.ssection <- function(id, title, rows) list(id = id, title = title, rows = Filter(Negate(is.null), rows))
.none <- "None"
.plural <- function(n, word) sprintf("%d %s%s", n, word, if (n == 1L) "" else "s")
.dims <- function(d) {
  if (is.null(d)) return("\u2014")
  sprintf("%s rows \u00d7 %s columns", format(d[["rows"]], big.mark = ","), d[["cols"]])
}


# ── 1. Data preparation ───────────────────────────────────────────────────────

.summary_prepare <- function(spec) {
  snap <- spec$specification_metadata$prepare_snapshot
  if (is.null(snap)) {
    return(.ssection("prepare", "Data preparation", list(
      .srow("Not recorded", "This analysis was started before preparation steps were captured. Restart the analysis in Step 1 to record them.",
            level = "note"))))
  }

  excluded <- setdiff(snap$original_columns, snap$included_columns)

  overrides <- snap$column_type_overrides
  ov_items  <- if (length(overrides) > 0L) {
    paste0(names(overrides), " \u2192 ", vapply(overrides, as.character, character(1)))
  }

  tf <- snap$column_transform_specs
  tf_items <- unlist(lapply(names(tf), function(col) {
    d <- .describe_transform(tf[[col]])
    if (is.null(d)) NULL else paste0(col, ": ", d)
  }))

  rf <- snap$row_filter_specs
  rf_items <- unlist(lapply(names(rf), function(col) .describe_filter(col, rf[[col]])))

  .ssection("prepare", "Data preparation", list(
    .srow("Original dataset", .dims(snap$original_dims)),
    .srow("Columns excluded", if (length(excluded)) length(excluded) else .none, items = excluded),
    .srow("Type overrides", if (length(ov_items)) length(ov_items) else .none, items = ov_items),
    .srow("Transforms", if (length(tf_items)) length(tf_items) else .none, items = tf_items),
    .srow("Row filters", if (length(rf_items)) length(rf_items) else .none, items = rf_items),
    .srow("Prepared dataset", .dims(snap$working_dims))
  ))
}

.describe_transform <- function(s) {
  m <- s$method %||% ""
  switch(m,
    auto        = "auto-factor (ordered levels)",
    cutpoints   = paste0("cut-points at ", paste(s$breakpoints, collapse = ", ")),
    log         = paste0("log (", s$log_base %||% "ln", ")"),
    winsorize   = sprintf("winsorized at the %s\u2013%s percentiles",
                          s$lower_pct %||% 1, s$upper_pct %||% 99),
    round       = sprintf("rounded to %s decimal place(s)", s$decimal_places %||% 0),
    standardize = "standardized (z-score)",
    NULL
  )
}

.describe_filter <- function(col, s) {
  if (identical(s$type, "numeric")) {
    full <- isTRUE(all.equal(s$min, s$data_min)) && isTRUE(all.equal(s$max, s$data_max))
    sprintf("%s: %s to %s%s", col, format(signif(s$min, 4)), format(signif(s$max, 4)),
            if (full) " (full range; removes missing values only)" else "")
  } else {
    sel <- s$levels_selected
    sprintf("%s: keep %s (%d of %d levels)", col, paste(sel, collapse = ", "),
            length(sel), length(s$levels_all))
  }
}


# ── 2. Analysis dataset ───────────────────────────────────────────────────────

.summary_dataset <- function(spec, data) {
  md <- spec$specification_metadata
  n_cols <- length(setdiff(names(data), ".edark_row_id"))
  .ssection("dataset", "Analysis dataset", list(
    .srow("Frozen at", if (!is.null(md$created_at)) format(md$created_at, "%Y-%m-%d %H:%M") else "\u2014"),
    .srow("Size", sprintf("%s rows \u00d7 %d columns", format(nrow(data), big.mark = ","), n_cols)),
    .srow("Complete rows (all columns)", sprintf("%d (%d%%)", sum(stats::complete.cases(data)),
                                                 round(mean(stats::complete.cases(data)) * 100)))
  ))
}


# ── 3. Roles ──────────────────────────────────────────────────────────────────

.var_kind <- function(x) {
  if (is.numeric(x)) return("numeric")
  if (is.factor(x)) return(sprintf("factor, %d levels", nlevels(droplevels(x[!is.na(x)]))))
  class(x)[1L]
}

.summary_roles <- function(spec, data) {
  vr <- spec$variable_roles
  st <- spec$specification_metadata$study_type %||% "descriptive"
  ev <- analysis_outcome_event(spec, data)

  .var <- function(v) {
    if (is.null(v) || !v %in% names(data)) return("\u2014")
    sprintf("%s (%s)", v, .var_kind(data[[v]]))
  }

  cl_items <- vapply(vr$cluster_variables %||% character(0), function(cl) {
    if (!cl %in% names(data)) return(cl)
    sprintf("%s (%d clusters)", cl, length(unique(stats::na.omit(data[[cl]]))))
  }, character(1))

  ps <- spec$purpose_specification
  sr <- analysis_split_rows(spec, data)
  vl <- analysis_validation(spec, mixed = length(vr$cluster_variables) > 0L)
  split_row <- switch(vl$method,
    split = if (!is.null(sr)) {
      .srow("Validation",
            sprintf("Held-out test set \u2014 %s: training = %s (%d rows); test = %s (%d rows)%s", sr$variable,
                    sr$training_level, sum(sr$training), paste(sr$test_levels, collapse = ", "),
                    sum(sr$test),
                    if (sr$n_missing > 0L) sprintf("; %d rows in neither", sr$n_missing) else ""))
    } else {
      .srow("Validation", "Held-out test set \u2014 choose a variable and training level in Step 1", level = "warning")
    },
    cv        = .srow("Validation", sprintf("Cross-validation \u2014 %d-fold \u00d7 %d repeat%s, seed %d (set in Performance)",
                                            vl$cv_folds, vl$cv_repeats, if (vl$cv_repeats == 1L) "" else "s", vl$seed)),
    bootstrap = .srow("Validation", sprintf("Bootstrap optimism correction \u2014 %d resamples, seed %d (set in Performance)",
                                            vl$bootstrap_reps, vl$seed)),
    NULL)

  .ssection("roles", "Study design and roles", list(
    .srow("Study type", .STUDY_TYPE_LABELS[[st]] %||% st),
    .srow("Model purpose", if (identical(ps$model_purpose, "prediction")) "Prediction" else "Association"),
    split_row,
    .srow("Outcome", .var(vr$outcome_variable)),
    if (!is.null(ev)) .srow("Modelling", sprintf("%s = %s (vs %s)", ev$variable, ev$event, ev$reference)),
    .srow("Exposure", .var(vr$exposure_variable)),
    .srow("Candidate covariates", length(vr$candidate_covariates), items = vr$candidate_covariates),
    .srow("Clusters", if (length(cl_items)) length(cl_items) else .none, items = unname(cl_items))
  ))
}


# ── 4. Table 1 ────────────────────────────────────────────────────────────────

.summary_table1 <- function(spec, result) {
  rt   <- result$result_tables
  made <- c(Overall = !is.null(rt$table1_overall),
            `By exposure` = !is.null(rt$table1_by_exposure),
            `By outcome` = !is.null(rt$table1_by_outcome))
  ts <- spec$table1_specification
  .ssection("table1", "Table 1", list(
    .srow("Generated", if (any(made)) paste(names(made)[made], collapse = ", ") else "Not generated"),
    if (any(made)) .srow("Options", paste0(
      "p-values: ", if (isTRUE(ts$include_pvalues_exposure) || isTRUE(ts$include_pvalues_outcome)) "yes" else "no",
      "; standardized mean differences: ",
      if (isTRUE(ts$include_smd_exposure) || isTRUE(ts$include_smd_outcome)) "yes" else "no"))
  ))
}


# ── 5. Variable investigation ─────────────────────────────────────────────────

.excluded_items <- function(ex) {
  if (is.null(ex) || nrow(ex) == 0L) return(NULL)
  paste0("excluded: ", ex$variable, " \u2014 ", ex$reason)
}

.summary_investigation <- function(spec, result) {
  vi   <- result$variable_investigation
  vsel <- spec$variable_selection_specification

  univ <- vi$univariable
  univ_row <- if (is.null(univ)) {
    .srow("Univariable screen", "Not run")
  } else {
    sugg <- unique(univ$variable[univ$suggested])
    .srow("Univariable screen",
          sprintf("p < %s \u2014 %d of %d suggested", vsel$univariable_p_threshold %||% 0.2,
                  length(sugg), length(unique(univ$variable))),
          items = c(sugg, .excluded_items(attr(univ, "excluded_variables") %||% vi$univariable_excluded)))
  }

  .sl_row <- function(x, label, params) {
    if (is.null(x)) return(.srow(label, "Not run"))
    if (!is.null(x$error)) return(.srow(label, paste("Failed:", x$error), level = "warning"))
    held <- if (length(x$held_variables)) paste0("; exposure held (", paste(x$held_variables, collapse = ", "), ")") else ""
    .srow(label, sprintf("%s \u2014 %s selected%s", params, .plural(length(x$selected_variables), "variable"), held),
          items = c(x$selected_variables, .excluded_items(x$excluded_variables)))
  }
  sw <- vi$stepwise
  la <- vi$lasso

  fp <- result$result_plots$collinearity_plots$flagged_pairs_table
  col_row <- if (is.null(fp)) {
    .srow("Collinearity", "Not computed")
  } else {
    .srow("Collinearity", if (nrow(fp)) sprintf("%d pair(s) above 0.7", nrow(fp)) else "No pairs above 0.7",
          items = if (nrow(fp)) sprintf("%s \u2194 %s (%s %s)", fp$var1, fp$var2, fp$type, fp$value))
  }

  .ssection("investigation", "Variable investigation", list(
    univ_row,
    col_row,
    .sl_row(sw, "Stepwise", if (!is.null(sw)) sprintf("%s, %s", sw$direction, sw$criterion) else ""),
    .sl_row(la, "LASSO", if (!is.null(la)) la$lambda_type else "")
  ))
}


# ── 6. Covariates and sample ──────────────────────────────────────────────────

.summary_covariates <- function(spec, result, data) {
  data  <- analysis_model_data(spec, data)   # training rows when split
  vr    <- spec$variable_roles
  covs  <- vr$final_model_covariates %||% character(0)
  vi    <- result$variable_investigation

  sugg <- list(
    Univariable = if (!is.null(vi$univariable)) unique(vi$univariable$variable[vi$univariable$suggested]),
    Stepwise    = if (is.null(vi$stepwise$error)) vi$stepwise$selected_variables,
    LASSO       = if (is.null(vi$lasso$error)) vi$lasso$selected_variables
  )
  cov_items <- vapply(covs, function(v) {
    by <- names(sugg)[vapply(sugg, function(s) v %in% s, logical(1))]
    paste0(v, if (length(by)) paste0(" \u2014 suggested by ", paste(by, collapse = ", ")) else " \u2014 not suggested by any method")
  }, character(1))

  model_vars <- c(vr$outcome_variable, vr$exposure_variable, covs)
  refs <- vr$reference_levels
  refs <- refs[intersect(names(refs), model_vars)]
  refs <- refs[vapply(names(refs), function(v) v %in% names(data) && is.factor(data[[v]]), logical(1))]
  ref_items <- if (length(refs)) paste0(names(refs), " = ", vapply(refs, as.character, character(1)))

  si <- if (!is.null(vr$outcome_variable) && vr$outcome_variable %in% names(data)) {
    compute_covariate_sample(data, vr$outcome_variable, vr$exposure_variable, covs,
                             candidates = vr$candidate_covariates %||% character(0),
                             cluster_vars = vr$cluster_variables %||% character(0))
  }
  iss <- if (!is.null(si)) si$issues
  iss_rows <- if (!is.null(iss) && nrow(iss)) {
    lapply(seq_len(nrow(iss)), function(i) {
      lvl <- iss$level[i]
      .srow(paste0(toupper(substr(lvl, 1L, 1L)), substring(lvl, 2L)), iss$message[i], level = lvl)
    })
  }

  c_rows <- list(
    .srow("Covariates in the model",
          if (length(covs)) length(covs) else "None \u2014 unadjusted (exposure only)",
          items = unname(cov_items)),
    .srow("Reference levels", if (length(ref_items)) length(ref_items) else .none, items = ref_items),
    if (!is.null(si)) .srow("Complete-case sample",
                            sprintf("%d of %d %srows (%d excluded for missing data)",
                                    si$n_fixed, si$n_total, if (!is.null(analysis_split(spec))) "training " else "",
                                    si$n_total - si$n_fixed)),
    if (!is.null(si) && !is.na(si$n_mixed)) .srow("With cluster variables", sprintf("%d rows", si$n_mixed)),
    if (!is.null(si) && !is.na(si$epv)) .srow("Events per parameter", sprintf("%.1f", si$epv))
  )
  .ssection("covariates", "Covariates and sample", c(c_rows, iss_rows))
}


# ── 7. Model ──────────────────────────────────────────────────────────────────

.summary_model <- function(spec, result, data) {
  md   <- spec$model_design
  mt   <- md$model_type
  vr   <- spec$variable_roles
  mixed <- isTRUE(mt %in% c("linear_mixed", "logistic_mixed"))

  fmla <- if (!is.null(mt) && !is.null(vr$outcome_variable)) {
    paste(deparse(build_analysis_formula(spec), width.cutoff = 500L), collapse = " ")
  }

  rs <- result$run_status
  status <- if (is.null(rs$status)) {
    .srow("Status", "Not yet fitted")
  } else if (identical(rs$status, "failed")) {
    .srow("Status", paste("Last run failed:", rs$error %||% ""), level = "error")
  } else if (analysis_fit_is_stale(spec, result)) {
    .srow("Status", sprintf("Fitted %s, but the specification has changed since \u2014 re-run the model",
                            format(rs$fitted_at, "%H:%M")), level = "warning")
  } else {
    .srow("Status", sprintf("Fitted %s on %d rows", format(rs$fitted_at, "%Y-%m-%d %H:%M"),
                            rs$n_used %||% NA_integer_), level = "pass")
  }

  .ssection("model", "Model", list(
    .srow("Model", if (is.null(mt)) "None available for this outcome" else .ANALYSIS_MODEL_LABELS[[mt]]),
    if (!is.null(fmla)) .srow("Formula", fmla),
    if (mixed) .srow("Random intercepts", paste(vr$cluster_variables, collapse = ", ")),
    if (mixed) .srow("Optimizer", md$optimizer %||% "bobyqa"),
    if (!is.null(mt)) .srow("Inference", edark_inference_note(mt)),
    if (!is.null(sp <- analysis_split(spec))) .srow("Fitted on", sprintf("Training set (%s = %s)", sp$variable, sp$training_level)),
    .srow("Missing data", "Complete-case analysis"),
    status
  ))
}


# ── 8. Preflight checks ───────────────────────────────────────────────────────

.summary_checks <- function(validation) {
  msgs <- c(validation$messages, validation$passed)
  ord  <- order(match(vapply(msgs, `[[`, character(1), "level"),
                      c("error", "warning", "note", "pass")))
  rows <- lapply(msgs[ord], function(m) {
    .srow(switch(m$level, error = "Error", warning = "Warning", note = "Note", pass = "Pass"),
          m$message, level = m$level)
  })
  .ssection("checks", "Preflight checks", rows)
}


# ── Model › Results: methods paragraph ─────────────────────────────────────────────────

#' Build the methods paragraph
#'
#' Plain text describing the fitted model, in the past tense, for a
#' manuscript's statistical methods section. Describes the model as fitted —
#' not how the covariates were chosen. The CI / p-value sentence comes from
#' the same definitions as every table footnote (\code{.EDARK_INFERENCE}), and
#' the software sentence reports the R and package versions actually loaded.
#'
#' @param result The \code{analysis_result} (fitted model, snapshot,
#'   \code{run_status}; \code{diagnostics} when Diagnostics was run;
#'   \code{performance} when Performance was run).
#' @param include_unadjusted Logical: whether the results include unadjusted
#'   estimates.
#' @return A single character string (paragraphs separated by blank lines).
#' @export
build_methods_paragraph <- function(result, include_unadjusted = FALSE) {
  spec  <- result$specification_snapshot
  vr    <- spec$variable_roles
  md    <- spec$model_design
  mt    <- md$model_type
  rs    <- result$run_status
  logit <- mt %in% c("logistic", "logistic_mixed")
  mixed <- mt %in% c("linear_mixed", "logistic_mixed")
  outcome  <- vr$outcome_variable
  exposure <- vr$exposure_variable
  covs     <- vr$final_model_covariates
  clusters <- vr$cluster_variables
  .list <- function(x) {
    x <- as.character(x)
    if (length(x) <= 1L) return(x)
    if (length(x) == 2L) return(paste(x, collapse = " and "))
    paste0(paste(x[-length(x)], collapse = ", "), ", and ", x[length(x)])
  }

  model_label <- tolower(.ANALYSIS_MODEL_LABELS[[mt]])
  ev <- rs$outcome_event
  outcome_txt <- if (logit) {
    sprintf("%s (modelling the odds of %s = %s versus %s)", outcome, outcome, ev$event, ev$reference)
  } else outcome

  s <- character(0)
  s <- c(s, if (!is.null(exposure)) {
    sprintf("The association between %s and %s was estimated with %s %s.",
            exposure, outcome_txt, if (grepl("^[aeiou]", model_label)) "an" else "a", model_label)
  } else {
    sprintf("Factors associated with %s were examined with %s %s.",
            outcome_txt, if (grepl("^[aeiou]", model_label)) "an" else "a", model_label)
  })
  s <- c(s, if (length(covs) > 0L) {
    sprintf("The model %s %s.", if (!is.null(exposure)) "was adjusted for" else "included", .list(covs))
  } else if (!is.null(exposure)) {
    "The model included the exposure only (no covariates)."
  })
  if (mixed) {
    s <- c(s, if (length(clusters) == 1L) {
      sprintf("A random intercept for %s accounted for clustering of observations within %s.",
              clusters, clusters)
    } else {
      sprintf("Random intercepts for %s accounted for clustering of observations within each grouping.",
              .list(clusters))
    })
    s <- c(s, if (mt == "linear_mixed") {
      sprintf("The model was fitted by restricted maximum likelihood (REML) using the %s optimizer.",
              md$optimizer %||% "bobyqa")
    } else {
      sprintf("The model was fitted by maximum likelihood (Laplace approximation) using the %s optimizer.",
              md$optimizer %||% "bobyqa")
    })
  }
  refs <- rs$reference_levels
  if (length(refs) > 0L) {
    s <- c(s, sprintf("Categorical variables were compared with a reference category (%s).",
                      paste(sprintf("%s: %s", names(refs), unlist(refs)), collapse = "; ")))
  }
  sp <- analysis_split(spec)
  if (!is.null(sp)) {
    s <- c(s, sprintf(paste(
      "The model was developed in a training set (%s = %s); observations with any other value of %s",
      "formed a held-out test set that was not used for variable selection or model fitting."),
      sp$variable, sp$training_level, sp$variable))
  }
  pct <- if (isTRUE(rs$n_total > 0)) round(100 * rs$n_used / rs$n_total, 1) else NA
  s <- c(s, sprintf(
    "The analysis was restricted to complete cases: %d of %d %sobservations (%s%%) had no missing values in any model variable.",
    rs$n_used, rs$n_total, if (!is.null(sp)) "training " else "", format(pct, nsmall = 1)))
  if (isTRUE(include_unadjusted)) {
    s <- c(s, sprintf(
      "Unadjusted estimates came from separate models containing one variable at a time, fitted to the same %d observations%s.",
      rs$n_used, if (mixed) " with the same random intercepts" else ""))
  }
  inf <- .EDARK_INFERENCE[[mt]]
  s <- c(s, sprintf("Results are reported as %s with %s; p-values are from %s.%s",
                    if (logit) "odds ratios" else "regression coefficients",
                    sub(", exponentiated to odds ratios$", "", inf$ci),
                    inf$p,
                    if (!is.null(inf$caution)) paste0(" ", inf$caution) else ""))

  diag_txt <- .methods_diagnostics(result$diagnostics)
  perf_txt <- .methods_performance(result$performance)
  para1 <- paste(c(s, diag_txt, perf_txt), collapse = " ")
  paste(para1, .methods_software(mt, result$diagnostics, result$performance), sep = "\n\n")
}

.methods_diagnostics <- function(dg) {
  if (is.null(dg) || length(dg$checks) == 0L) return(NULL)
  .join <- function(x) {
    if (length(x) == 1L) return(x)
    if (length(x) == 2L) return(paste(x, collapse = " and "))
    paste0(paste(x[-length(x)], collapse = ", "), ", and ", x[length(x)])
  }
  assumptions <- c(
    residuals      = if (identical(dg$residuals$type, "binned")) "binned residual plots"
                     else if (identical(dg$residuals$type, "standard")) "residual plots and the Breusch-Pagan test"
                     else "residual plots",
    linearity      = "residuals plotted against each continuous predictor",
    influence      = "Cook's distance and leverage",
    vif            = "variance inflation factors",
    separation     = "a check for separation",
    random_effects = "the distribution of the random intercepts")
  a <- unname(assumptions[intersect(dg$checks, names(assumptions))])
  if (length(a)) sprintf("Model assumptions were assessed with %s.", .join(a))
}

.methods_performance <- function(pf) {
  if (is.null(pf) || length(pf$checks) == 0L) return(NULL)
  .join <- function(x) {
    if (length(x) == 1L) return(x)
    if (length(x) == 2L) return(paste(x, collapse = " and "))
    paste0(paste(x[-length(x)], collapse = ", "), ", and ", x[length(x)])
  }
  logit <- pf$model_type %in% c("logistic", "logistic_mixed")
  vl <- pf$validation
  validated <- intersect(c("test", "cv", "bootstrap"), names(pf$sets))
  has_val <- length(validated) > 0L
  where_val <- c(test = "in the test set", cv = "under cross-validation",
                 bootstrap = "after bootstrap optimism correction")[validated]
  slope_txt <- if (has_val) sprintf(", with the calibration intercept and slope %s", where_val[1L]) else ""
  measures <- c(
    discrimination   = if (has_val && validated[1L] != "test") "the area under the ROC curve"
                       else "the area under the ROC curve (DeLong 95% CI)",
    calibration      = if (logit) paste0("calibration plots and the Brier score", slope_txt)
                       else paste0("observed versus predicted values", slope_txt),
    prediction_error = "the root mean squared error, mean absolute error and R-squared of the predictions")
  m <- unname(measures[intersect(pf$checks, names(measures))])
  if (!length(m)) return(NULL)
  marg <- if (identical(pf$basis, "marginal")) ", using predictions from the fixed effects only" else ""
  first <- sprintf("Predictive performance was summarised with %s%s.", .join(m), marg)
  cl <- if (identical(pf$basis, "marginal")) " (resampling whole clusters)" else ""
  second <- switch(if (has_val) validated[1L] else "none",
    test = paste("Performance is reported both in the rows used to fit the model (apparent performance)",
                 "and in the held-out test set."),
    cv = sprintf(paste(
      "Performance was internally validated by %d-fold cross-validation repeated %d time%s%s%s (random seed %d):",
      "in each fold the model, with the same covariates, was refitted to the remaining folds and",
      "predicted the omitted rows; measures were computed on the pooled out-of-fold predictions and",
      "averaged over repeats. The reported coefficients are those of the model fitted to all rows."),
      vl$cv_folds, vl$cv_repeats, if (vl$cv_repeats == 1L) "" else "s",
      if (logit && !identical(pf$basis, "marginal")) ", stratified by outcome" else "",
      if (identical(pf$basis, "marginal")) ", with folds made of whole clusters" else "", vl$seed),
    bootstrap = sprintf(paste(
      "Performance was internally validated by bootstrap optimism correction with %d resamples%s (random seed %d):",
      "the model, with the same covariates, was refitted in each resample and the mean difference",
      "between its performance in the resample and in the original data was subtracted from the",
      "apparent performance. The reported coefficients are those of the model fitted to all rows."),
      vl$bootstrap_reps, cl, vl$seed),
    "Performance was measured in the rows used to fit the model (apparent performance, which is optimistic).")
  paste(first, second)
}

.methods_software <- function(mt, dg, pf = NULL) {
  pkgs <- c(
    if (mt %in% c("linear_mixed", "logistic_mixed")) "lme4",
    if (mt == "linear_mixed") "lmerTest",
    if (!is.null(dg)) "performance",
    if (!is.null(dg$residuals$bp)) "lmtest",
    if (!is.null(dg$separation)) "detectseparation",
    if (any(vapply(pf$sets, function(s) !is.null(s$auc), logical(1)))) "pROC")
  ver <- function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) "?")
  edark_v <- ver("edark")
  pk <- if (length(pkgs) > 0L) {
    paste0(" and the R packages ", paste(sprintf("%s %s", pkgs, vapply(pkgs, ver, character(1))), collapse = ", "))
  } else ""
  sprintf("Analyses were performed in %s using EDARK %s%s.",
          sub("^R version ([0-9.]+).*$", "R \\1", R.version.string), edark_v, pk)
}
