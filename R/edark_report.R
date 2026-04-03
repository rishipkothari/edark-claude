#' Generate an EDARK report without launching the GUI
#'
#' Programmatic API for report generation. Accepts a raw data frame, applies
#' the same input validation and type-casting as \code{edark()}, then writes a
#' report to \code{output_path}.
#'
#' @param data A \code{data.frame}.
#' @param report_type \code{"all_vars"} (default) for an all-variables description
#'   report, or \code{"primary_vs_others"} for a bivariate primary-vs-all report.
#' @param variables Character vector of column names to include. Defaults to all
#'   columns.
#' @param primary_variable For \code{report_type = "primary_vs_others"}: the name
#'   of the primary variable.
#' @param primary_role \code{"exposure"} (default) or \code{"outcome"}. Controls
#'   axis assignment for bivariate plots.
#' @param stratify_variable Optional column name to stratify all bivariate plots.
#'   Only used when \code{report_type = "primary_vs_others"}.
#' @param report_format Output format: \code{"html"} (default), \code{"pptx"},
#'   or \code{"docx"}.
#' @param output_path Path to write the report. Defaults to
#'   \code{"edark_report.<ext>"} in the current working directory.
#' @param max_factor_levels Maximum unique values allowed for factor columns
#'   before they are treated as high-cardinality. Default \code{20}.
#'
#' @return Invisibly returns \code{output_path}.
#'
#' @examples
#' \dontrun{
#' # All-variables HTML report
#' edark_report(liver_tx, report_format = "html",
#'              output_path = tempfile(fileext = ".html"))
#'
#' # Primary vs others PowerPoint
#' edark_report(liver_tx,
#'              report_type      = "primary_vs_others",
#'              primary_variable = "age_tx",
#'              primary_role     = "exposure",
#'              report_format    = "pptx",
#'              output_path      = tempfile(fileext = ".pptx"))
#' }
#'
#' @export
edark_report <- function(data,
                          report_type       = "all_vars",
                          variables         = NULL,
                          primary_variable  = NULL,
                          primary_role      = "exposure",
                          stratify_variable = NULL,
                          report_format     = "html",
                          output_path       = NULL,
                          max_factor_levels = 20) {

  validate_input(data)
  dataset_cast <- cast_column_types(data, max_factor_levels)
  column_types <- detect_column_types(dataset_cast)

  if (is.null(variables)) variables <- names(dataset_cast)

  if (is.null(output_path)) {
    ext         <- switch(report_format, pptx = ".pptx", docx = ".docx", html = ".html",
                          stop("Unknown report_format: ", report_format))
    output_path <- file.path(getwd(), paste0("edark_report", ext))
  }

  generate_report(
    dataset           = dataset_cast,
    column_types      = column_types,
    report_type       = report_type,
    variables         = variables,
    primary_variable  = primary_variable,
    primary_role      = primary_role,
    stratify_variable = stratify_variable,
    format            = report_format,
    output_path       = output_path
  )

  message("Report written to: ", output_path)
  invisible(output_path)
}
