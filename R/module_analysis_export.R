#' Analysis Step 6 — Export Module
#'
#' UI and server for Step 6 of the Analysis workflow: export preset selector,
#' item checklists, zip preview, and download handler producing a structured
#' analysis folder (see PRD §10.2 for folder layout).
#' Full implementation: Phase 8 of the build plan.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @name module_analysis_export
NULL


#' @rdname module_analysis_export
#' @export
analysis_export_ui <- function(id) {
  # Still the Phase 8 stub, but in the page shape every other page uses (D6),
  # so the walk from Step 1 to Step 6 does not change layout at the last step.
  # Phase 8 fills the config pane with the preset selector and item checklists,
  # the centre with the file list, and the info pane with the zip's contents.
  edark_page(
    config = shiny::tagList(
      edark_section_label("Export", first = TRUE),
      shiny::tags$p(
        class = "small text-muted mb-0",
        "The preset selector and the list of items to include will live here."
      )
    ),
    result = edark_empty_state(
      "Export is not built yet",
      "Step 6 assembles the working dataset, the analysis spec, and the tables,
       figures and diagnostics you generated into one zip. It arrives in Phase 8.",
      icon = "box-archive"
    ),
    info = shiny::tagList(
      edark_section_label("Will contain", first = TRUE),
      shiny::tags$p(class = "small text-muted mb-0",
                    "Once built, this pane lists what the zip will hold.")
    )
  )
}


#' @rdname module_analysis_export
#' @export
analysis_export_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    # Phase 8 implementation
  })
}
