#' Build a summary statistics table for a single variable
#'
#' Returns a one-row `data.frame` with descriptive statistics appropriate
#' for the variable's type. This is displayed as a `reactable` table in the
#' Explore stage alongside the plot.
#'
#' **Numeric variables** — n, missing, missing %, mean, median, SD, IQR,
#' min, max, skewness, kurtosis.
#'
#' **Factor / character variables** — n, missing, missing %, unique levels,
#' most common level (mode), mode frequency, mode %.
#'
#' **Datetime variables** — n, missing, missing %, earliest, latest, range
#' (in days).
#'
#' @param dataset A `data.frame` — the current working dataset.
#' @param variable Character. The name of the column to summarise.
#' @param column_type Character. The EDARK type string for `variable`:
#'   one of `"numeric"`, `"factor"`, `"datetime"`, `"character"`.
#'
#' @return A `data.frame` with one row and named columns appropriate for the
#'   variable type.
#'
#' @export
build_variable_summary <- function(dataset, variable, column_type) {
  stopifnot(is.data.frame(dataset), variable %in% names(dataset))
  stopifnot(column_type %in% c("numeric", "factor", "datetime", "character"))

  x       <- dataset[[variable]]
  n_total <- length(x)
  n_miss  <- sum(is.na(x))
  pct_miss <- round(100 * n_miss / n_total, 1)

  if (column_type == "numeric") {
    vals <- x[!is.na(x)]
    data.frame(
      Variable    = variable,
      Type        = "numeric",
      N           = n_total,
      Missing     = n_miss,
      Missing_pct = pct_miss,
      Mean        = round(mean(vals), 3),
      Median      = round(median(vals), 3),
      SD          = round(sd(vals), 3),
      IQR         = round(IQR(vals), 3),
      Min         = round(min(vals), 3),
      Max         = round(max(vals), 3),
      Skewness    = round(e1071::skewness(vals), 3),
      Kurtosis    = round(e1071::kurtosis(vals), 3),
      stringsAsFactors = FALSE
    )

  } else if (column_type %in% c("factor", "character")) {
    vals        <- x[!is.na(x)]
    tbl         <- sort(table(vals), decreasing = TRUE)
    mode_val    <- names(tbl)[1]
    mode_n      <- as.integer(tbl[1])
    mode_pct    <- round(100 * mode_n / length(vals), 1)
    n_unique    <- length(unique(vals))
    data.frame(
      Variable    = variable,
      Type        = column_type,
      N           = n_total,
      Missing     = n_miss,
      Missing_pct = pct_miss,
      Unique      = n_unique,
      Mode        = mode_val,
      Mode_n      = mode_n,
      Mode_pct    = mode_pct,
      stringsAsFactors = FALSE
    )

  } else {  # datetime
    vals     <- x[!is.na(x)]
    earliest <- min(vals)
    latest   <- max(vals)
    range_d  <- as.numeric(difftime(latest, earliest, units = "days"))
    data.frame(
      Variable    = variable,
      Type        = "datetime",
      N           = n_total,
      Missing     = n_miss,
      Missing_pct = pct_miss,
      Earliest    = format(earliest, "%Y-%m-%d"),
      Latest      = format(latest,   "%Y-%m-%d"),
      Range_days  = round(range_d, 0),
      stringsAsFactors = FALSE
    )
  }
}
