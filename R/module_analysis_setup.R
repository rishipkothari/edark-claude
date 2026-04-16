#' Analysis Step 1 — Setup Module
#'
#' UI and server for Step 1 of the Analysis workflow: dataset freeze,
#' variable role assignment, and study type derivation.
#' Full implementation: Phase 1 of the build plan.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @name module_analysis_setup
NULL


#' @rdname module_analysis_setup
#' @export
analysis_setup_ui <- function(id) {
  bslib::card(
    full_screen = FALSE,
    bslib::card_body(
      shiny::tags$p(
        class = "text-muted fst-italic text-center mt-4",
        shiny::icon("clock"),
        " Step 1 \u2014 Setup: available in Phase 1."
      )
    )
  )
}


#' @rdname module_analysis_setup
#' @export
analysis_setup_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {
    # Phase 1 implementation
  })
}
