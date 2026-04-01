#' Detect the EDARK type of each column in a dataset
#'
#' Returns a named character vector mapping each column name to one of four
#' EDARK type strings: `"numeric"`, `"factor"`, `"datetime"`, `"character"`.
#' This vector is stored in `shared_state$column_types` and drives all plot
#' routing and UI dropdown population throughout the app.
#'
#' Detection rules (first match wins):
#' - `POSIXct` / `POSIXlt` / `Date` → `"datetime"`
#' - `factor` / `ordered` → `"factor"`
#' - `numeric` / `integer` / `double` → `"numeric"`
#' - Everything else → `"character"`
#'
#' @param dataset A `data.frame` or `tibble`.
#'
#' @return A named character vector, one element per column, with values in
#'   `c("numeric", "factor", "datetime", "character")`.
#'
#' @export
#' @examples
#' df <- data.frame(
#'   age    = c(30, 45, 60),
#'   group  = factor(c("A", "B", "A")),
#'   date   = as.POSIXct(c("2024-01-01", "2024-02-01", "2024-03-01")),
#'   notes  = c("good", "ok", "bad"),
#'   stringsAsFactors = FALSE
#' )
#' detect_column_types(df)
#' # age → "numeric", group → "factor", date → "datetime", notes → "character"
detect_column_types <- function(dataset) {
  stopifnot(is.data.frame(dataset))

  type_for_column <- function(x) {
    if (inherits(x, c("POSIXct", "POSIXlt", "Date"))) return("datetime")
    if (is.factor(x) || is.ordered(x))               return("factor")
    if (is.numeric(x) || is.integer(x))              return("numeric")
    "character"
  }

  types <- vapply(dataset, type_for_column, character(1))
  types
}
