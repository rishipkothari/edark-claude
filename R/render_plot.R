#' Render a ggplot object from a plot specification
#'
#' Takes a plot spec produced by `build_univariate_plot_spec()` or
#' `build_bivariate_plot_spec()` and the current working dataset, and returns
#' a `ggplot` object. The caller is responsible for wrapping it with
#' `plotly::ggplotly()` for interactive display, or using it directly for
#' report export.
#'
#' @param spec A named list as returned by `build_univariate_plot_spec()` or
#'   `build_bivariate_plot_spec()`.
#' @param dataset A `data.frame` — the current working dataset
#'   (`shared_state$dataset_working`).
#' @param max_factor_levels Integer. Factor columns with more unique values
#'   than this will not be plotted; a warning message is returned instead.
#'   Default `20`.
#'
#' @return A `ggplot` object, or a `ggplot` error-card if the plot cannot be
#'   generated (e.g. high-cardinality factor guard).
#'
#' @export
render_plot <- function(spec, dataset, max_factor_levels = 20) {
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

  plot_fn <- switch(spec$plot_type,
    bar_count          = .plot_bar_count,
    histogram_density  = .plot_histogram_density,
    trend_count        = .plot_trend_count,
    bar_grouped        = .plot_bar_grouped,
    violin_box         = .plot_violin_box,
    scatter_lm         = .plot_scatter_lm,
    trend_mean         = .plot_trend_mean,
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
  p <- .apply_plot_aesthetics(p, spec)
  p
}


# ── Internal helpers ──────────────────────────────────────────────────────────

# Applies shared aesthetics (legend, theme) to any finished ggplot.
.apply_plot_aesthetics <- function(p, spec) {
  p <- p + ggplot2::theme_minimal(base_size = 13)

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

# bar_count: univariate factor — horizontal bars with count + %
.plot_bar_count <- function(spec, dataset) {
  col_a    <- spec$column_a
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  # Compute counts and percentages
  df <- dataset
  df[[col_a]] <- forcats::fct_infreq(df[[col_a]])  # order by frequency

  if (!is.null(stratify)) {
    p <- ggplot2::ggplot(df, ggplot2::aes(
      y    = .data[[col_a]],
      fill = .data[[stratify]]
    )) +
      ggplot2::geom_bar(position = "dodge") +
      ggplot2::scale_fill_brewer(palette = palette, name = stratify)
  } else {
    p <- ggplot2::ggplot(df, ggplot2::aes(
      y    = .data[[col_a]],
      fill = .data[[col_a]]
    )) +
      ggplot2::geom_bar() +
      ggplot2::scale_fill_brewer(palette = palette) +
      ggplot2::theme(legend.position = "none")
  }

  if (spec$show_data_labels) {
    p <- p + ggplot2::geom_bar(stat = "count") +
      ggplot2::stat_count(
        ggplot2::aes(label = ggplot2::after_stat(count)),
        geom   = "text",
        hjust  = -0.2,
        size   = 3.5
      )
  }

  p +
    ggplot2::labs(x = "Count", y = col_a) +
    ggplot2::theme(axis.text.y = ggplot2::element_text(size = 11))
}


# histogram_density: univariate numeric — histogram + density curve + Q-Q plot
.plot_histogram_density <- function(spec, dataset) {
  col_a    <- spec$column_a
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  df <- dataset[!is.na(dataset[[col_a]]), ]

  # Histogram with density overlay
  if (!is.null(stratify)) {
    hist_p <- ggplot2::ggplot(df, ggplot2::aes(
      x    = .data[[col_a]],
      fill = .data[[stratify]]
    )) +
      ggplot2::geom_histogram(
        ggplot2::aes(y = ggplot2::after_stat(density)),
        bins = 30, alpha = 0.6, position = "identity"
      ) +
      ggplot2::geom_density(
        ggplot2::aes(colour = .data[[stratify]]),
        linewidth = 0.9
      ) +
      ggplot2::scale_fill_brewer(palette = palette, name = stratify) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify)

    # Facet if more than 3 strata (warn otherwise)
    n_strata <- nlevels(factor(df[[stratify]]))
    if (n_strata > 3) {
      hist_p <- hist_p + ggplot2::facet_wrap(~ .data[[stratify]])
    }
  } else {
    hist_p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[col_a]])) +
      ggplot2::geom_histogram(
        ggplot2::aes(y = ggplot2::after_stat(density)),
        bins = 30, fill = "#5b9bd5", alpha = 0.7
      ) +
      ggplot2::geom_density(colour = "#1f497d", linewidth = 0.9)
  }

  hist_p <- hist_p + ggplot2::labs(x = col_a, y = "Density")

  # Q-Q plot (always uses the pooled data, no stratification)
  qq_p <- ggplot2::ggplot(df, ggplot2::aes(sample = .data[[col_a]])) +
    ggplot2::stat_qq(colour = "#5b9bd5", size = 1.5, alpha = 0.6) +
    ggplot2::stat_qq_line(colour = "#1f497d", linewidth = 0.8) +
    ggplot2::labs(x = "Theoretical quantiles", y = "Sample quantiles",
                  title = "Q-Q Plot")

  # Combine side-by-side with patchwork
  hist_p + qq_p
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
      ggplot2::facet_wrap(~ .data[[stratify]])
  } else {
    df_agg <- dplyr::count(df, .data$._time)
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(x = .data$._time, y = .data$n)) +
      ggplot2::geom_line(colour = "#5b9bd5", linewidth = 0.9) +
      ggplot2::geom_point(colour = "#1f497d", size = 2)
  }

  p + ggplot2::labs(x = resolution, y = "Count", title = paste("Events over time —", col_a))
}


# bar_grouped: factor × factor — grouped (or stacked) bar chart
.plot_bar_grouped <- function(spec, dataset) {
  col_a   <- spec$column_a
  col_b   <- spec$column_b
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  p <- ggplot2::ggplot(dataset, ggplot2::aes(
    x    = .data[[col_a]],
    fill = .data[[col_b]]
  )) +
    ggplot2::geom_bar(position = "dodge") +
    ggplot2::scale_fill_brewer(palette = palette, name = col_b) +
    ggplot2::labs(x = col_a, y = "Count")

  if (!is.null(stratify)) {
    p <- p + ggplot2::facet_wrap(~ .data[[stratify]])
  }

  p
}


# violin_box: factor (X) × numeric (Y) — violin outer, box inner
.plot_violin_box <- function(spec, dataset) {
  col_a    <- spec$column_a
  col_b    <- spec$column_b
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  df <- dataset[!is.na(dataset[[col_b]]), ]

  p <- ggplot2::ggplot(df, ggplot2::aes(
    x    = .data[[col_a]],
    y    = .data[[col_b]],
    fill = .data[[col_a]]
  )) +
    ggplot2::geom_violin(alpha = 0.4, trim = FALSE) +
    ggplot2::geom_boxplot(width = 0.15, outlier.shape = 21,
                          outlier.size = 2, alpha = 0.8) +
    ggplot2::scale_fill_brewer(palette = palette) +
    ggplot2::labs(x = col_a, y = col_b)

  # Facet by stratification variable (colour already used for groups)
  if (!is.null(stratify)) {
    p <- p + ggplot2::facet_wrap(~ .data[[stratify]])
  }

  p
}


# scatter_lm: numeric × numeric — points + linear fit + Pearson r
.plot_scatter_lm <- function(spec, dataset) {
  col_a    <- spec$column_a
  col_b    <- spec$column_b
  stratify <- spec$stratify_by
  palette  <- spec$color_palette

  df <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]

  if (!is.null(stratify)) {
    p <- ggplot2::ggplot(df, ggplot2::aes(
      x      = .data[[col_a]],
      y      = .data[[col_b]],
      colour = .data[[stratify]]
    )) +
      ggplot2::geom_point(alpha = 0.6, size = 2) +
      ggplot2::geom_smooth(method = "lm", se = TRUE, linewidth = 0.8) +
      ggplot2::scale_colour_brewer(palette = palette, name = stratify) +
      ggpubr::stat_cor(ggplot2::aes(group = .data[[stratify]]),
                       method = "pearson", label.x.npc = "left")
  } else {
    p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[col_a]], y = .data[[col_b]])) +
      ggplot2::geom_point(colour = "#5b9bd5", alpha = 0.6, size = 2) +
      ggplot2::geom_smooth(method = "lm", se = TRUE,
                           colour = "#1f497d", linewidth = 0.8) +
      ggpubr::stat_cor(method = "pearson", label.x.npc = "left")
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
      ggplot2::facet_wrap(~ .data[[stratify]])
  } else {
    df_agg <- dplyr::group_by(df, .data$._time) |>
      dplyr::summarise(._mean = mean(.data[[col_b]], na.rm = TRUE), .groups = "drop")
    p <- ggplot2::ggplot(df_agg, ggplot2::aes(x = .data$._time, y = .data$._mean)) +
      ggplot2::geom_line(colour = "#5b9bd5", linewidth = 0.9) +
      ggplot2::geom_point(colour = "#1f497d", size = 2)
  }

  p + ggplot2::labs(x = resolution, y = paste("Mean", col_b))
}


# trend_proportion: datetime (X) × factor (Y) — proportion per level over time
.plot_trend_proportion <- function(spec, dataset) {
  col_a      <- spec$column_a
  col_b      <- spec$column_b
  stratify   <- spec$stratify_by
  resolution <- spec$trend_resolution
  palette    <- spec$color_palette

  floor_fn  <- .trend_floor_fn(resolution)
  df        <- dataset[!is.na(dataset[[col_a]]) & !is.na(dataset[[col_b]]), ]
  df$._time <- floor_fn(df[[col_a]])

  df_agg <- dplyr::count(df, .data$._time, .data[[col_b]]) |>
    dplyr::group_by(.data$._time) |>
    dplyr::mutate(prop = .data$n / sum(.data$n)) |>
    dplyr::ungroup()

  p <- ggplot2::ggplot(df_agg, ggplot2::aes(
    x      = .data$._time,
    y      = .data$prop,
    colour = .data[[col_b]]
  )) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_colour_brewer(palette = palette, name = col_b) +
    ggplot2::scale_y_continuous(labels = scales::percent_format()) +
    ggplot2::labs(x = resolution, y = "Proportion")

  if (!is.null(stratify)) {
    p <- p + ggplot2::facet_wrap(~ .data[[stratify]])
  }

  p
}


# ── Shared utilities ──────────────────────────────────────────────────────────

# Returns the appropriate lubridate floor function for a trend resolution string.
.trend_floor_fn <- function(resolution) {
  switch(resolution,
    Day   = function(x) lubridate::floor_date(x, "day"),
    Week  = function(x) lubridate::floor_date(x, "week"),
    Month = function(x) lubridate::floor_date(x, "month"),
    Year  = function(x) lubridate::floor_date(x, "year"),
    stop("Unknown trend_resolution: ", resolution, call. = FALSE)
  )
}
