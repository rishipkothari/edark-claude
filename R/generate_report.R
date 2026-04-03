# generate_report.R
# Core report generation logic — no Shiny dependency.
# Called by module_report.R (downloadHandler) and edark_report() programmatic API.


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------

.build_all_vars_sections <- function(dataset, column_types, variables) {
  sections <- vector("list", length(variables))
  for (i in seq_along(variables)) {
    var <- variables[[i]]
    if (!var %in% names(column_types)) next

    spec <- list(
      plot_type        = route_plot_type(column_types[[var]], NULL),
      column_a         = var,
      column_b         = NULL,
      primary_role     = "exposure",
      stratify_by      = NULL,
      color_palette    = "Set2",
      show_data_labels = FALSE,
      show_legend      = TRUE,
      legend_position  = "top",
      trend_resolution = "Month"
    )

    plot_obj   <- render_plot(spec, dataset)
    summary_df <- build_variable_summary(dataset, var, column_types[[var]])

    sections[[i]] <- list(
      title      = var,
      plot_obj   = plot_obj,
      summary_df = summary_df
    )
  }
  # Drop NULLs (skipped variables)
  Filter(Negate(is.null), sections)
}


.build_primary_vs_others_sections <- function(dataset, column_types,
                                               secondary_vars,
                                               primary_variable,
                                               primary_role,
                                               stratify_variable) {
  sections <- vector("list", length(secondary_vars))
  for (i in seq_along(secondary_vars)) {
    sec_var <- secondary_vars[[i]]
    if (!sec_var %in% names(column_types))      next
    if (!primary_variable %in% names(column_types)) next

    # Axis assignment from role (mirrors build_bivariate_plot_spec logic)
    if (primary_role == "exposure") {
      col_a      <- primary_variable
      col_b      <- sec_var
      col_a_type <- column_types[[primary_variable]]
      col_b_type <- column_types[[sec_var]]
    } else {
      col_a      <- sec_var
      col_b      <- primary_variable
      col_a_type <- column_types[[sec_var]]
      col_b_type <- column_types[[primary_variable]]
    }

    # violin_jitter normalization: factor must be col_a (X)
    if (col_a_type == "numeric" && col_b_type == "factor") {
      tmp        <- col_a;      col_a      <- col_b;      col_b      <- tmp
      tmp        <- col_a_type; col_a_type <- col_b_type; col_b_type <- tmp
    }

    stratify_by <- if (!is.null(stratify_variable) && nzchar(stratify_variable))
      stratify_variable else NULL

    spec <- list(
      plot_type        = route_plot_type(col_a_type, col_b_type),
      column_a         = col_a,
      column_b         = col_b,
      primary_role     = primary_role,
      stratify_by      = stratify_by,
      color_palette    = "Set2",
      show_data_labels = FALSE,
      show_legend      = TRUE,
      legend_position  = "top",
      trend_resolution = "Month"
    )

    plot_obj <- render_plot(spec, dataset)

    # Summary: one row for primary + one row for secondary
    primary_summary   <- build_variable_summary(dataset, primary_variable,
                                                 column_types[[primary_variable]])
    secondary_summary <- build_variable_summary(dataset, sec_var,
                                                 column_types[[sec_var]])
    # rbind with type-compatible alignment: only common columns
    common_cols  <- intersect(names(primary_summary), names(secondary_summary))
    summary_df   <- rbind(primary_summary[, common_cols, drop = FALSE],
                          secondary_summary[, common_cols, drop = FALSE])

    title <- paste(primary_variable, "\u00d7", sec_var)
    if (!is.null(stratify_by))
      title <- paste(title, "\u00b7 stratified by", stratify_by)

    sections[[i]] <- list(
      title      = title,
      plot_obj   = plot_obj,
      summary_df = summary_df
    )
  }
  Filter(Negate(is.null), sections)
}


# ---------------------------------------------------------------------------
# Format assemblers
# ---------------------------------------------------------------------------

.assemble_pptx <- function(sections, output_path) {
  prs <- officer::read_pptx(
    system.file("templates/ppt_16x9_blank_template.pptx", package = "edark")
  )

  for (sec in sections) {
    prs <- officer::add_slide(prs, layout = "Blank", master = "Office Theme")

    # Title bar
    prs <- officer::ph_with(
      prs,
      value    = sec$title,
      location = officer::ph_location(left = 0.4, top = 0.2, width = 12.2, height = 0.55)
    )

    # Plot (left 60% of slide body)
    plot_location <- officer::ph_location(left = 0.4, top = 0.9, width = 7.4, height = 5.8)

    if (inherits(sec$plot_obj, "patchwork")) {
      # patchwork: render to temp PNG, insert as raster image
      tmp_png <- tempfile(fileext = ".png")
      on.exit(unlink(tmp_png), add = TRUE)
      ggplot2::ggsave(tmp_png, plot = sec$plot_obj,
                      width = 7.4, height = 5.8, units = "in", dpi = 150)
      prs <- officer::ph_with(
        prs,
        value    = officer::external_img(src = tmp_png, width = 7.4, height = 5.8),
        location = plot_location
      )
    } else {
      prs <- officer::ph_with(
        prs,
        value    = rvg::dml(ggobj = sec$plot_obj),
        location = plot_location
      )
    }

    # Summary flextable (right 40%)
    ft <- flextable::flextable(sec$summary_df)
    ft <- flextable::set_table_properties(ft, layout = "autofit")
    ft <- flextable::fontsize(ft, size = 8, part = "all")

    prs <- officer::ph_with(
      prs,
      value    = ft,
      location = officer::ph_location(left = 8.0, top = 0.9, width = 4.7, height = 5.8)
    )
  }

  print(prs, target = output_path)
  invisible(output_path)
}


.assemble_docx <- function(sections, output_path) {
  doc <- officer::read_docx()

  for (i in seq_along(sections)) {
    sec <- sections[[i]]

    doc <- officer::body_add_par(doc, sec$title, style = "heading 1")

    # Plot — raster via body_add_gg (handles both ggplot and patchwork)
    doc <- officer::body_add_gg(doc, value = sec$plot_obj,
                                 width = 6, height = 4, res = 150)

    # Summary table
    ft  <- flextable::flextable(sec$summary_df)
    ft  <- flextable::set_table_properties(ft, layout = "autofit")
    ft  <- flextable::fontsize(ft, size = 9, part = "all")
    doc <- flextable::body_add_flextable(doc, ft)

    # Page break between sections (not after the last one)
    if (i < length(sections)) {
      doc <- officer::body_add_break(doc)
    }
  }

  print(doc, target = output_path)
  invisible(output_path)
}


.assemble_html <- function(sections, output_path) {
  template_path <- system.file("report_template.Rmd", package = "edark")

  rmarkdown::render(
    input            = template_path,
    output_file      = normalizePath(output_path, mustWork = FALSE),
    output_dir       = dirname(normalizePath(output_path, mustWork = FALSE)),
    intermediates_dir = tempdir(),
    params           = list(sections = sections),
    quiet            = TRUE,
    envir            = new.env(parent = globalenv())
  )

  invisible(output_path)
}


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

#' Generate an EDARK report
#'
#' Builds a report from a dataset and a list of plot sections. Called by
#' \code{module_report.R}'s \code{downloadHandler} and by \code{edark_report()}.
#'
#' @param dataset A \code{data.frame} — the working dataset.
#' @param column_types Named character vector of column types (from
#'   \code{detect_column_types()}).
#' @param report_type \code{"all_vars"} or \code{"primary_vs_others"}.
#' @param variables Character vector of variable names to include in the report.
#' @param primary_variable For \code{"primary_vs_others"}: the primary variable name.
#' @param primary_role \code{"exposure"} or \code{"outcome"}.
#' @param stratify_variable Optional column name to stratify all bivariate plots by.
#' @param format Output format: \code{"pptx"}, \code{"docx"}, or \code{"html"}.
#' @param output_path Absolute path to write the report to.
#'
#' @return Invisibly returns \code{output_path}.
#'
#' @export
generate_report <- function(dataset,
                             column_types,
                             report_type,
                             variables,
                             primary_variable  = NULL,
                             primary_role      = "exposure",
                             stratify_variable = NULL,
                             format,
                             output_path) {
  stopifnot(report_type %in% c("all_vars", "primary_vs_others"))
  stopifnot(format %in% c("pptx", "docx", "html"))
  stopifnot(is.data.frame(dataset), length(variables) >= 1)

  sections <- if (report_type == "all_vars") {
    .build_all_vars_sections(dataset, column_types, variables)
  } else {
    if (is.null(primary_variable))
      stop("primary_variable must be specified for report_type = 'primary_vs_others'")
    secondary_vars <- setdiff(variables, primary_variable)
    if (length(secondary_vars) == 0)
      stop("No secondary variables to plot — ensure variables contains columns besides primary_variable.")
    .build_primary_vs_others_sections(
      dataset, column_types, secondary_vars,
      primary_variable, primary_role, stratify_variable
    )
  }

  if (length(sections) == 0)
    stop("No sections could be built — check that selected variables exist in the dataset.")

  switch(format,
    pptx = .assemble_pptx(sections, output_path),
    docx = .assemble_docx(sections, output_path),
    html = .assemble_html(sections, output_path)
  )

  invisible(output_path)
}
