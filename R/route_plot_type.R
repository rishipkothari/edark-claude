#' Determine the plot type string from two column types
#'
#' Given the EDARK type strings for the X-axis column (`column_a`) and the
#' Y-axis column (`column_b`), returns the plot type string that `render_plot()`
#' will use to build the correct visualisation.
#'
#' `column_b_type` may be `NULL` for univariate (single-variable) plots.
#'
#' @param column_a_type Character. EDARK type of the X-axis variable.
#'   One of `"factor"`, `"numeric"`, `"datetime"`.
#' @param column_b_type Character or `NULL`. EDARK type of the Y-axis variable,
#'   or `NULL` for univariate plots.
#'
#' @return A single character string — one of:
#'   `"bar_count"`, `"histogram_density"`,
#'   `"bar_grouped"`, `"violin_jitter"`, `"scatter_loess"`,
#'   `"trend_mean"`, `"trend_factor"`.
#'   Returns `NULL` if the combination is not supported.
#'
#' @keywords internal
route_plot_type <- function(column_a_type, column_b_type = NULL) {
  # Univariate — datetime excluded (reserved for future Time-Trend feature)
  if (is.null(column_b_type)) {
    return(switch(column_a_type,
      factor  = "bar_count",
      numeric = "histogram_density",
      NULL    # datetime, character, or unknown → unsupported
    ))
  }

  # Bivariate — datetime excluded (reserved for future Time-Trend feature)
  key <- paste0(column_a_type, "|", column_b_type)
  switch(key,
    "factor|factor"   = "bar_grouped",
    "factor|numeric"  = "violin_jitter",
    "numeric|factor"  = "violin_jitter",
    "numeric|numeric" = "scatter_loess",
    NULL   # unsupported combination (includes any datetime pairing)
  )
}
