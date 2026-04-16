#' Analysis Export Assembly Service
#'
#' Assembles the export zip from cached \code{analysis_result} objects. No
#' recomputation occurs during export — all content is read from cache.
#' Produces the folder structure defined in PRD §10.2: methods/, results/,
#' diagnostics/, analysis report (Word or HTML), full result RDS, and
#' optionally a self-contained analysis package zip. Supports all five data
#' export formats: RDS, CSV, SPSS \code{.sav}, Stata \code{.dta}, Excel
#' \code{.xlsx}. See PRD §10.
#' Implemented in Phase 8 of the build plan.
#'
#' @name service_analysis_export
NULL
