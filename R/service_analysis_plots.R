#' Analysis Plot Generation Service
#'
#' \code{ggplot2} figures for the Analysis module. Each function takes plain
#' vectors / data frames (never a Shiny object) and returns a ggplot, so the
#' same figure is shown in the app and saved by the export.
#' Diagnostic plots (Model › Diagnostics), performance plots (Model › Performance) and the forest plot
#' (Model › Results).
#'
#' @importFrom magrittr %>%
#'
#' @name service_analysis_plots
NULL


.AP_PRIMARY <- "#2c7be5"
.AP_FLAG    <- "#d6604d"
.AP_MUTED   <- "grey55"

.ap_theme <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = "bold", size = base_size),
      plot.subtitle    = ggplot2::element_text(colour = "grey35", size = base_size - 2),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position  = "bottom"
    )
}


# ── Collinearity heatmaps (Analyze Step 3 and the Explore report) ─────────────

# Text and tile labels shrink as the matrix grows.
.heatmap_sizes <- function(n_vars) {
  list(label = max(2, min(5, 10 - 0.6 * n_vars)),
       base  = max(9, min(16, round(18 - 0.6 * n_vars))))
}

.heatmap_base <- function(df, base_size, title) {
  ggplot2::ggplot(df, ggplot2::aes(x = .data$Var1, y = .data$Var2, fill = .data$value)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      axis.text.x  = ggplot2::element_text(angle = 45, hjust = 1),
      panel.grid   = ggplot2::element_blank()
    ) +
    ggplot2::labs(x = NULL, y = NULL, title = title)
}

.heatmap_df <- function(mat) {
  df <- as.data.frame(as.table(mat))
  names(df) <- c("Var1", "Var2", "value")
  df$value <- as.numeric(df$value)
  df
}

# Pearson r matrix from compute_collinearity()$cor_matrix.
.plot_correlation_heatmap <- function(mat, title = "Pearson Correlation Matrix") {
  sz <- .heatmap_sizes(nrow(mat))
  .heatmap_base(.heatmap_df(mat), sz$base, title) +
    ggplot2::geom_text(ggplot2::aes(label = round(.data$value, 2L)),
                       size = sz$label, color = "black") +
    ggplot2::scale_fill_gradient2(low = "#2166ac", mid = "white", high = .AP_FLAG,
                                  midpoint = 0, limits = c(-1, 1), name = "r")
}

# Cramer's V matrix from compute_collinearity()$cramers_v_mat.
.plot_cramers_heatmap <- function(mat, title = "Cram\u00e9r's V Matrix") {
  sz <- .heatmap_sizes(nrow(mat))
  .heatmap_base(.heatmap_df(mat), sz$base, title) +
    ggplot2::geom_text(ggplot2::aes(label = ifelse(is.na(.data$value), "",
                                                    round(.data$value, 2L))),
                       size = sz$label, color = "black") +
    ggplot2::scale_fill_gradient(low = "white", high = .AP_FLAG, limits = c(0, 1),
                                 na.value = "grey90", name = "V")
}


# ── Residuals ─────────────────────────────────────────────────────────────────

.plot_resid_fitted <- function(fitted, resid) {
  df <- data.frame(fitted = fitted, resid = resid)
  ggplot2::ggplot(df, ggplot2::aes(.data$fitted, .data$resid)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_point(alpha = 0.45, colour = .AP_PRIMARY) +
    ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                         colour = .AP_FLAG, linewidth = 0.8) +
    ggplot2::labs(title = "Residuals vs fitted",
                  subtitle = "Look for curvature (missed non-linearity) or a funnel (unequal variance)",
                  x = "Fitted value", y = "Residual") +
    .ap_theme()
}


# Symmetric axes so the reference line sits on the diagonal (see CLAUDE.md,
# histogram_density Q-Q).
.plot_qq <- function(x, title, subtitle = "Points should follow the line") {
  x <- x[is.finite(x)]
  n <- length(x)
  df <- data.frame(theoretical = stats::qnorm(stats::ppoints(n)), sample = sort(x))
  rng <- range(c(df$theoretical, df$sample))
  ggplot2::ggplot(df, ggplot2::aes(.data$theoretical, .data$sample)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, colour = .AP_FLAG) +
    ggplot2::geom_point(alpha = 0.55, colour = .AP_PRIMARY) +
    ggplot2::coord_cartesian(xlim = rng, ylim = rng) +
    ggplot2::labs(title = title, subtitle = subtitle,
                  x = "Theoretical quantile", y = "Sample quantile") +
    .ap_theme()
}


.plot_scale_location <- function(fitted, std) {
  df <- data.frame(fitted = fitted, root = sqrt(abs(std)))
  ggplot2::ggplot(df, ggplot2::aes(.data$fitted, .data$root)) +
    ggplot2::geom_point(alpha = 0.45, colour = .AP_PRIMARY) +
    ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                         colour = .AP_FLAG, linewidth = 0.8) +
    ggplot2::labs(title = "Scale-location",
                  subtitle = "A flat line means the residual spread is constant",
                  x = "Fitted value", y = "\u221a|standardised residual|") +
    .ap_theme()
}


# Binned residuals (Gelman & Hill): mean residual per bin of fitted
# probability with its 95% interval; most bins should include zero.
.plot_binned_residuals <- function(b) {
  b$inside <- ifelse(b$group == "yes", "Includes 0", "Excludes 0")
  ggplot2::ggplot(b, ggplot2::aes(.data$xbar, .data$ybar, colour = .data$inside)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$CI_low, ymax = .data$CI_high), width = 0) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_colour_manual(values = c("Includes 0" = .AP_PRIMARY, "Excludes 0" = .AP_FLAG),
                                 name = NULL) +
    ggplot2::labs(title = "Binned residuals",
                  subtitle = "Mean residual per bin of predicted probability; about 95% of bins should include 0",
                  x = "Predicted probability", y = "Average residual") +
    .ap_theme()
}


# Linearity: residuals against each continuous predictor. Linear models get a
# scatter with a loess line per predictor; logistic models get binned
# residuals per predictor (the raw residuals of a 0/1 outcome are two bands).
# `d` is a long data.frame(term, x, resid) or, for binned, (term, xbar, ybar,
# CI_low, CI_high, group).
.plot_linearity <- function(d, binned) {
  if (binned) {
    d$inside <- ifelse(d$group == "yes", "Includes 0", "Excludes 0")
    p <- ggplot2::ggplot(d, ggplot2::aes(.data$xbar, .data$ybar, colour = .data$inside)) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = .AP_MUTED) +
      ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$CI_low, ymax = .data$CI_high), width = 0) +
      ggplot2::geom_point(size = 1.8) +
      ggplot2::scale_colour_manual(values = c("Includes 0" = .AP_PRIMARY, "Excludes 0" = .AP_FLAG),
                                   name = NULL) +
      ggplot2::labs(subtitle = "Mean residual per bin of the predictor; a trend suggests the effect is not linear on the log-odds scale",
                    y = "Average residual")
  } else {
    p <- ggplot2::ggplot(d, ggplot2::aes(.data$x, .data$resid)) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = .AP_MUTED) +
      ggplot2::geom_point(alpha = 0.35, colour = .AP_PRIMARY) +
      ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                           colour = .AP_FLAG, linewidth = 0.8) +
      ggplot2::labs(subtitle = "The smoothed line should stay flat around 0; a curve suggests a non-linear effect",
                    y = "Residual")
  }
  p +
    ggplot2::facet_wrap(~ term, scales = "free_x") +
    ggplot2::labs(title = "Residuals vs each continuous predictor", x = NULL) +
    .ap_theme()
}


# ── Influence ─────────────────────────────────────────────────────────────────

.plot_cooks <- function(ids, cooks, threshold, n_label = 5L) {
  df <- data.frame(id = ids, idx = seq_along(cooks), cooks = cooks)
  df$above <- df$cooks > threshold
  lab <- utils::head(df[order(-df$cooks), , drop = FALSE], n_label)
  lab <- lab[lab$above, , drop = FALSE]
  ggplot2::ggplot(df, ggplot2::aes(.data$idx, .data$cooks, colour = .data$above)) +
    ggplot2::geom_segment(ggplot2::aes(xend = .data$idx, yend = 0), linewidth = 0.4) +
    ggplot2::geom_hline(yintercept = threshold, linetype = "dashed", colour = .AP_FLAG) +
    ggplot2::geom_text(data = lab, ggplot2::aes(label = .data$id), vjust = -0.5,
                       size = 3.2, colour = "grey20") +
    ggplot2::scale_colour_manual(values = c(`FALSE` = .AP_PRIMARY, `TRUE` = .AP_FLAG), guide = "none") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.1))) +
    ggplot2::labs(title = "Cook's distance",
                  subtitle = sprintf("Dashed line: 4 / n = %.3f. Labels are row IDs.", threshold),
                  x = "Observation", y = "Cook's distance") +
    .ap_theme()
}


.plot_leverage <- function(leverage, std, cooks, ids, threshold, n_label = 5L) {
  df <- data.frame(id = ids, leverage = leverage, std = std, cooks = cooks)
  df$above <- df$cooks > threshold
  lab <- utils::head(df[order(-df$cooks), , drop = FALSE], n_label)
  lab <- lab[lab$above, , drop = FALSE]
  ggplot2::ggplot(df, ggplot2::aes(.data$leverage, .data$std)) +
    ggplot2::geom_hline(yintercept = c(-2, 0, 2), linetype = c("dotted", "dashed", "dotted"),
                        colour = .AP_MUTED) +
    ggplot2::geom_point(ggplot2::aes(size = .data$cooks, colour = .data$above), alpha = 0.55) +
    ggplot2::geom_text(data = lab, ggplot2::aes(label = .data$id), vjust = -0.9,
                       size = 3.2, colour = "grey20") +
    ggplot2::scale_colour_manual(values = c(`FALSE` = .AP_PRIMARY, `TRUE` = .AP_FLAG), guide = "none") +
    ggplot2::scale_size_continuous(range = c(1, 5), guide = "none") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = 0.12)) +
    ggplot2::labs(title = "Leverage vs standardised residual",
                  subtitle = "Size = Cook's distance. Watch points far right and far from 0",
                  x = "Leverage (hat value)", y = "Standardised residual") +
    .ap_theme()
}


# ── Random effects ────────────────────────────────────────────────────────────

.plot_ranef_qq <- function(re) {
  df <- do.call(rbind, lapply(split(re, re$grpvar), function(d) {
    d <- d[order(d$condval), , drop = FALSE]
    d$theoretical <- stats::qnorm(stats::ppoints(nrow(d)))
    d
  }))
  ggplot2::ggplot(df, ggplot2::aes(.data$theoretical, .data$condval)) +
    ggplot2::geom_smooth(method = "lm", formula = y ~ x, se = FALSE,
                         colour = .AP_FLAG, linewidth = 0.6) +
    ggplot2::geom_point(colour = .AP_PRIMARY, size = 2, alpha = 0.7) +
    ggplot2::facet_wrap(~ grpvar, scales = "free") +
    ggplot2::labs(title = "Random intercepts: normal Q-Q",
                  subtitle = "Each point is one cluster's estimated intercept; points should follow the line",
                  x = "Theoretical quantile", y = "Cluster intercept") +
    .ap_theme()
}


.plot_cluster_sizes <- function(sizes) {
  sizes <- sizes[order(sizes$group, -sizes$n), , drop = FALSE]
  sizes$key <- factor(paste(sizes$group, sizes$cluster, sep = "\r"),
                      levels = rev(unique(paste(sizes$group, sizes$cluster, sep = "\r"))))
  many <- nrow(sizes) > 40L
  p <- ggplot2::ggplot(sizes, ggplot2::aes(.data$key, .data$n)) +
    ggplot2::geom_col(fill = .AP_PRIMARY, width = 0.75) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~ group, scales = "free_y") +
    ggplot2::scale_x_discrete(labels = function(x) sub(".*\r", "", x)) +
    ggplot2::labs(title = "Rows per cluster", x = NULL, y = "Rows") +
    .ap_theme()
  if (many) p <- p + ggplot2::theme(axis.text.y = ggplot2::element_blank())
  p
}


# ── Performance (Model › Performance) ──────────────────────────────────────────────────────

# Title with the set of rows it describes, e.g. "ROC curve (test set)".
.ap_title <- function(title, set_label = NULL) {
  if (is.null(set_label)) title else paste0(title, " (", set_label, ")")
}


.plot_roc <- function(roc, auc, ci, set_label = NULL, subtitle = NULL) {
  df <- data.frame(fpr = 1 - roc$specificities, tpr = roc$sensitivities)
  df <- df[order(df$fpr, df$tpr), , drop = FALSE]
  ggplot2::ggplot(df, ggplot2::aes(.data$fpr, .data$tpr)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_step(colour = .AP_PRIMARY, linewidth = 0.9) +
    ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    ggplot2::labs(title = .ap_title("ROC curve", set_label),
                  subtitle = subtitle %||% sprintf("AUC %.3f (95%% CI %.3f\u2013%.3f, DeLong)", auc, ci[1L], ci[3L]),
                  x = "1 \u2212 specificity", y = "Sensitivity") +
    .ap_theme()
}


.plot_calibration_logistic <- function(bins, set_label = NULL) {
  lim <- c(0, max(c(bins$high, bins$predicted), na.rm = TRUE))
  ggplot2::ggplot(bins, ggplot2::aes(.data$predicted, .data$observed)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$low, ymax = .data$high),
                           width = 0, colour = .AP_PRIMARY, alpha = 0.6) +
    ggplot2::geom_line(colour = .AP_PRIMARY, alpha = 0.5) +
    ggplot2::geom_point(colour = .AP_PRIMARY, size = 2.5) +
    ggplot2::coord_equal(xlim = lim, ylim = lim) +
    ggplot2::labs(title = .ap_title("Calibration by decile", set_label),
                  subtitle = "On the dashed line, predicted risk = observed risk",
                  x = "Mean predicted probability", y = "Observed proportion (95% CI)") +
    .ap_theme()
}


# Smoothed calibration curve: apparent and bootstrap bias-corrected (as
# rms::calibrate). `curve` is data.frame(predicted, apparent, corrected);
# `pred` (the apparent predictions) is drawn as a rug.
.plot_calibration_curve <- function(curve, pred, logit, outcome, set_label = NULL) {
  long <- rbind(
    data.frame(x = curve$predicted, y = curve$apparent,  line = "Apparent"),
    data.frame(x = curve$predicted, y = curve$corrected, line = "Bias-corrected")
  )
  long <- long[is.finite(long$y), , drop = FALSE]
  rug  <- data.frame(x = if (length(pred) > 2000L) pred[seq(1L, length(pred), length.out = 2000L)] else pred)
  lim  <- range(c(curve$predicted, long$y), na.rm = TRUE)
  if (logit) lim <- c(max(0, lim[1L]), min(1, lim[2L]))
  ggplot2::ggplot(long, ggplot2::aes(.data$x, .data$y, colour = .data$line, linetype = .data$line)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_rug(data = rug, ggplot2::aes(x = .data$x), inherit.aes = FALSE,
                      sides = "b", alpha = 0.15, colour = .AP_MUTED) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::scale_colour_manual(values = c(Apparent = .AP_MUTED, `Bias-corrected` = .AP_PRIMARY), name = NULL) +
    ggplot2::scale_linetype_manual(values = c(Apparent = "dotted", `Bias-corrected` = "solid"), name = NULL) +
    ggplot2::coord_cartesian(xlim = lim, ylim = lim) +
    ggplot2::labs(title = .ap_title("Calibration curve", set_label),
                  subtitle = "Smoothed (lowess); on the dashed line, predicted = observed",
                  x = if (logit) "Predicted probability" else "Predicted value",
                  y = if (logit) "Observed proportion" else sprintf("Observed %s", outcome)) +
    .ap_theme() +
    ggplot2::theme(legend.position = "bottom")
}


.plot_predicted_probs <- function(pred, outcome_factor, set_label = NULL) {
  df <- data.frame(pred = pred, group = outcome_factor)
  ggplot2::ggplot(df, ggplot2::aes(.data$pred, fill = .data$group)) +
    ggplot2::geom_histogram(bins = 30, alpha = 0.6, position = "identity", colour = NA) +
    ggplot2::scale_fill_manual(values = c(.AP_MUTED, .AP_PRIMARY), name = "Observed outcome") +
    ggplot2::labs(title = .ap_title("Predicted probabilities", set_label),
                  subtitle = "Less overlap = better separation of events from non-events",
                  x = "Predicted probability", y = "Rows") +
    .ap_theme()
}


.plot_observed_predicted <- function(pred, y, outcome, set_label = NULL) {
  df  <- data.frame(pred = pred, y = y)
  rng <- range(c(pred, y), na.rm = TRUE)
  ggplot2::ggplot(df, ggplot2::aes(.data$pred, .data$y)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_point(alpha = 0.45, colour = .AP_PRIMARY) +
    ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                         colour = .AP_FLAG, linewidth = 0.8) +
    ggplot2::coord_cartesian(xlim = rng, ylim = rng) +
    ggplot2::labs(title = .ap_title("Observed vs predicted", set_label),
                  subtitle = "The smoothed line should follow the dashed diagonal",
                  x = "Predicted value", y = sprintf("Observed %s", outcome)) +
    .ap_theme()
}


# ── Model › Results: forest plot ───────────────────────────────────────────────────────

#' Forest plot of the adjusted estimates
#'
#' Three aligned panels (patchwork): labels | estimates with 95% CIs |
#' "OR (95% CI)" and p. Built from \code{build_results_table()} so the plot
#' shows exactly the numbers in the table. Logistic models use a log-scale OR
#' axis with a reference line at 1; linear models a line at 0. The exposure is
#' highlighted.
#'
#' @param tbl Output of \code{build_results_table()}.
#' @return A patchwork object; \code{attr(, "n_rows")} is the number of rows
#'   (for choosing a plot height).
#' @export
build_forest_plot <- function(tbl) {
  logit   <- identical(attr(tbl, "measure"), "OR")
  measure <- attr(tbl, "measure")
  n  <- nrow(tbl)
  df <- tbl
  df$y     <- rev(seq_len(n))
  df$shown <- df$row_type %in% c("level", "continuous") & !is.na(df$adj_est)
  df$label_x <- ifelse(df$row_type %in% c("level", "reference"), 0.06, 0)
  df$face  <- ifelse(df$is_exposure & df$row_type %in% c("header", "continuous"), "bold",
               ifelse(df$row_type == "reference", "italic", "plain"))
  df$colour <- ifelse(df$is_exposure, .AP_PRIMARY, "grey25")
  df$ci_txt <- ifelse(df$row_type == "reference", "Reference",
               ifelse(df$shown, edark_format_ci(df$adj_est, df$adj_low, df$adj_high), ""))
  df$p_txt  <- ifelse(df$shown, edark_format_p(df$adj_p), "")

  ylim  <- c(0.5, n + 1.2)
  blank <- ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(4, 2, 4, 2))
  header <- function(x, text, hjust) {
    ggplot2::annotate("text", x = x, y = n + 1, label = text, hjust = hjust,
                      fontface = "bold", size = 3.6)
  }

  # Row stripes to guide the eye across panels
  stripes <- df[df$y %% 2 == 0, , drop = FALSE]
  stripe_layer <- function() {
    ggplot2::geom_rect(data = stripes, ggplot2::aes(ymin = .data$y - 0.5, ymax = .data$y + 0.5),
                       xmin = -Inf, xmax = Inf, fill = "grey95", inherit.aes = FALSE)
  }

  p_lab <- ggplot2::ggplot(df, ggplot2::aes(y = .data$y)) +
    stripe_layer() +
    ggplot2::geom_text(ggplot2::aes(x = .data$label_x, label = .data$label, fontface = .data$face),
                       hjust = 0, size = 3.6, colour = "grey15") +
    header(0, "Variable", 0) +
    ggplot2::scale_x_continuous(limits = c(0, 1)) +
    ggplot2::scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    blank

  pts <- df[df$shown, , drop = FALSE]
  null_x <- if (logit) 1 else 0
  p_mid <- ggplot2::ggplot(pts, ggplot2::aes(x = .data$adj_est, y = .data$y)) +
    stripe_layer() +
    ggplot2::geom_vline(xintercept = null_x, linetype = "dashed", colour = "grey55") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = .data$adj_low, xmax = .data$adj_high, colour = .data$colour),
                           width = 0.25, linewidth = 0.6, orientation = "y") +
    ggplot2::geom_point(ggplot2::aes(colour = .data$colour), shape = 15, size = 2.6) +
    ggplot2::scale_colour_identity() +
    ggplot2::scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    ggplot2::labs(x = if (logit) "Odds ratio (95% CI, log scale)" else sprintf("%s (95%% CI)", measure),
                  y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(axis.text.y = ggplot2::element_blank(), panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.x = ggplot2::element_text(size = 10),
                   panel.grid.minor = ggplot2::element_blank(),
                   plot.margin = ggplot2::margin(4, 6, 4, 6))
  if (logit) p_mid <- p_mid + ggplot2::scale_x_log10()

  p_txt <- ggplot2::ggplot(df, ggplot2::aes(y = .data$y)) +
    stripe_layer() +
    ggplot2::geom_text(ggplot2::aes(x = 0, label = .data$ci_txt,
                                    fontface = ifelse(.data$row_type == "reference", "italic", "plain")),
                       hjust = 0, size = 3.5, colour = "grey15") +
    ggplot2::geom_text(ggplot2::aes(x = 1, label = .data$p_txt), hjust = 1, size = 3.5, colour = "grey15") +
    header(0, sprintf("%s (95%% CI)", measure), 0) +
    header(1, "p", 1) +
    ggplot2::scale_x_continuous(limits = c(0, 1)) +
    ggplot2::scale_y_continuous(limits = ylim, expand = c(0, 0)) +
    blank

  out <- patchwork::wrap_plots(p_lab, p_mid, p_txt, nrow = 1, widths = c(1.1, 1.6, 1.1))
  attr(out, "n_rows") <- n
  out
}
