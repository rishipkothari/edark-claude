#' Validate the dataset passed to `edark()`
#'
#' Stops with a clear, human-readable error message if the input is not a
#' non-empty data frame. Called once at launch before any reactive graph
#' is constructed.
#'
#' @param dataset The object to validate.
#' @param max_factor_levels The `max_factor_levels` argument passed to
#'   `edark()`, validated here for type and range.
#'
#' @return Invisibly returns `TRUE` if all checks pass. Otherwise calls
#'   `stop()` with a descriptive message.
#'
#' @keywords internal
validate_input <- function(dataset, max_factor_levels) {
  if (!is.data.frame(dataset)) {
    stop(
      "`dataset` must be a data.frame or tibble, but you passed a ",
      class(dataset)[1], ".",
      call. = FALSE
    )
  }

  if (nrow(dataset) == 0) {
    stop("`dataset` has 0 rows. Please pass a non-empty data frame.", call. = FALSE)
  }

  if (ncol(dataset) == 0) {
    stop("`dataset` has 0 columns. Please pass a non-empty data frame.", call. = FALSE)
  }

  if (!is.numeric(max_factor_levels) || length(max_factor_levels) != 1 ||
      max_factor_levels < 1 || max_factor_levels != round(max_factor_levels)) {
    stop("`max_factor_levels` must be a single positive integer.", call. = FALSE)
  }

  invisible(TRUE)
}
