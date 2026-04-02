# Pipeline helpers for column transformations.
# UI and server logic live in module_transform_variables.R.
# Called by apply_prepare_pipeline() in module_prepare_confirm.R.


# Apply all staged column-transform specs to a dataset.
.apply_column_transforms <- function(dataset, transforms) {
  if (length(transforms) == 0) return(dataset)

  for (col in names(transforms)) {
    if (!col %in% names(dataset)) next
    spec <- transforms[[col]]
    x    <- dataset[[col]]

    if (identical(spec$method, "auto")) {
      lvls           <- sort(unique(x[!is.na(x)]))
      dataset[[col]] <- factor(x, levels = lvls, ordered = TRUE)

    } else {
      breaks <- spec$breakpoints
      if (is.null(breaks) || length(breaks) == 0) next

      x_min       <- min(x, na.rm = TRUE)
      x_max       <- max(x, na.rm = TRUE)
      breaks_use  <- sort(breaks[breaks > x_min & breaks < x_max])
      if (length(breaks_use) == 0) {
        warning("No breakpoints fall within the range of '", col,
                "' (", round(x_min, 2), " \u2013 ", round(x_max, 2),
                "). Column left unchanged.")
        next
      }
      breaks_full <- c(-Inf, breaks_use, Inf)
      n_bins      <- length(breaks_full) - 1L

      labels <- spec$labels
      if (is.null(labels) || length(labels) == 0 || length(labels) != n_bins)
        labels <- .make_range_labels(breaks_use)

      dataset[[col]] <- cut(x,
        breaks         = breaks_full,
        labels         = labels,
        include.lowest = TRUE,
        right          = FALSE,
        ordered_result = TRUE
      )
    }
  }
  dataset
}


# Build a preview data frame — only used when method = "auto".
# For cut-points the preview is removed from the UI.
.build_transform_preview <- function(spec, x_vals) {
  if (!identical(spec$method, "auto")) return(NULL)
  data.frame(
    Original_value = as.character(x_vals),
    New_level      = as.character(seq_along(x_vals)),
    stringsAsFactors = FALSE
  )
}


# Generate human-readable range labels from a vector of breakpoints.
# e.g. breaks = c(25, 40) → c("< 25", "25 – < 40", "≥ 40")
.make_range_labels <- function(breaks) {
  breaks <- sort(breaks)
  n_bins <- length(breaks) + 1L

  fmt <- function(x) {
    if (x == round(x)) {
      # Integer-valued: no decimal point
      formatC(x, format = "d", big.mark = ",")
    } else {
      # Decimal: trim trailing zeros manually
      s <- formatC(x, format = "f", digits = 2)
      sub("\\.?0+$", "", s)
    }
  }

  labels <- character(n_bins)
  labels[1]      <- paste0("< ",     fmt(breaks[1]))
  labels[n_bins] <- paste0("\u2265 ", fmt(breaks[length(breaks)]))

  if (n_bins > 2) {
    for (i in seq(2, n_bins - 1)) {
      labels[i] <- paste0(fmt(breaks[i - 1]), " \u2013 < ", fmt(breaks[i]))
    }
  }
  labels
}


# Check whether a staged transform spec is valid (ready to apply).
# Returns TRUE if valid, FALSE if it needs user attention.
.transform_spec_is_valid <- function(spec, x) {
  if (identical(spec$method, "auto")) return(TRUE)

  breaks <- spec$breakpoints
  if (is.null(breaks) || length(breaks) == 0) return(FALSE)

  x_min      <- min(x, na.rm = TRUE)
  x_max      <- max(x, na.rm = TRUE)
  breaks_use <- breaks[breaks > x_min & breaks < x_max]
  length(breaks_use) > 0
}
