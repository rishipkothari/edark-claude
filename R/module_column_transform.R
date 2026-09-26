# Pipeline helpers for column transformations.
# UI and server logic live in module_transform_variables.R.
# Called by apply_prepare_pipeline() in module_prepare_confirm.R.


# ── Winsorize bounds ──────────────────────────────────────────────────────────
#
# The percentile pair is clamped in one place, because three callers need the
# same rule: the two numericInputs in module_transform_variables.R (typed input
# ignores a numericInput's min/max, so a box can send 0, -4 or 250),
# .apply_column_transforms() below, and the validity checks used by Apply.
#
# Lower lives in [1, 99]; upper in [lower + 1, 100]. A degenerate pair would
# hand quantile() a lower bound at or above the upper one, which silently
# flattens the column to a constant.

EDARK_WINSOR_MIN <- 1
EDARK_WINSOR_MAX <- 100

# Clamp a lower percentile into range; NULL / NA / non-numeric gives the default.
.winsor_lower <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x) != 1L || is.na(x)) return(EDARK_WINSOR_MIN)
  min(max(x, EDARK_WINSOR_MIN), EDARK_WINSOR_MAX - 1)
}

# Clamp an upper percentile into range, given the lower one it must clear.
.winsor_upper <- function(x, lower = EDARK_WINSOR_MIN) {
  lower <- .winsor_lower(lower)
  x     <- suppressWarnings(as.numeric(x))
  if (length(x) != 1L || is.na(x)) x <- EDARK_WINSOR_MAX - 1
  min(max(x, lower + 1), EDARK_WINSOR_MAX)
}


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

    } else if (identical(spec$method, "cutpoints")) {
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

    } else if (identical(spec$method, "log")) {
      base_fn <- switch(
        spec$log_base %||% "ln",
        ln    = log,
        log10 = log10,
        log2  = log2,
        log   # fallback
      )
      dataset[[col]] <- base_fn(x)

    } else if (identical(spec$method, "winsorize")) {
      # Clamp here too: a spec can arrive from edark_report() rather than from
      # the two boxes, and nothing upstream of that API checks it.
      lo_pct         <- .winsor_lower(spec$lower_pct)
      hi_pct         <- .winsor_upper(spec$upper_pct, lo_pct)
      lo             <- quantile(x, lo_pct / 100, na.rm = TRUE)
      hi             <- quantile(x, hi_pct / 100, na.rm = TRUE)
      dataset[[col]] <- pmin(pmax(x, lo), hi)

    } else if (identical(spec$method, "round")) {
      dp             <- max(0L, as.integer(spec$decimal_places %||% 0))
      dataset[[col]] <- round(x, digits = dp)

    } else if (identical(spec$method, "standardize")) {
      mu <- mean(x, na.rm = TRUE)
      s  <- sd(x,   na.rm = TRUE)
      dataset[[col]] <- if (s > 0) (x - mu) / s else x
    }
  }
  dataset
}


# Generate human-readable range labels from a vector of breakpoints.
# e.g. breaks = c(25, 40) → c("< 25", "25 – < 40", "≥ 40")
.make_range_labels <- function(breaks) {
  breaks <- sort(breaks)
  n_bins <- length(breaks) + 1L

  fmt <- function(x) {
    if (x == round(x)) {
      formatC(x, format = "d", big.mark = ",")
    } else {
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
  switch(spec$method,
    auto        = TRUE,
    standardize = TRUE,
    round       = TRUE,

    cutpoints = {
      breaks <- spec$breakpoints
      if (is.null(breaks) || length(breaks) == 0) return(FALSE)
      x_min      <- min(x, na.rm = TRUE)
      x_max      <- max(x, na.rm = TRUE)
      length(breaks[breaks > x_min & breaks < x_max]) > 0
    },

    log = {
      if (any(!is.na(x) & x <= 0)) return(FALSE)
      TRUE
    },

    winsorize = {
      lo <- spec$lower_pct %||% EDARK_WINSOR_MIN
      hi <- spec$upper_pct %||% (EDARK_WINSOR_MAX - 1)
      is.numeric(lo) && is.numeric(hi) && !is.na(lo) && !is.na(hi) &&
        lo >= EDARK_WINSOR_MIN && hi <= EDARK_WINSOR_MAX && lo < hi
    },

    TRUE  # unknown method: pass through
  )
}
