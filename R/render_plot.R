#' Render a ggplot object from a plot specification
#'
#' Takes a plot spec produced by `build_univariate_plot_spec()` or
#' `build_bivariate_plot_spec()` and the current working dataset, and returns
#' a `ggplot` or `patchwork` object ready for `renderPlot()` or report export.
#'
#' @param spec A named list as returned by `build_univariate_plot_spec()` or
#'   `build_bivariate_plot_spec()`.
#' @param dataset A `data.frame` — the current working dataset
#'   (`shared_state$dataset_working`).
#' @param max_factor_levels Integer. Factor columns with more unique values
#'   than this will not be plotted; a warning message is returned instead.
#'   Default `20`.
#'
#' @return A `ggplot` or `patchwork` object, or a `ggplot` error-card if the
#'   plot cannot be generated (e.g. high-cardinality factor guard).
#'
#' @export
render_plot <- function(spec, dataset, max_factor_levels = 20, split_panels = FALSE) {
  stopifnot(is.list(spec), is.data.frame(dataset))

  # High-cardinality guard: check any factor column used in the spec
  factor_cols <- c(spec$column_a, spec$column_b, spec$stratify_by)
  factor_cols <- factor_cols[!is.null(factor_cols)]
  for (col in factor_cols) {
    if (is.factor(dataset[[col]])) {
      n_levels <- nlevels(dataset[[col]])
      if (n_levels > max_factor_levels) {
        return(.plot_warning_card(paste0(
          "Column '", col, "' has ", n_levels, " levels (max: ", max_factor_levels, "). ",
          "Reduce the number of levels or change the column type to plot this variable."
        )))
      }
    }
  }

  if (is.null(spec$plot_type)) {
    return(.plot_warning_card(paste0(
      "Unsupported variable type combination: cannot plot '",
      spec$column_a, "' against '",
      if (!is.null(spec$column_b)) spec$column_b else "(none)", "'."
    )))
  }

  plot_fn <- switch(spec$plot_type,
    bar_count          = .plot_bar_count,
    histogram_density  = .plot_histogram_density,
    trend_count        = .plot_trend_count,
    bar_grouped        = .plot_bar_grouped,
    violin_jitter      = .plot_violin_jitter,
    scatter_loess      = .plot_scatter_loess,
    trend_mean         = .plot_trend_mean,
    trend_numeric      = .plot_trend_numeric,
    trend_proportion   = .plot_trend_proportion,
    NULL
  )

  if (is.null(plot_fn)) {
    return(.plot_warning_card(paste0(
      "Unsupported variable type combination: cannot plot '",
      spec$column_a, "' against '",
      if (!is.null(spec$column_b)) spec$column_b else "(none)", "'."
    )))
  }

  p <- plot_fn(spec, dataset)

  # histogram_density returns an edark_two_panel intermediate; apply aesthetics
  # to each panel separately then combine into a patchwork for rendering.
  # Left (density): honours show_legend / legend_position from spec
  # Right (QQ):     legend suppressed — facet strips label each stratum
  if (inherits(p, "edark_two_panel")) {
    spec_right <- modifyList(spec, list(show_legend = FALSE))
    left_p  <- .apply_plot_aesthetics(p$left,  spec)
    right_p <- .apply_plot_aesthetics(p$right, spec_right)
    # QQ panel always gets its own descriptive title (overrides the one set by
    # .apply_plot_aesthetics) so it is self-contained in reports.
    right_p <- right_p + ggplot2::labs(title = paste("Q-Q Plot:", spec$column_a))
    if (split_panels) return(list(left_p, right_p))
    p <- patchwork::wrap_plots(left_p, right_p, widths = c(0.45, 0.55))
  } else {
    p <- .apply_plot_aesthetics(p, spec)
  }
  p
}


# ── Internal helpers ──────────────────────────────────────────────────────────

# Applies shared aesthetics (title, legend, theme) to any finished ggplot.
.apply_plot_aesthetics <- function(p, spec) {
  title <- spec$column_a
  if (!is.null(spec$column_b)) {
    title <- paste0(title, "  \u00d7  ", spec$column_b)
  }
  if (!is.null(spec$stratify_by)) {
    title <- paste0(title, "  \u00b7  stratified by ", spec$stratify_by)
  }

  p <- p +
    ggplot2::labs(title = title) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold", colour = "#444444",
                                         margin = ggplot2::margin(b = 6)),
      strip.text = ggplot2::element_text(margin = ggplot2::margin(t = 6, b = 4))
    )

  if (!spec$show_legend) {
    p <- p + ggplot2::theme(legend.position = "none")
  } else {
    p <- p + ggplot2::theme(legend.position = spec$legend_position)
  }

  p
}


# Returns a minimal ggplot that displays a warning message as text.
# Used instead of stop() so the UI can display it gracefully.
.plot_warning_card <- function(message) {
  ggplot2::ggplot() +
    ggplot2::annotate(
      "text", x = 0.5, y = 0.5,
      label = message,
      size  = 5, colour = "#b94a48",
      hjust = 0.5, vjust = 0.5,
      lineheight = 1.4
    ) +
    ggplot2::theme_void() +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
}


# ── Plot type implementations ─────────────────────────────────────────────────

# bar_count: univariate factor — vertical bars with count
.plot_bar_count <- function(spec, dataset) {
  col_a    <- spec$column_a
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  # Drop NA factor values so they neither appear as bars nor create empty axis slots
  df <- dataset[!is.na(dataset[[col_a]]), ]

  if (!is.null(stratify)) {
    # Build complete grid: every factor level gets a bar (count 0) in every
    # stratum so no level silently vanishes from a facet panel.
    all_strata <- levels(factor(df[[stratify]]))
    all_levels <- levels(factor(df[[col_a]]))

    df_counts <- dplyr::count(df, .data[[stratify]], .data[[col_a]])

    complete_grid <- expand.grid(
      s = all_strata, l = all_levels, stringsAsFactors = FALSE
    )
    names(complete_grid) <- c(stratify, col_a)

    df_counts <- dplyr::left_join(complete_grid, df_counts, by = c(stratify, col_a))
    df_counts$n[is.na(df_counts$n)] <- 0L
    df_counts[[stratify]] <- factor(df_counts[[stratify]], levels = all_strata)
    df_counts[[col_a]]    <- factor(df_counts[[col_a]],    levels = all_levels)

    # Facet by stratum; x = primary factor levels; fill = primary factor levels
    # (legend is redundant with x-axis so hidden)
    p <- ggplot2::ggplot(df_counts, ggplot2::aes(
      x    = .data[[col_a]],
      y    = .data$n,
      fill = .data[[col_a]]
    )) +
      ggplot2::geom_col() +
      ggplot2::scale_fill_brewer(palette = palette, guide = "none") +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)), scales = "fixed",
                          labeller = ggplot2::label_both) +
      ggplot2::labs(x = col_a, y = "Count") +
      ggplot2::theme(axis.text.x = ggplot2::element_text(size = 11))

    if (spec$show_data_labels) {
      p <- p + ggplot2::geom_text(
        ggplot2::aes(label = .data$n),
        vjust = -0.3,
        size  = 3.5
      )
    }
  } else {
    # Keep natural factor level order — do not reorder by frequency
    p <- ggplot2::ggplot(df, ggplot2::aes(
      x    = .data[[col_a]],
      fill = .data[[col_a]]
    )) +
      ggplot2::geom_bar() +
      ggplot2::scale_fill_brewer(palette = palette, guide = "none") +
      ggplot2::labs(x = col_a, y = "Count") +
      ggplot2::theme(axis.text.x = ggplot2::element_text(size = 11))

    if (spec$show_data_labels) {
      p <- p + ggplot2::stat_count(
        ggplot2::aes(label = ggplot2::after_stat(count)),
        geom  = "text",
        vjust = -0.3,
        size  = 3.5
      )
    }
  }

  p
}


# histogram_density: univariate numeric — two panels returned as edark_two_panel
#
# No stratify:   left = histogram + density overlay  |  right = pooled QQ
# With stratify: left = overlapping density curves   |  right = QQ faceted by
#                       (one per stratum, no bars)           stratum, ncol =
#                                                            ceiling(sqrt(n))
#
# Returns an edark_two_panel intermediate (left + right ggplots) so that
# render_plot() can apply aesthetics per-panel before combining into a patchwork.
.plot_histogram_density <- function(spec, dataset) {
  col_a    <- spec$column_a
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  df <- dataset[!is.na(dataset[[col_a]]), ]

  if (!is.null(stratify)) {
    n_strata <- nlevels(factor(df[[stratify]]))
    qq_ncol  <- ceiling(sqrt(n_strata))

    # ── Left: overlapping density curves, one per stratum (no histogram bars) ─
    left_p <- ggplot2::ggplot(df, ggplot2::aes(
      x      = .data[[col_a]],
      colour = .data[[stratify]],
      fill   = .data[[stratify]]
    )) +
      ggplot2::geom_density(linewidth = 0.9, alpha = 0.15) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify) +
      ggplot2::scale_fill_brewer(palette = palette, name = stratify) +
      ggplot2::labs(x = col_a, y = "Density")

    # ── Right: QQ faceted by stratum, ceiling(sqrt(n)) columns ────────────────
    df_qq       <- df
    df_qq$z_std <- ave(
      df[[col_a]], df[[stratify]],
      FUN = function(x) as.numeric(scale(x))
    )

    # Both axes use the same limits so the 45° reference line is interpretable.
    # Range covers both the sample z-scores and the expected theoretical quantiles.
    z_range  <- range(df_qq$z_std, na.rm = TRUE)
    q_theor  <- range(qnorm(ppoints(nrow(df_qq))))
    ax_range <- range(c(z_range, q_theor))
    ax_pad   <- diff(ax_range) * 0.05

    right_p <- ggplot2::ggplot(df_qq, ggplot2::aes(
      sample = .data$z_std,
      colour = .data[[stratify]]
    )) +
      ggplot2::stat_qq(size = 1.5, alpha = 0.6) +
      ggplot2::stat_qq_line(linewidth = 0.8) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify) +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)), ncol = qq_ncol,
                          scales = "fixed", labeller = ggplot2::label_both) +
      ggplot2::coord_cartesian(xlim = ax_range + c(-ax_pad, ax_pad),
                               ylim = ax_range + c(-ax_pad, ax_pad)) +
      ggplot2::labs(x = "Theoretical quantiles",
                    y = "Standardised sample quantiles") +
      ggplot2::theme(legend.position = "none")
  } else {
    # ── Left: histogram + density overlay ─────────────────────────────────────
    # Primary Y axis is count; density curve is scaled to count units.
    # Secondary Y axis shows the density scale via inverse transform.
    n_obs <- nrow(df)
    bw    <- diff(range(df[[col_a]], na.rm = TRUE)) / 30

    left_p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[col_a]])) +
      ggplot2::geom_histogram(bins = 30, fill = "#5b9bd5", alpha = 0.7) +
      ggplot2::geom_density(
        ggplot2::aes(y = ggplot2::after_stat(density) * n_obs * bw),
        colour = "#1f497d", linewidth = 0.9
      ) +
      ggplot2::scale_y_continuous(
        name     = "Count",
        sec.axis = ggplot2::sec_axis(~ . / (n_obs * bw), name = "Density")
      ) +
      ggplot2::labs(x = col_a)

    # ── Right: QQ (pooled) ────────────────────────────────────────────────────
    # Both axes use the same limits so the 45° reference line is interpretable.
    df_qq    <- data.frame(z = as.numeric(scale(df[[col_a]])))
    z_range  <- range(df_qq$z, na.rm = TRUE)
    q_theor  <- range(qnorm(ppoints(nrow(df_qq))))
    ax_range <- range(c(z_range, q_theor))
    ax_pad   <- diff(ax_range) * 0.05
    right_p <- ggplot2::ggplot(df_qq, ggplot2::aes(sample = .data$z)) +
      ggplot2::stat_qq(colour = "#5b9bd5", size = 1.5, alpha = 0.6) +
      ggplot2::stat_qq_line(colour = "#1f497d", linewidth = 0.8) +
      ggplot2::coord_cartesian(xlim = ax_range + c(-ax_pad, ax_pad),
                               ylim = ax_range + c(-ax_pad, ax_pad)) +
      ggplot2::labs(x = "Theoretical quantiles",
                    y = "Standardised sample quantiles")
  }

  structure(list(left = left_p, right = right_p), class = "edark_two_panel")
}


# trend_count: univariate datetime — event counts over time
.plot_trend_count <- function(spec, dataset) {
  col_a      <- spec$column_a
  stratify   <- spec$stratify_by
  resolution <- spec$trend_resolution
  palette    <- spec$color_palette

  floor_fn <- .trend_floor_fn(resolution)
  df        <- dataset[!is.na(dataset[[col_a]]), ]
  df$._time <- floor_fn(df[[col_a]])

  if (!is.null(stratify)) {
    df_agg <- dplyr::count(df, .data$._time, .data[[stratify]])
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(
      x      = .data$._time,
      y      = .data$n,
      colour = .data[[stratify]]
    )) +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify) +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)),
                          labeller = ggplot2::label_both)
  } else {
    df_agg <- dplyr::count(df, .data$._time)
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(x = .data$._time, y = .data$n)) +
      ggplot2::geom_line(colour = "#5b9bd5", linewidth = 0.9) +
      ggplot2::geom_point(colour = "#1f497d", size = 2)
  }

  p + ggplot2::labs(x = resolution, y = "Count")
}


# bar_grouped: factor × factor — grouped bar chart
# Pre-computes a complete grid (every col_a × col_b combination) so that
# missing combinations appear as zero-height bars rather than being absent,
# which would otherwise cause remaining bars to expand to double width.
.plot_bar_grouped <- function(spec, dataset) {
  col_a    <- spec$column_a
  col_b    <- spec$column_b
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  all_x    <- levels(factor(dataset[[col_a]]))
  all_fill <- levels(factor(dataset[[col_b]]))

  if (!is.null(stratify)) {
    all_strata <- levels(factor(dataset[[stratify]]))
    df_counts  <- dplyr::count(dataset, .data[[stratify]], .data[[col_a]], .data[[col_b]])

    complete_grid <- expand.grid(s = all_strata, a = all_x, b = all_fill,
                                 stringsAsFactors = FALSE)
    names(complete_grid) <- c(stratify, col_a, col_b)
    df_counts <- dplyr::left_join(complete_grid, df_counts, by = c(stratify, col_a, col_b))
    df_counts$n[is.na(df_counts$n)] <- 0L
    df_counts[[stratify]] <- factor(df_counts[[stratify]], levels = all_strata)
    df_counts[[col_a]]    <- factor(df_counts[[col_a]],    levels = all_x)
    df_counts[[col_b]]    <- factor(df_counts[[col_b]],    levels = all_fill)

    p <- ggplot2::ggplot(df_counts, ggplot2::aes(
      x    = .data[[col_a]],
      y    = .data$n,
      fill = .data[[col_b]]
    )) +
      ggplot2::geom_col(position = "dodge") +
      ggplot2::scale_fill_brewer(palette = palette, name = col_b) +
      ggplot2::labs(x = col_a, y = "Count") +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)), scales = "fixed",
                          ncol     = ceiling(sqrt(length(all_strata))),
                          labeller = ggplot2::label_both)
  } else {
    df_counts <- dplyr::count(dataset, .data[[col_a]], .data[[col_b]])

    complete_grid <- expand.grid(a = all_x, b = all_fill, stringsAsFactors = FALSE)
    names(complete_grid) <- c(col_a, col_b)
    df_counts <- dplyr::left_join(complete_grid, df_counts, by = c(col_a, col_b))
    df_counts$n[is.na(df_counts$n)] <- 0L
    df_counts[[col_a]] <- factor(df_counts[[col_a]], levels = all_x)
    df_counts[[col_b]] <- factor(df_counts[[col_b]], levels = all_fill)

    p <- ggplot2::ggplot(df_counts, ggplot2::aes(
      x    = .data[[col_a]],
      y    = .data$n,
      fill = .data[[col_b]]
    )) +
      ggplot2::geom_col(position = "dodge") +
      ggplot2::scale_fill_brewer(palette = palette, name = col_b) +
      ggplot2::labs(x = col_a, y = "Count")
  }

  p
}


# violin_jitter: factor (X) × numeric (Y) — violin outer, jittered points + median marker
# col_a is always the factor; col_b is always numeric (normalised in build_bivariate_plot_spec).
# NA factor levels are made explicit so they appear labelled on the X-axis.
# Legend is always suppressed — X-axis labels and facet strips make it redundant.
.plot_violin_jitter <- function(spec, dataset) {
  col_a    <- spec$column_a   # factor
  col_b    <- spec$column_b   # numeric
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  df <- dataset[!is.na(dataset[[col_b]]), ]

  # Make NA factor levels explicit so they appear labelled on the X-axis
  if (anyNA(df[[col_a]])) {
    df[[col_a]] <- addNA(df[[col_a]])
    lvls <- levels(df[[col_a]])
    lvls[is.na(lvls)] <- "NA"
    levels(df[[col_a]]) <- lvls
  }

  p <- ggplot2::ggplot(df, ggplot2::aes(
    x    = .data[[col_a]],
    y    = .data[[col_b]],
    fill = .data[[col_a]]
  )) +
    ggplot2::geom_violin(alpha = 0.4, trim = FALSE) +
    ggplot2::geom_jitter(
      ggplot2::aes(colour = .data[[col_a]]),
      width = 0.15, alpha = 0.4, size = 1.5
    ) +
    ggplot2::stat_summary(
      fun = median, geom = "point",
      shape = 21, size = 3, fill = "white", colour = "black", stroke = 1.2
    ) +
    ggplot2::scale_fill_brewer(palette = palette, guide = "none") +
    ggplot2::scale_colour_brewer(palette = palette, guide = "none") +
    ggplot2::labs(x = col_a, y = col_b)

  if (!is.null(stratify)) {
    n_strata  <- nlevels(factor(df[[stratify]]))
    ncol_wrap <- ceiling(sqrt(n_strata))
    p <- p + ggplot2::facet_wrap(as.formula(paste("~", stratify)), scales = "fixed",
                                  ncol = ncol_wrap, labeller = ggplot2::label_both)
  }

  p
}


# scatter_loess: numeric × numeric — points + loess smoother + correlation stats
# Correlation label shows R², r, and p as plain text (not plotmath).
# ggpubr::stat_cor is intentionally NOT used — its plotmath output renders as
# raw expression strings rather than formatted text.
# Stratified: colour per stratum, faceted with ceiling(sqrt(n)) columns.
.plot_scatter_loess <- function(spec, dataset) {
  col_a    <- spec$column_a
  col_b    <- spec$column_b
  stratify <- spec$stratify_by

  df <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]

  # Compute Pearson r, R², p and format as a plain string.
  .cor_label <- function(x, y) {
    ct    <- cor.test(x, y, method = "pearson")
    r_val <- as.numeric(ct$estimate)
    sprintf("R\u00b2 = %.2f   r = %.2f   p = %.3g", r_val^2, r_val, ct$p.value)
  }

  if (!is.null(stratify)) {
    palette   <- spec$color_palette
    n_strata  <- nlevels(factor(df[[stratify]]))
    ncol_wrap <- ceiling(sqrt(n_strata))

    # Per-stratum labels — top-left corner, left-justified.
    x_rng <- range(df[[col_a]], na.rm = TRUE)
    y_rng <- range(df[[col_b]], na.rm = TRUE)

    cor_df <- dplyr::group_by(df, .data[[stratify]]) |>
      dplyr::summarise(
        label  = .cor_label(.data[[col_a]], .data[[col_b]]),
        x_pos  = x_rng[2] - 0.02 * diff(x_rng),
        y_pos  = y_rng[2] - 0.04 * diff(y_rng),
        .groups = "drop"
      )

    p <- ggplot2::ggplot(df, ggplot2::aes(
      x      = .data[[col_a]],
      y      = .data[[col_b]],
      colour = .data[[stratify]]
    )) +
      ggplot2::geom_point(alpha = 0.6, size = 2) +
      ggplot2::geom_smooth(method = "loess", se = TRUE, linewidth = 0.8) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify, guide = "none") +
      ggplot2::geom_label(
        data        = cor_df,
        ggplot2::aes(x = x_pos, y = y_pos, label = label),
        size        = 3, colour = "grey30", hjust = 1,
        fill        = "white", label.colour = "#cccccc", label.size = 0.3,
        label.padding = ggplot2::unit(0.3, "lines"),
        inherit.aes = FALSE
      ) +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)), scales = "fixed",
                          ncol = ncol_wrap, labeller = ggplot2::label_both)
  } else {
    label <- .cor_label(df[[col_a]], df[[col_b]])
    x_rng <- range(df[[col_a]], na.rm = TRUE)
    y_rng <- range(df[[col_b]], na.rm = TRUE)
    x_pos <- x_rng[2] - 0.02 * diff(x_rng)
    y_pos <- y_rng[2] - 0.04 * diff(y_rng)
    label_df <- data.frame(x_pos = x_pos, y_pos = y_pos, label = label)

    p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[col_a]], y = .data[[col_b]])) +
      ggplot2::geom_point(colour = "#5b9bd5", alpha = 0.6, size = 2) +
      ggplot2::geom_smooth(method = "loess", se = TRUE,
                           colour = "#1f497d", linewidth = 0.8) +
      ggplot2::geom_label(
        data        = label_df,
        ggplot2::aes(x = x_pos, y = y_pos, label = label),
        size        = 3.5, colour = "grey30", hjust = 1,
        fill        = "white", label.colour = "#cccccc", label.size = 0.3,
        label.padding = ggplot2::unit(0.3, "lines"),
        inherit.aes = FALSE
      )
  }

  p + ggplot2::labs(x = col_a, y = col_b)
}


# trend_mean: datetime (X) × numeric (Y) — mean over time
.plot_trend_mean <- function(spec, dataset) {
  col_a      <- spec$column_a
  col_b      <- spec$column_b
  stratify   <- spec$stratify_by
  resolution <- spec$trend_resolution
  palette    <- spec$color_palette

  floor_fn  <- .trend_floor_fn(resolution)
  df        <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]
  df$._time <- floor_fn(df[[col_a]])

  if (!is.null(stratify)) {
    df_agg <- dplyr::group_by(df, .data$._time, .data[[stratify]]) |>
      dplyr::summarise(._mean = mean(.data[[col_b]], na.rm = TRUE), .groups = "drop")
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(
      x      = .data$._time,
      y      = .data$._mean,
      colour = .data[[stratify]]
    )) +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify) +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)),
                          labeller = ggplot2::label_both)
  } else {
    df_agg <- dplyr::group_by(df, .data$._time) |>
      dplyr::summarise(._mean = mean(.data[[col_b]], na.rm = TRUE), .groups = "drop")
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(x = .data$._time, y = .data$._mean)) +
      ggplot2::geom_line(colour = "#5b9bd5", linewidth = 0.9) +
      ggplot2::geom_point(colour = "#1f497d", size = 2)
  }

  p + ggplot2::labs(x = resolution, y = paste("Mean", col_b))
}


# trend_proportion: datetime (X) × factor (Y)
# No stratify: count per factor level per timepoint, all levels as coloured lines.
# Stratify: facet by stratum; within each facet, count per level as coloured lines.
.plot_trend_proportion <- function(spec, dataset) {
  col_a      <- spec$column_a
  col_b      <- spec$column_b
  stratify   <- spec$stratify_by
  resolution <- spec$trend_resolution
  palette    <- spec$color_palette

  floor_fn  <- .trend_floor_fn(resolution)
  df        <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]
  df$._time <- floor_fn(df[[col_a]])

  if (!is.null(stratify)) {
    # Include stratify in the count so the facet variable exists in df_agg
    df_agg <- dplyr::count(df, .data$._time, .data[[stratify]], .data[[col_b]])

    p <- ggplot2::ggplot(df_agg, ggplot2::aes(
      x      = .data$._time,
      y      = .data$n,
      colour = .data[[col_b]]
    )) +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_colour_brewer(palette = palette, name = col_b) +
      ggplot2::labs(x = resolution, y = "Count") +
      ggplot2::facet_wrap(as.formula(paste("~", stratify)),
                          labeller = ggplot2::label_both,
                          scales = "fixed",
                          ncol = ceiling(sqrt(length(unique(df[[stratify]])))))
  } else {
    df_agg <- dplyr::count(df, .data$._time, .data[[col_b]])

    p <- ggplot2::ggplot(df_agg, ggplot2::aes(
      x      = .data$._time,
      y      = .data$n,
      colour = .data[[col_b]]
    )) +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_colour_brewer(palette = palette, name = col_b) +
      ggplot2::labs(x = resolution, y = "Count")
  }

  p
}


# trend_numeric: datetime (X) × numeric (Y) — flexible summary stat with
# optional error ribbon (SD, SE, 95% CI, IQR).
.plot_trend_numeric <- function(spec, dataset) {
  col_a      <- spec$column_a
  col_b      <- spec$column_b
  stratify   <- spec$stratify_by
  resolution <- spec$trend_resolution
  palette    <- spec$color_palette
  stat       <- if (!is.null(spec$trend_summary_stat)) spec$trend_summary_stat else "mean_sd"

  floor_fn  <- .trend_floor_fn(resolution)
  df        <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]
  df$._time <- floor_fn(df[[col_a]])

  has_ribbon <- stat %in% c("mean_sd", "mean_se", "mean_ci", "median_iqr")
  y_label    <- .trend_stat_label(stat)

  # Build aggregation function based on stat
  .agg <- function(d) {
    x <- d[[col_b]]
    n <- sum(!is.na(x))
    y <- switch(stat,
      mean_sd    = mean(x, na.rm = TRUE),
      mean_se    = mean(x, na.rm = TRUE),
      mean_ci    = mean(x, na.rm = TRUE),
      median_iqr = stats::median(x, na.rm = TRUE),
      count      = as.numeric(n),
      sum        = sum(x, na.rm = TRUE),
      max        = max(x, na.rm = TRUE),
      min        = min(x, na.rm = TRUE)
    )
    if (has_ribbon) {
      bounds <- switch(stat,
        mean_sd    = { s <- stats::sd(x, na.rm = TRUE); c(y - s, y + s) },
        mean_se    = { se <- stats::sd(x, na.rm = TRUE) / sqrt(n); c(y - se, y + se) },
        mean_ci    = { ci <- stats::qt(0.975, df = max(n - 1, 1)) *
                           stats::sd(x, na.rm = TRUE) / sqrt(n); c(y - ci, y + ci) },
        median_iqr = c(stats::quantile(x, 0.25, na.rm = TRUE),
                       stats::quantile(x, 0.75, na.rm = TRUE))
      )
      data.frame(._y = y, ._ymin = bounds[[1]], ._ymax = bounds[[2]])
    } else {
      data.frame(._y = y)
    }
  }

  if (!is.null(stratify)) {
    df_agg <- dplyr::group_by(df, .data$._time, .data[[stratify]]) |>
      dplyr::group_modify(~ .agg(.x)) |>
      dplyr::ungroup()

    p <- ggplot2::ggplot(df_agg, ggplot2::aes(
      x      = .data$._time,
      y      = .data$._y,
      colour = .data[[stratify]]
    ))

    if (has_ribbon) {
      p <- p + ggplot2::geom_ribbon(
        ggplot2::aes(ymin = .data$._ymin, ymax = .data$._ymax, fill = .data[[stratify]]),
        alpha = 0.1, colour = NA
      )
    }

    p <- p +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::geom_point(size = 2) +
      ggplot2::scale_colour_brewer(palette = palette, aesthetics = c("colour", "fill"),
                                   name = stratify) +
      ggplot2::labs(x = resolution, y = y_label)
  } else {
    df_agg <- dplyr::group_by(df, .data$._time) |>
      dplyr::group_modify(~ .agg(.x)) |>
      dplyr::ungroup()

    p <- ggplot2::ggplot(df_agg, ggplot2::aes(x = .data$._time, y = .data$._y))

    if (has_ribbon) {
      p <- p + ggplot2::geom_ribbon(
        ggplot2::aes(ymin = .data$._ymin, ymax = .data$._ymax),
        alpha = 0.15, fill = "#5b9bd5"
      )
    }

    p <- p +
      ggplot2::geom_line(colour = "#5b9bd5", linewidth = 0.9) +
      ggplot2::geom_point(colour = "#1f497d", size = 2) +
      ggplot2::labs(x = resolution, y = y_label)
  }

  p
}


# Returns the Y-axis label for a trend_numeric summary stat.
.trend_stat_label <- function(stat) {
  switch(stat,
    mean_sd    = "Mean \u00b1 SD",
    mean_se    = "Mean \u00b1 SE",
    mean_ci    = "Mean \u00b1 95% CI",
    median_iqr = "Median (IQR)",
    count      = "Count",
    sum        = "Sum",
    max        = "Max",
    min        = "Min",
    stat
  )
}


# ── Shared utilities ──────────────────────────────────────────────────────────

# Returns the appropriate lubridate floor function for a trend resolution string.
.trend_floor_fn <- function(resolution) {
  switch(resolution,
    Hour    = function(x) lubridate::floor_date(x, "hour"),
    Day     = function(x) lubridate::floor_date(x, "day"),
    Week    = function(x) lubridate::floor_date(x, "week"),
    Month   = function(x) lubridate::floor_date(x, "month"),
    Quarter = function(x) lubridate::floor_date(x, "quarter"),
    Year  = function(x) lubridate::floor_date(x, "year"),
    stop("Unknown trend_resolution: ", resolution, call. = FALSE)
  )
}
