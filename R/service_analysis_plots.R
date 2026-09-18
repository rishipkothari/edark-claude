#' Analysis Plot Generation Service
#'
#' \code{ggplot2} figures for the Analysis module. Each function takes plain
#' vectors / data frames (never a Shiny object) and returns a ggplot, so the
#' same figure is shown in the app and saved by the export.
#' Phase 6: diagnostic plots. Phase 7 adds the forest plot.
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


# ── Prediction performance ────────────────────────────────────────────────────

.plot_roc <- function(roc, auc, ci) {
  df <- data.frame(fpr = 1 - roc$specificities, tpr = roc$sensitivities)
  df <- df[order(df$fpr, df$tpr), , drop = FALSE]
  ggplot2::ggplot(df, ggplot2::aes(.data$fpr, .data$tpr)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_step(colour = .AP_PRIMARY, linewidth = 0.9) +
    ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    ggplot2::labs(title = "ROC curve",
                  subtitle = sprintf("AUC %.3f (95%% CI %.3f\u2013%.3f, DeLong)", auc, ci[1L], ci[3L]),
                  x = "1 \u2212 specificity", y = "Sensitivity") +
    .ap_theme()
}


.plot_calibration_logistic <- function(bins) {
  lim <- c(0, max(c(bins$high, bins$predicted), na.rm = TRUE))
  ggplot2::ggplot(bins, ggplot2::aes(.data$predicted, .data$observed)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$low, ymax = .data$high),
                           width = 0, colour = .AP_PRIMARY, alpha = 0.6) +
    ggplot2::geom_line(colour = .AP_PRIMARY, alpha = 0.5) +
    ggplot2::geom_point(colour = .AP_PRIMARY, size = 2.5) +
    ggplot2::coord_equal(xlim = lim, ylim = lim) +
    ggplot2::labs(title = "Calibration by decile of predicted risk",
                  subtitle = "On the dashed line, predicted risk = observed risk",
                  x = "Mean predicted probability", y = "Observed proportion (95% CI)") +
    .ap_theme()
}


.plot_predicted_probs <- function(pred, outcome_factor) {
  df <- data.frame(pred = pred, group = outcome_factor)
  ggplot2::ggplot(df, ggplot2::aes(.data$pred, fill = .data$group)) +
    ggplot2::geom_histogram(bins = 30, alpha = 0.6, position = "identity", colour = NA) +
    ggplot2::scale_fill_manual(values = c(.AP_MUTED, .AP_PRIMARY), name = "Observed outcome") +
    ggplot2::labs(title = "Predicted probabilities by observed outcome",
                  subtitle = "Less overlap = better separation of events from non-events",
                  x = "Predicted probability", y = "Rows") +
    .ap_theme()
}


.plot_observed_predicted <- function(pred, y, outcome) {
  df  <- data.frame(pred = pred, y = y)
  rng <- range(c(pred, y), na.rm = TRUE)
  ggplot2::ggplot(df, ggplot2::aes(.data$pred, .data$y)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = .AP_MUTED) +
    ggplot2::geom_point(alpha = 0.45, colour = .AP_PRIMARY) +
    ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                         colour = .AP_FLAG, linewidth = 0.8) +
    ggplot2::coord_cartesian(xlim = rng, ylim = rng) +
    ggplot2::labs(title = "Observed vs predicted",
                  subtitle = "The smoothed line should follow the dashed diagonal",
                  x = "Predicted value", y = sprintf("Observed %s", outcome)) +
    .ap_theme()
}
