#' Analysis Diagnostic Computation Service
#'
#' Post-fit diagnostics for the Step 5 model (PRD §7.2\enc{–}{-}7.5). Pure
#' functions — no Shiny. \code{analysis_diagnostic_options()} lists the checks
#' a model type offers; \code{run_analysis_diagnostics()} computes the selected
#' ones and returns values, plots and messages for Model › Diagnostics to store.
#'
#' Checks of the model's assumptions and stability: residuals (standard plots
#' + Breusch-Pagan for linear models; binned residuals for logistic models,
#' whose raw residuals are uninformative), linearity of each continuous
#' predictor, influence (Cook's distance, leverage — non-mixed models),
#' collinearity (VIF), separation (logistic), random effects (per-cluster
#' variance, ICC, cluster sizes, Q-Q — mixed). Sample accounting and fitting
#' warnings (convergence, singular fit) are always reported — they cost
#' nothing and belong with every model.
#'
#' Predictive performance (discrimination, calibration, prediction error) is
#' Model › Performance — \code{service_analysis_performance.R}.
#'
#' @importFrom magrittr %>%
#'
#' @name service_analysis_diagnostics
NULL


# VIF nudges (PRD §4.5) and the conventional Cook's distance cut-off (4 / n)
.DIAG_VIF_MODERATE <- 5
.DIAG_VIF_HIGH     <- 10
.DIAG_TOP_INFLUENTIAL <- 10L


#' Diagnostic checks available for a model type
#'
#' @param model_type One of \code{"linear"}, \code{"logistic"},
#'   \code{"linear_mixed"}, \code{"logistic_mixed"}.
#' @return A \code{data.frame(id, label, description)}.
#' @export
analysis_diagnostic_options <- function(model_type) {
  if (is.null(model_type)) return(NULL)
  logit <- model_type %in% c("logistic", "logistic_mixed")
  mixed <- model_type %in% c("linear_mixed", "logistic_mixed")

  rows <- list(
    list("residuals", "Residuals",
         if (logit) "Binned residuals (raw residuals of a 0/1 outcome are not interpretable)"
         else if (mixed) "Residuals vs fitted, Q-Q and scale-location (conditional residuals)"
         else "Residuals vs fitted, Q-Q, scale-location and the Breusch-Pagan test"),
    list("linearity", "Linearity",
         if (logit) "Binned residuals against each continuous predictor (linear on the log-odds scale?)"
         else "Residuals against each continuous predictor"),
    if (!mixed) list("influence", "Influential observations",
                     "Cook's distance, leverage and the most influential rows"),
    list("vif", "Collinearity (VIF)",
         "Variance inflation factor for each predictor"),
    if (logit) list("separation", "Separation",
                    if (mixed) "Checked on the fixed effects" else
                      "Whether a predictor perfectly predicts the outcome"),
    if (mixed) list("random_effects", "Random effects",
                    "Variance and ICC per cluster variable, cluster sizes, Q-Q of cluster intercepts")
  )
  rows <- Filter(Negate(is.null), rows)
  data.frame(
    id          = vapply(rows, `[[`, character(1), 1L),
    label       = vapply(rows, `[[`, character(1), 2L),
    description = vapply(rows, `[[`, character(1), 3L),
    stringsAsFactors = FALSE
  )
}


#' Run post-fit diagnostics
#'
#' @param result The \code{analysis_result} holding a fitted
#'   \code{primary_model}, its \code{specification_snapshot},
#'   \code{run_status} and \code{inference_summary$predicted_values}.
#' @param data The rows the model was built from (for sample accounting):
#'   \code{analysis_model_data(spec, analysis_data)} — the training set when
#'   a train/test split applies.
#' @param checks Character vector of check ids from
#'   \code{analysis_diagnostic_options()}. Unknown or inapplicable ids are
#'   ignored.
#' @param progress_fn Optional \code{function(fraction, detail)}.
#'
#' @return A named list: \code{run_at}, \code{model_type}, \code{checks}
#'   (ids actually run), \code{sample}, \code{residuals}, \code{linearity},
#'   \code{influence}, \code{vif}, \code{separation}, \code{random_effects}
#'   (each \code{NULL} when not run), \code{influence_measures} (per-row
#'   data.frame, non-mixed models), \code{metrics} (long data.frame: section,
#'   key, label, value, format, level — every computed value, for the
#'   at-a-glance panel and export), \code{messages} (data.frame: level,
#'   message) and \code{plots} (named list of ggplot objects).
#' @export
run_analysis_diagnostics <- function(result, data, checks, progress_fn = NULL) {
  model <- result$fitted_models$primary_model
  if (is.null(model)) stop("No fitted model to diagnose.")
  spec       <- result$specification_snapshot
  model_type <- spec$model_design$model_type
  outcome    <- spec$variable_roles$outcome_variable
  logit      <- model_type %in% c("logistic", "logistic_mixed")
  mixed      <- model_type %in% c("linear_mixed", "logistic_mixed")

  avail  <- analysis_diagnostic_options(model_type)$id
  checks <- intersect(checks, avail)

  mf  <- stats::model.frame(model)
  ids <- result$inference_summary$predicted_values$.edark_row_id
  if (length(ids) != nrow(mf)) ids <- seq_len(nrow(mf))

  out <- list(run_at = Sys.time(), model_type = model_type, checks = checks,
              sample = NULL, residuals = NULL, linearity = NULL, influence = NULL,
              vif = NULL, separation = NULL, random_effects = NULL,
              influence_measures = NULL)
  metrics <- list()
  msgs    <- data.frame(level = character(0), message = character(0), stringsAsFactors = FALSE)
  plots   <- list()

  .metric <- function(section, key, label, value, format = "number", level = NA_character_) {
    if (is.null(value) || length(value) == 0L) return()
    value <- suppressWarnings(as.numeric(value[1L]))
    if (is.na(value)) return()
    metrics[[length(metrics) + 1L]] <<- data.frame(
      section = section, key = key, label = label, value = value,
      format = format, level = level, stringsAsFactors = FALSE)
  }
  .msg <- function(level, text) msgs[nrow(msgs) + 1L, ] <<- list(level, text)
  .progress <- function(frac, detail) if (is.function(progress_fn)) progress_fn(frac, detail)
  .try <- function(label, expr) {
    tryCatch(suppressMessages(expr), error = function(e) {
      .msg("warning", sprintf("%s could not be computed: %s", label, conditionMessage(e)))
      NULL
    })
  }

  # ── Sample accounting (always) ──────────────────────────────────────────────
  .progress(0.1, "Sample accounting\u2026")
  out$sample <- .diag_sample(spec, data, mf, outcome, logit, mixed)
  .metric("sample", "n_total", "Rows in analysis dataset", out$sample$n_total, "integer")
  .metric("sample", "n_used", "Rows used by the model", out$sample$n_used, "integer")
  .metric("sample", "n_excluded", "Excluded (missing data)", out$sample$n_total - out$sample$n_used, "integer")
  if (logit) {
    .metric("sample", "n_events", sprintf("Events (%s = %s)", outcome, out$sample$event), out$sample$n_events, "integer")
    .metric("sample", "event_rate", "Event rate", out$sample$n_events / out$sample$n_used, "percent")
  }

  # ── Fitting warnings (always) ───────────────────────────────────────────────
  rm <- result$run_status$run_messages
  if (!is.null(rm) && nrow(rm) > 0L) {
    fit_w <- rm[rm$level == "warning" & rm$stage == "fit", , drop = FALSE]
    for (m in fit_w$message) .msg("warning", m)
  }
  if (mixed) {
    singular <- isTRUE(lme4::isSingular(model))
    .metric("fit", "singular", "Singular fit", as.integer(singular), "yesno",
            if (singular) "warning" else NA_character_)
    # lme4 files the singular-fit notice under convergence messages too
    conv <- model@optinfo$conv$lme4$messages
    conv <- conv[!grepl("singular", conv, ignore.case = TRUE)]
    .metric("fit", "converged", "Converged", as.integer(length(conv) == 0L), "yesno",
            if (length(conv) > 0L) "warning" else NA_character_)
  }

  # ── Residuals ───────────────────────────────────────────────────────────────
  if ("residuals" %in% checks) {
    .progress(0.25, "Residuals\u2026")
    r <- .try("Residual diagnostics", .diag_residuals(model, model_type))
    if (!is.null(r)) {
      out$residuals <- r[setdiff(names(r), "plots")]
      plots <- c(plots, r$plots)
      if (!is.null(r$bp)) {
        .metric("residuals", "bp_stat", "Breusch-Pagan statistic", r$bp$statistic)
        .metric("residuals", "bp_p", "Breusch-Pagan p-value", r$bp$p.value, "pvalue")
      }
      if (!is.null(r$binned)) {
        .metric("residuals", "binned_inside", "Bins within the error bounds", r$binned_inside, "percent")
      }
    }
  }

  # ── Linearity ───────────────────────────────────────────────────────────────
  if ("linearity" %in% checks) {
    .progress(0.33, "Linearity\u2026")
    lin <- .try("Linearity check", .diag_linearity(model, mf, spec, logit))
    if (is.character(lin)) {
      .msg("note", lin)
    } else if (!is.null(lin)) {
      out$linearity <- lin[setdiff(names(lin), "plots")]
      plots <- c(plots, lin$plots)
      if (!is.null(lin$inside)) {
        for (i in seq_len(nrow(lin$inside))) {
          .metric("linearity", paste0("lin_", lin$inside$term[i]),
                  sprintf("Bins within the error bounds (%s)", lin$inside$term[i]),
                  lin$inside$inside[i], "percent")
        }
      }
    }
  }

  # ── Influence ───────────────────────────────────────────────────────────────
  if ("influence" %in% checks) {
    .progress(0.4, "Influence\u2026")
    inf <- .try("Influence measures", .diag_influence(model, mf, ids, logit))
    if (!is.null(inf)) {
      out$influence          <- inf[setdiff(names(inf), c("plots", "measures"))]
      out$influence_measures <- inf$measures
      plots <- c(plots, inf$plots)
      .metric("influence", "cooks_max", "Largest Cook's distance", inf$cooks_max)
      .metric("influence", "cooks_threshold", "Cook's distance cut-off (4 / n)", inf$threshold)
      .metric("influence", "n_above", "Rows above the cut-off", inf$n_above, "integer")
    }
  }

  # ── Collinearity ────────────────────────────────────────────────────────────
  if ("vif" %in% checks) {
    .progress(0.55, "Collinearity\u2026")
    v <- .try("VIF", .diag_vif(model))
    if (is.character(v)) {
      .msg("note", v)
    } else if (!is.null(v)) {
      out$vif <- v
      .metric("vif", "vif_max", "Largest VIF", max(v$vif, na.rm = TRUE), "number",
              if (any(v$flag != "ok")) "warning" else NA_character_)
      hi  <- v$term[v$flag == "high"]
      mod <- v$term[v$flag == "moderate"]
      if (length(hi) > 0L) {
        .msg("warning", sprintf("High variance inflation (VIF > %d): %s. Review the VIF table.",
                                .DIAG_VIF_HIGH, paste(hi, collapse = ", ")))
      }
      if (length(mod) > 0L) {
        .msg("warning", sprintf("Moderate variance inflation (VIF %d\u2013%d): %s. Interpret these estimates cautiously.",
                                .DIAG_VIF_MODERATE, .DIAG_VIF_HIGH, paste(mod, collapse = ", ")))
      }
    }
  }

  # ── Separation ──────────────────────────────────────────────────────────────
  if ("separation" %in% checks) {
    .progress(0.65, "Separation\u2026")
    s <- .try("Separation check", .diag_separation(model, mf, mixed))
    if (!is.null(s)) {
      out$separation <- s
      .metric("separation", "separation", "Separation detected", as.integer(s$detected), "yesno",
              if (s$detected) "warning" else NA_character_)
      if (s$detected) {
        .msg("warning", sprintf(paste(
          "Separation detected: %s. Their estimates are unreliable (infinite in theory);",
          "consider merging sparse factor levels or removing the variable."),
          paste(s$terms, collapse = ", ")))
      }
    }
  }

  # ── Random effects ──────────────────────────────────────────────────────────
  if ("random_effects" %in% checks) {
    .progress(0.75, "Random effects\u2026")
    re <- .try("Random-effects summary", .diag_random_effects(model, mf, logit))
    if (!is.null(re)) {
      out$random_effects <- re[setdiff(names(re), "plots")]
      plots <- c(plots, re$plots)
      comp <- re$components
      for (i in seq_len(nrow(comp))) {
        g <- comp$group[i]
        .metric("random_effects", paste0("icc_", g), sprintf("ICC (%s)", g), comp$icc[i])
        .metric("random_effects", paste0("sd_", g), sprintf("Intercept SD (%s)", g), comp$sd[i])
        .metric("random_effects", paste0("n_groups_", g), sprintf("Clusters (%s)", g), comp$n_groups[i], "integer")
        .metric("random_effects", paste0("median_size_", g), sprintf("Median cluster size (%s)", g),
                comp$median_size[i], "integer")
      }
      if (nrow(comp) > 1L) .metric("random_effects", "icc_adjusted", "ICC (all clusters)", re$icc_adjusted)
    }
  }

  .progress(0.95, "Finishing\u2026")
  out$metrics  <- if (length(metrics) > 0L) do.call(rbind, metrics) else NULL
  out$messages <- msgs
  out$plots    <- plots
  out
}


# ── Helpers ──────────────────────────────────────────────────────────────────

.diag_sample <- function(spec, data, mf, outcome, logit, mixed) {
  vr   <- spec$variable_roles
  vars <- unique(c(outcome, vr$exposure_variable, vr$final_model_covariates,
                   if (mixed) vr$cluster_variables))
  vars <- intersect(vars, names(data))
  missing <- data.frame(
    variable  = vars,
    n_missing = vapply(vars, function(v) sum(is.na(data[[v]])), integer(1)),
    stringsAsFactors = FALSE, row.names = NULL
  )
  s <- list(n_total = nrow(data), n_used = nrow(mf), missing = missing,
            event = NULL, n_events = NULL)
  if (logit) {
    y <- mf[[outcome]]
    s$event    <- levels(y)[2L]
    s$n_events <- sum(y == s$event)
  }
  s
}


.diag_residuals <- function(model, model_type) {
  if (model_type %in% c("logistic", "logistic_mixed")) {
    # Response residuals (y - p), as in Gelman & Hill; performance's default
    # (deviance) residuals do not average to zero, so the bins look biased.
    b <- performance::binned_residuals(model, residuals = "response")
    b <- as.data.frame(b)
    inside <- mean(b$group == "yes", na.rm = TRUE)
    return(list(
      type = "binned", binned = b, binned_inside = inside, bp = NULL,
      plots = list(binned_residuals = .plot_binned_residuals(b))
    ))
  }

  fitted <- as.numeric(stats::fitted(model))
  resid  <- as.numeric(stats::residuals(model))
  std    <- if (inherits(model, "lm")) as.numeric(stats::rstandard(model))
            else resid / stats::sigma(model)
  bp <- NULL
  if (model_type == "linear") {
    t  <- lmtest::bptest(model)
    bp <- list(statistic = unname(t$statistic), df = unname(t$parameter), p.value = unname(t$p.value))
  }
  list(
    type = if (model_type == "linear") "standard" else "conditional",
    bp = bp, binned = NULL, binned_inside = NULL,
    plots = list(
      residuals_vs_fitted = .plot_resid_fitted(fitted, resid),
      qq_plot             = .plot_qq(std, "Normal Q-Q (standardised residuals)"),
      scale_location      = .plot_scale_location(fitted, std)
    )
  )
}


.diag_influence <- function(model, mf, ids, logit) {
  cooks <- as.numeric(stats::cooks.distance(model))
  lev   <- as.numeric(stats::hatvalues(model))
  std   <- as.numeric(stats::rstandard(model))
  n     <- length(cooks)
  thr   <- 4 / n

  measures <- data.frame(.edark_row_id = ids, cooks = cooks, leverage = lev,
                         std_resid = std, stringsAsFactors = FALSE)
  top <- measures[order(-measures$cooks), , drop = FALSE]
  top <- utils::head(top, .DIAG_TOP_INFLUENTIAL)
  # The model variables for those rows, so the user can see who they are
  vals <- mf[match(top$.edark_row_id, ids), , drop = FALSE]
  vals[] <- lapply(vals, function(x) if (is.factor(x)) as.character(x) else x)
  top <- cbind(top, vals, row.names = NULL)

  list(
    threshold = thr,
    n_above   = sum(cooks > thr, na.rm = TRUE),
    cooks_max = max(cooks, na.rm = TRUE),
    top       = top,
    measures  = measures,
    plots = list(
      influence_plot = .plot_cooks(ids, cooks, thr),
      leverage_plot  = .plot_leverage(lev, std, cooks, ids, thr)
    )
  )
}


# Returns a data.frame(term, vif, flag), or a character note when VIF does not
# apply (fewer than two predictors).
.diag_vif <- function(model) {
  n_terms <- length(attr(stats::terms(model, fixed.only = TRUE), "term.labels"))
  if (n_terms < 2L) return("VIF needs at least two predictors in the model; not computed.")
  cc <- suppressWarnings(as.data.frame(performance::check_collinearity(model)))
  if (nrow(cc) == 0L) return("VIF could not be computed for this model.")
  vif <- as.numeric(cc$VIF)
  data.frame(
    term = as.character(cc$Term),
    vif  = vif,
    flag = ifelse(vif > .DIAG_VIF_HIGH, "high", ifelse(vif >= .DIAG_VIF_MODERATE, "moderate", "ok")),
    stringsAsFactors = FALSE
  )
}


.diag_separation <- function(model, mf, mixed) {
  fmla <- if (mixed) stats::formula(model, fixed.only = TRUE) else stats::formula(model)
  sep  <- suppressWarnings(stats::glm(fmla, data = mf, family = stats::binomial(),
                                      method = detectseparation::detect_separation))
  inf  <- sep$coefficients
  terms <- names(inf)[!is.na(inf) & is.infinite(inf)]
  list(detected = isTRUE(sep$outcome), terms = terms)
}


# Per-cluster variance, SD and ICC from VarCorr (performance::icc() returns NA
# once any variance component is ~0). ICC for a grouping = its variance / the
# total, where the residual variance is sigma^2 (linear) or pi^2 / 3 (logistic,
# latent scale).
.diag_random_effects <- function(model, mf, logit) {
  vc  <- as.data.frame(lme4::VarCorr(model))
  vc  <- vc[is.na(vc$var2), , drop = FALSE]
  grp <- vc[vc$grp != "Residual", , drop = FALSE]
  resid_var <- if (logit) pi^2 / 3 else stats::sigma(model)^2
  total <- sum(grp$vcov) + resid_var

  sizes <- lapply(grp$grp, function(g) {
    tab <- table(mf[[g]])
    data.frame(group = g, cluster = names(tab), n = as.integer(tab), stringsAsFactors = FALSE)
  })
  sizes <- do.call(rbind, sizes)

  comp <- data.frame(
    group    = grp$grp,
    variance = grp$vcov,
    sd       = grp$sdcor,
    icc      = grp$vcov / total,
    stringsAsFactors = FALSE
  )
  comp$n_groups    <- vapply(comp$group, function(g) sum(sizes$group == g), integer(1))
  comp$min_size    <- vapply(comp$group, function(g) min(sizes$n[sizes$group == g]), integer(1))
  comp$median_size <- vapply(comp$group, function(g) as.integer(round(stats::median(sizes$n[sizes$group == g]))), integer(1))
  comp$max_size    <- vapply(comp$group, function(g) max(sizes$n[sizes$group == g]), integer(1))

  re <- as.data.frame(lme4::ranef(model))
  re <- re[re$term == "(Intercept)", c("grpvar", "grp", "condval"), drop = FALSE]

  list(
    components     = comp,
    residual_variance = resid_var,
    residual_scale = if (logit) "latent (\u03c0\u00b2/3)" else "residual",
    icc_adjusted   = sum(grp$vcov) / total,
    cluster_sizes  = sizes,
    plots = list(
      random_effects_qq = .plot_ranef_qq(re),
      cluster_size_plot = .plot_cluster_sizes(sizes)
    )
  )
}


# Residuals against each continuous (numeric) predictor. Linear models: the
# model's residuals (conditional for mixed models). Logistic models: binned
# response residuals per predictor. Returns a character note when there is no
# continuous predictor.
.diag_linearity <- function(model, mf, spec, logit) {
  vr    <- spec$variable_roles
  preds <- .safe_preds(vr$exposure_variable, vr$final_model_covariates)
  num   <- preds[vapply(preds, function(v) v %in% names(mf) && is.numeric(mf[[v]]), logical(1))]
  if (length(num) == 0L) return("Linearity: the model has no continuous predictor, so there is nothing to check.")

  if (logit) {
    b <- lapply(num, function(v) {
      d <- as.data.frame(performance::binned_residuals(model, term = v, residuals = "response"))
      d$term <- v
      d
    })
    b <- do.call(rbind, b)
    inside <- stats::aggregate(list(inside = b$group == "yes"), list(term = b$term), mean)
    return(list(terms = num, inside = inside,
                plots = list(linearity_plot = .plot_linearity(b, binned = TRUE))))
  }

  resid <- as.numeric(stats::residuals(model))
  d <- do.call(rbind, lapply(num, function(v) {
    data.frame(term = v, x = as.numeric(mf[[v]]), resid = resid, stringsAsFactors = FALSE)
  }))
  list(terms = num, inside = NULL,
       plots = list(linearity_plot = .plot_linearity(d, binned = FALSE)))
}
