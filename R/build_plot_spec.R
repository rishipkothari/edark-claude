#' Build a plot specification for a univariate (single-variable) plot
#'
#' Constructs a named list describing everything `render_plot()` needs to
#' draw the plot. Does not touch the data or produce any graphics.
#' Called when the user clicks "Describe" in the Explore stage.
#'
#' @param shared_state A Shiny `reactiveValues` object containing at minimum:
#'   `primary_variable`, `primary_variable_role`, `stratify_variable`,
#'   `column_types`, `color_palette`, `show_data_labels`, `show_legend`,
#'   `legend_position`, `trend_resolution`.
#'
#' @return A named list (the plot spec) with the following elements:
#'   \describe{
#'     \item{plot_type}{Character. One of the type strings from `route_plot_type()`.}
#'     \item{column_a}{Character. Name of the X-axis column.}
#'     \item{column_b}{`NULL` for univariate plots.}
#'     \item{stratify_by}{Character or `NULL`. Name of the stratification column.}
#'     \item{color_palette}{Character. A `RColorBrewer` palette name.}
#'     \item{show_data_labels}{Logical.}
#'     \item{show_legend}{Logical.}
#'     \item{legend_position}{Character. `"right"`, `"left"`, `"top"`, or `"bottom"`.}
#'     \item{trend_resolution}{Character. One of `"Day"`, `"Week"`, `"Month"`, `"Year"`.
#'       Used only for `trend_*` plot types.}
#'   }
#'
#' @export
build_univariate_plot_spec <- function(shared_state) {
  primary  <- shiny::isolate(shared_state$primary_variable)
  role     <- shiny::isolate(shared_state$primary_variable_role)
  types    <- shiny::isolate(shared_state$column_types)
  stratify <- shiny::isolate(shared_state$stratify_variable)

  # Role determines axis assignment:
  # exposure → primary is X (column_a); outcome → primary is Y (column_b)
  # For univariate there is no secondary variable, so column_a is always primary.
  column_a_type <- types[[primary]]
  plot_type     <- route_plot_type(column_a_type, column_b_type = NULL)

  list(
    plot_type        = plot_type,
    column_a         = primary,
    column_b         = NULL,
    primary_role     = role,
    stratify_by      = stratify,
    color_palette    = shiny::isolate(shared_state$color_palette),
    show_data_labels = shiny::isolate(shared_state$show_data_labels),
    show_legend      = shiny::isolate(shared_state$show_legend),
    legend_position  = shiny::isolate(shared_state$legend_position),
    trend_resolution = shiny::isolate(shared_state$trend_resolution)
  )
}


#' Build a plot specification for a bivariate (two-variable) plot
#'
#' Like `build_univariate_plot_spec()` but also incorporates the secondary
#' variable and applies axis assignment based on the primary variable's role.
#' Called when the user clicks "Plot Correlation" in the Explore stage.
#'
#' @inheritParams build_univariate_plot_spec
#'
#' @return A named list with the same structure as `build_univariate_plot_spec()`
#'   but with `column_b` populated and `plot_type` determined from the
#'   two-variable combination.
#'
#' @export
build_bivariate_plot_spec <- function(shared_state) {
  primary   <- shiny::isolate(shared_state$primary_variable)
  secondary <- shiny::isolate(shared_state$secondary_variable)
  role      <- shiny::isolate(shared_state$primary_variable_role)
  types     <- shiny::isolate(shared_state$column_types)
  stratify  <- shiny::isolate(shared_state$stratify_variable)

  # Axis assignment from PRD §4.3:
  #   exposure → primary is X (column_a), secondary is Y (column_b)
  #   outcome  → primary is Y (column_b), secondary is X (column_a)
  if (role == "exposure") {
    column_a      <- primary
    column_b      <- secondary
    column_a_type <- types[[primary]]
    column_b_type <- types[[secondary]]
  } else {
    column_a      <- secondary
    column_b      <- primary
    column_a_type <- types[[secondary]]
    column_b_type <- types[[primary]]
  }

  plot_type <- route_plot_type(column_a_type, column_b_type)

  list(
    plot_type        = plot_type,
    column_a         = column_a,
    column_b         = column_b,
    primary_role     = role,
    stratify_by      = stratify,
    color_palette    = shiny::isolate(shared_state$color_palette),
    show_data_labels = shiny::isolate(shared_state$show_data_labels),
    show_legend      = shiny::isolate(shared_state$show_legend),
    legend_position  = shiny::isolate(shared_state$legend_position),
    trend_resolution = shiny::isolate(shared_state$trend_resolution)
  )
}
