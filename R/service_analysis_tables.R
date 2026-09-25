#' Analysis Table Generation Service
#'
#' Provides functions for generating \code{gtsummary} tables used in the
#' Analysis module. Called from Steps 2 (Table 1) and 7 (Results).
#' All functions are pure — no Shiny dependencies.
#'
#' @importFrom magrittr %>%
#'
#' @name service_analysis_tables
NULL


#' Build Table 1 (descriptive summary table)
#'
#' Generates up to three \code{gtsummary::tbl_summary} objects: an overall
#' summary and optional stratified tables by exposure and outcome.
#'
#' @param data A \code{data.frame} (the frozen analysis dataset).
#' @param spec A named list conforming to the \code{analysis_spec} structure.
#' @param include_pvalues_exposure,include_pvalues_outcome Logical. Add p-values
#'   to the by-exposure / by-outcome tab. \code{NULL} (the default) falls back to
#'   the matching field in \code{spec$table1_specification}.
#' @param include_smd_exposure,include_smd_outcome Logical. Add standardized mean
#'   difference to the by-exposure / by-outcome tab. Only applied when that
#'   stratifier has exactly 2 observed levels. \code{NULL} (the default) falls
#'   back to the matching field in \code{spec$table1_specification}.
#'
#' @details P-values and SMD are mutually exclusive per tab: when both are
#'   requested for the same stratifier, SMD wins.
#'
#' @return A named list: \code{overall}, \code{by_exposure}, \code{by_outcome}.
#'   Elements are \code{NULL} when not applicable.
#' @export
build_table1 <- function(data,
                         spec,
                         include_pvalues_exposure = NULL,
                         include_pvalues_outcome  = NULL,
                         include_smd_exposure     = NULL,
                         include_smd_outcome      = NULL) {

  roles        <- spec$variable_roles
  outcome_var  <- roles$outcome_variable
  exposure_var <- roles$exposure_variable
  t1_vars      <- roles$table1_variables
  t1_spec      <- spec$table1_specification

  t1_vars <- setdiff(t1_vars, ".edark_row_id")
  t1_vars <- intersect(names(data), t1_vars)          # dataset column order
  priority <- c(exposure_var, outcome_var)
  priority <- priority[!vapply(priority, function(x) is.null(x) || !nzchar(x), logical(1))]
  priority <- intersect(priority, t1_vars)
  t1_vars  <- c(priority, setdiff(t1_vars, priority)) # exposure \u2192 outcome \u2192 rest

  if (length(t1_vars) == 0) {
    return(list(overall = NULL, by_exposure = NULL, by_outcome = NULL))
  }

  # A stratifier must be categorical with at least 2 observed levels. Without
  # this, a numeric `by` variable makes gtsummary treat every distinct value as
  # its own group.
  .can_stratify <- function(v) {
    if (is.null(v) || !nzchar(v) || !v %in% names(data)) return(FALSE)
    col <- data[[v]]
    if (!(is.factor(col) || is.character(col) || is.logical(col))) return(FALSE)
    length(unique(stats::na.omit(as.character(col)))) >= 2L
  }

  .build_one <- function(by_var, include_p, include_smd_flag) {
    tryCatch({
      if (!is.null(by_var) && by_var %in% names(data)) {
        all_vars <- unique(c(t1_vars, by_var))
        all_vars <- intersect(all_vars, names(data))

        tbl <- gtsummary::tbl_summary(
          data    = data[, all_vars, drop = FALSE],
          by      = by_var,
          missing = "no"
        ) %>%
          gtsummary::add_overall() %>%
          gtsummary::bold_labels()

        if (include_p) {
          # Same tests and p-value display as every other group comparison
          # in the app (stats_inference.R): Kruskal-Wallis for numeric
          # variables; chi-square, or Fisher's exact when any expected
          # count < 5, for categorical ones.
          tbl <- tbl %>% gtsummary::add_p(
            test = list(
              gtsummary::all_continuous()  ~ "kruskal.test",
              gtsummary::all_categorical() ~ .gts_categorical_test
            ),
            pvalue_fun = function(x) ifelse(is.na(x), NA_character_, edark_format_p(x))
          )
        }

        if (include_smd_flag) {
          strat_col <- data[[by_var]]
          n_levels  <- if (is.factor(strat_col)) {
            length(levels(droplevels(strat_col)))
          } else {
            length(unique(stats::na.omit(strat_col)))
          }
          if (n_levels == 2L) {
            tbl <- tryCatch(
              tbl %>% gtsummary::add_difference(
                test = list(
                  gtsummary::all_continuous()   ~ "smd",
                  gtsummary::all_categorical()  ~ "smd"
                )
              ),
              error = function(e) tbl
            )
          }
        }

        # Span the level columns with the stratifying variable's name, so the
        # header reads e.g. "liver_donor_type" over "Deceased | Living".
        # stat_0 = FALSE keeps the Overall column outside the span.
        tbl <- tryCatch(
          tbl %>% gtsummary::modify_spanning_header(
            gtsummary::all_stat_cols(stat_0 = FALSE) ~ paste0("**", by_var, "**")
          ),
          error = function(e) tbl
        )

        tbl
      } else {
        gtsummary::tbl_summary(
          data    = data[, t1_vars, drop = FALSE],
          missing = "no"
        ) %>%
          gtsummary::bold_labels()
      }
    }, error = function(e) NULL)
  }

  overall <- .build_one(NULL, FALSE, FALSE)

  # An explicit argument wins; NULL falls back to the spec.
  .flag <- function(arg, spec_val) if (is.null(arg)) isTRUE(spec_val) else isTRUE(arg)

  p_exp   <- .flag(include_pvalues_exposure, t1_spec$include_pvalues_exposure)
  p_out   <- .flag(include_pvalues_outcome,  t1_spec$include_pvalues_outcome)
  smd_exp <- .flag(include_smd_exposure,     t1_spec$include_smd_exposure)
  smd_out <- .flag(include_smd_outcome,      t1_spec$include_smd_outcome)

  by_exposure <- if (.can_stratify(exposure_var) &&
                     isTRUE(t1_spec$stratify_by_exposure)) {
    .build_one(exposure_var, p_exp && !smd_exp, smd_exp)
  } else NULL

  by_outcome <- if (.can_stratify(outcome_var) &&
                    isTRUE(t1_spec$stratify_by_outcome)) {
    .build_one(outcome_var, p_out && !smd_out, smd_out)
  } else NULL

  list(overall = overall, by_exposure = by_exposure, by_outcome = by_outcome)
}


# ── Model › Results: results table ─────────────────────────────────────────────────────

#' Build the Model › Results table
#'
#' One data frame holds every number and label in the table; the screen
#' (\code{results_table_gt()}) and the Word export
#' (\code{results_table_flextable()}) only format it. Rows: each predictor of
#' the fitted model (exposure first, then covariates). A factor gets a header
#' row, then one row per level with its reference level marked. Adjusted
#' values are the Step 5 coefficients; unadjusted values come from
#' \code{fit_unadjusted_models()}. No intercept.
#'
#' @param result The \code{analysis_result} (fitted model, snapshot,
#'   \code{inference_summary$coefficients}, \code{run_status}).
#' @param unadjusted Output of \code{fit_unadjusted_models()}, or \code{NULL}
#'   to leave out the unadjusted column.
#'
#' @return A data.frame with columns \code{row_type} (\code{"continuous"},
#'   \code{"header"}, \code{"level"}, \code{"reference"}), \code{variable},
#'   \code{level}, \code{label}, \code{is_exposure}, \code{adj_est},
#'   \code{adj_low}, \code{adj_high}, \code{adj_p}, \code{unadj_est},
#'   \code{unadj_low}, \code{unadj_high}, \code{unadj_p}, \code{unadj_status}.
#'   Attributes: \code{model_type}, \code{measure} ("OR" / "β"),
#'   \code{n_used}, \code{include_unadjusted}, \code{footnotes} (character).
#' @export
build_results_table <- function(result, unadjusted = NULL) {
  spec  <- result$specification_snapshot
  roles <- spec$variable_roles
  mt    <- spec$model_design$model_type
  logit <- mt %in% c("logistic", "logistic_mixed")
  mixed <- mt %in% c("linear_mixed", "logistic_mixed")
  exposure <- roles$exposure_variable
  preds <- .safe_preds(exposure, roles$final_model_covariates)
  adj   <- result$inference_summary$coefficients
  mf    <- stats::model.frame(result$fitted_models$primary_model)
  refs  <- result$run_status$reference_levels
  un    <- unadjusted$coefficients
  st    <- unadjusted$status

  .vals <- function(tbl, v, lvl) {
    if (is.null(tbl)) return(c(NA, NA, NA, NA))
    r <- tbl[tbl$variable %in% v & (if (is.na(lvl)) is.na(tbl$level) else tbl$level %in% lvl), , drop = FALSE]
    if (nrow(r) == 0L) return(c(NA, NA, NA, NA))
    c(r$effect[1L], r$effect.low[1L], r$effect.high[1L], r$p.value[1L])
  }
  .row <- function(type, v, lvl, label) {
    a <- if (type %in% c("level", "continuous")) .vals(adj, v, lvl) else rep(NA, 4)
    u <- if (type %in% c("level", "continuous")) .vals(un, v, lvl) else rep(NA, 4)
    s <- if (is.null(st)) NA_character_ else {
      x <- st$status[st$variable == v]
      if (length(x)) x else NA_character_
    }
    data.frame(row_type = type, variable = v, level = lvl, label = label,
               is_exposure = identical(v, exposure),
               adj_est = a[1], adj_low = a[2], adj_high = a[3], adj_p = a[4],
               unadj_est = u[1], unadj_low = u[2], unadj_high = u[3], unadj_p = u[4],
               unadj_status = s, stringsAsFactors = FALSE)
  }

  rows <- list()
  for (v in preds) {
    lv <- .edark_var_levels(mf[[v]])
    if (is.null(lv)) {
      rows[[length(rows) + 1L]] <- .row("continuous", v, NA_character_, v)
    } else {
      ref <- refs[[v]] %||% lv[1L]
      rows[[length(rows) + 1L]] <- .row("header", v, NA_character_, v)
      for (l in lv) {
        rows[[length(rows) + 1L]] <- .row(if (identical(l, ref)) "reference" else "level", v, l, l)
      }
    }
  }
  out <- do.call(rbind, rows)

  # ── Footnotes ──
  ev <- result$run_status$outcome_event
  fn <- c(
    if (logit) sprintf("OR = odds ratio for %s = %s (vs %s).", ev$variable, ev$event, ev$reference)
    else "\u03b2 = regression coefficient (difference in the outcome).",
    if (any(out$row_type == "continuous")) "Continuous variables: per 1-unit increase.",
    sprintf("Adjusted: one model including all variables shown%s (n = %d).",
            if (mixed) paste0(", with random intercepts for ", paste(roles$cluster_variables, collapse = ", ")) else "",
            nrow(mf)),
    if (!is.null(unadjusted)) {
      sprintf("Unadjusted: a separate model for each variable, fitted to the same %d observations%s.",
              nrow(mf), if (mixed) " with the same random intercepts" else "")
    },
    edark_inference_note(mt)
  )
  if (!is.null(st)) {
    w <- st[st$status == "warning", , drop = FALSE]
    f <- st[st$status == "failed", , drop = FALSE]
    if (nrow(w) > 0L) {
      fn <- c(fn, paste0("\u2020 Unadjusted model fitted with a warning - ",
                         paste(sprintf("%s: %s", w$variable, w$message), collapse = "; "), "."))
    }
    if (nrow(f) > 0L) {
      fn <- c(fn, paste0("\u2021 Unadjusted model could not be fitted - ",
                         paste(sprintf("%s: %s", f$variable, f$message), collapse = "; "), "."))
    }
  }

  attr(out, "model_type")         <- mt
  attr(out, "measure")            <- if (logit) "OR" else "\u03b2"
  attr(out, "n_used")             <- nrow(mf)
  attr(out, "include_unadjusted") <- !is.null(unadjusted)
  attr(out, "footnotes")          <- fn
  out
}


# Display strings for the results table (shared by gt and flextable).
.results_display <- function(tbl) {
  est_cell <- function(prefix) {
    e <- tbl[[paste0(prefix, "_est")]]
    x <- edark_format_ci(e, tbl[[paste0(prefix, "_low")]], tbl[[paste0(prefix, "_high")]])
    x[tbl$row_type == "header"]    <- ""
    x[tbl$row_type == "reference"] <- "Reference"
    x
  }
  p_cell <- function(prefix) {
    x <- edark_format_p(tbl[[paste0(prefix, "_p")]])
    x[tbl$row_type %in% c("header", "reference")] <- ""
    x
  }
  d <- data.frame(label = tbl$label, adj_est = est_cell("adj"), adj_p = p_cell("adj"),
                  stringsAsFactors = FALSE)
  if (isTRUE(attr(tbl, "include_unadjusted"))) {
    u <- est_cell("unadj")
    mark <- ifelse(tbl$unadj_status %in% "warning", "\u2020",
                   ifelse(tbl$unadj_status %in% "failed", "\u2021", ""))
    show <- tbl$row_type %in% c("level", "continuous")
    u[show] <- paste0(u[show], mark[show])
    d <- data.frame(label = d$label, unadj_est = u, unadj_p = p_cell("unadj"),
                    adj_est = d$adj_est, adj_p = d$adj_p, stringsAsFactors = FALSE)
  }
  d
}


#' Render the results table
#'
#' @param tbl Output of \code{build_results_table()}.
#' @return \code{results_table_gt()}: a \code{gt} table for the app.
#' @export
results_table_gt <- function(tbl) {
  d <- .results_display(tbl)
  measure <- attr(tbl, "measure")
  est_lab <- sprintf("%s (95%% CI)", measure)
  unadj   <- isTRUE(attr(tbl, "include_unadjusted"))

  g <- gt::gt(d) %>%
    gt::cols_label(label = "", adj_est = est_lab, adj_p = "p") %>%
    gt::cols_align("right", columns = setdiff(names(d), "label")) %>%
    gt::tab_spanner(sprintf("Adjusted (n = %d)", attr(tbl, "n_used")), columns = c("adj_est", "adj_p"))
  if (unadj) {
    g <- g %>%
      gt::cols_label(unadj_est = est_lab, unadj_p = "p") %>%
      gt::tab_spanner("Unadjusted", columns = c("unadj_est", "unadj_p"))
  }
  lvl_rows <- which(tbl$row_type %in% c("level", "reference"))
  ref_rows <- which(tbl$row_type == "reference")
  exp_rows <- which(tbl$is_exposure & tbl$row_type %in% c("header", "continuous"))
  if (length(lvl_rows)) {
    g <- gt::tab_style(g, gt::cell_text(indent = gt::px(18)), gt::cells_body(columns = "label", rows = lvl_rows))
  }
  if (length(ref_rows)) {
    g <- gt::tab_style(g, gt::cell_text(style = "italic", color = "#6c757d"), gt::cells_body(rows = ref_rows))
  }
  if (length(exp_rows)) {
    g <- gt::tab_style(g, gt::cell_text(weight = "bold"), gt::cells_body(columns = "label", rows = exp_rows))
  }
  for (f in attr(tbl, "footnotes")) g <- gt::tab_source_note(g, f)
  g %>% gt::tab_options(table.font.size = gt::px(14), data_row.padding = gt::px(4),
                        source_notes.font.size = gt::px(12))
}


#' @rdname results_table_gt
#' @return \code{results_table_flextable()}: a \code{flextable} for Word export.
#' @export
results_table_flextable <- function(tbl) {
  d <- .results_display(tbl)
  measure <- attr(tbl, "measure")
  est_lab <- sprintf("%s (95%% CI)", measure)
  unadj   <- isTRUE(attr(tbl, "include_unadjusted"))

  ft <- flextable::flextable(d)
  ft <- flextable::set_header_labels(ft, values = c(
    list(label = "", adj_est = est_lab, adj_p = "p"),
    if (unadj) list(unadj_est = est_lab, unadj_p = "p")))
  ft <- flextable::add_header_row(
    ft, colwidths = if (unadj) c(1, 2, 2) else c(1, 2),
    values = c("", if (unadj) "Unadjusted", sprintf("Adjusted (n = %d)", attr(tbl, "n_used"))))
  lvl_rows <- which(tbl$row_type %in% c("level", "reference"))
  ref_rows <- which(tbl$row_type == "reference")
  exp_rows <- which(tbl$is_exposure & tbl$row_type %in% c("header", "continuous"))
  if (length(lvl_rows)) ft <- flextable::padding(ft, i = lvl_rows, j = 1, padding.left = 14)
  if (length(ref_rows)) ft <- flextable::italic(ft, i = ref_rows)
  if (length(exp_rows)) ft <- flextable::bold(ft, i = exp_rows, j = 1)
  ft <- flextable::align(ft, j = seq(2, ncol(d)), align = "right", part = "all")
  for (f in attr(tbl, "footnotes")) ft <- flextable::add_footer_lines(ft, f)
  ft <- flextable::fontsize(ft, size = 9, part = "footer")
  flextable::autofit(flextable::theme_booktabs(ft))
}


#' Format fit statistics for display and export
#'
#' @param result The \code{analysis_result}. Adds the AUC (and its 95% CI)
#'   when Performance computed it, for each set of rows (apparent, test).
#' @return A data.frame(Statistic, Value) of display strings, or \code{NULL}.
#' @export
build_fit_statistics_table <- function(result) {
  fs <- result$inference_summary$fit_statistics
  if (is.null(fs) || nrow(fs) == 0L) return(NULL)
  val <- vapply(seq_len(nrow(fs)), function(i) .fmt_fit_stat(fs$value[i], fs$format[i]), character(1))
  out <- data.frame(Statistic = fs$label, Value = val, stringsAsFactors = FALSE)
  pf <- result$performance
  set_names <- c(apparent = "apparent", test = "test set", cv = "cross-validated",
                 bootstrap = "bootstrap-corrected")
  for (s in names(pf$sets)) {
    v <- pf$sets[[s]]
    what <- set_names[[s]] %||% s
    if (identical(pf$basis, "marginal")) what <- paste("marginal predictions,", what)
    if (!is.null(v$auc)) {
      out <- rbind(out, data.frame(
        Statistic = sprintf("AUC (%s)", what),
        Value = if (is.null(v$auc_low)) edark_format_est(v$auc) else edark_format_ci(v$auc, v$auc_low, v$auc_high),
        stringsAsFactors = FALSE))
    }
    # In-sample the calibration slope is 1 by construction; report validated ones
    if (s != "apparent" && !is.null(v$cal_slope)) {
      out <- rbind(out, data.frame(Statistic = sprintf("Calibration slope (%s)", what),
                                   Value = edark_format_est(v$cal_slope), stringsAsFactors = FALSE))
    }
  }
  out
}

.fmt_fit_stat <- function(value, format) {
  switch(format,
    integer = format(round(value), big.mark = ","),
    percent = sprintf("%.1f%%", value * 100),
    pvalue  = edark_format_p(value),
    edark_format_est(value))
}
