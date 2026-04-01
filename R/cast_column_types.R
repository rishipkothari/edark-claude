#' Auto-cast dataset columns to appropriate types
#'
#' Applies deterministic type-casting rules to a data frame at launch time.
#' Rules are applied in priority order; a column is only transformed by the
#' first rule that matches it. The original data frame is never modified —
#' a new data frame is returned.
#'
#' @param dataset A `data.frame` or `tibble`.
#' @param max_factor_levels Integer. Character columns with no more than this
#'   many unique non-NA values are converted to `factor`. Default `20`.
#'
#' @return A `data.frame` with columns cast according to the rules below:
#'
#' | Priority | Condition | Action |
#' |----------|-----------|--------|
#' | 1 | `Date` column | Convert to `POSIXct` at midnight UTC |
#' | 2 | `logical` column | Convert to `factor` with levels `FALSE`, `TRUE` |
#' | 3 | `character` column where all non-NA values parse as numeric | Convert to `numeric` |
#' | 4 | `character` column with ≤ `max_factor_levels` unique non-NA values | Convert to `factor` |
#' | 5 | Anything else | Leave unchanged |
#'
#' @export
#' @examples
#' df <- data.frame(
#'   a = as.Date("2024-01-01"),
#'   b = TRUE,
#'   c = c("1.5", "2.0", "3.1"),
#'   d = c("low", "high", "low"),
#'   e = 42L,
#'   stringsAsFactors = FALSE
#' )
#' cast_column_types(df)
cast_column_types <- function(dataset, max_factor_levels = 20) {
  stopifnot(is.data.frame(dataset))
  stopifnot(is.numeric(max_factor_levels), max_factor_levels >= 1)

  result <- dataset

  for (col in names(result)) {
    x <- result[[col]]

    # Priority 1: Date → POSIXct at midnight UTC
    if (inherits(x, "Date")) {
      result[[col]] <- as.POSIXct(as.character(x), tz = "UTC")
      next
    }

    # Priority 2: logical → factor(FALSE, TRUE)
    if (is.logical(x)) {
      result[[col]] <- factor(x, levels = c("FALSE", "TRUE"))
      next
    }

    # Priority 3: character where every non-NA value parses as numeric → numeric
    if (is.character(x)) {
      non_na <- x[!is.na(x)]
      if (length(non_na) > 0 && all(!is.na(suppressWarnings(as.numeric(non_na))))) {
        result[[col]] <- as.numeric(x)
        next
      }
    }

    # Priority 4: character with few enough unique values → factor
    if (is.character(x)) {
      n_unique <- length(unique(x[!is.na(x)]))
      if (n_unique <= max_factor_levels) {
        result[[col]] <- as.factor(x)
        next
      }
    }

    # Priority 5: leave unchanged
  }

  result
}
