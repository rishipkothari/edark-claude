#' Analysis Step 2 — Table 1 Module
#'
#' UI and server for Step 2 of the Analysis workflow: descriptive summary
#' table (Table 1) stratified by exposure, outcome, or overall.
#' Full implementation per PRD §5.3 Step 2, §6.4, §3.7.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_table1
NULL


#' @rdname module_analysis_table1
#' @export
analysis_table1_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      position = "left",
      width    = 390,

      shiny::uiOutput(ns("strat_ui")),

      shiny::tags$hr(class = "my-2"),
      edark_run_button(ns, "btn_generate", "Generate Table 1", icon = "table")
    ),

    shiny::uiOutput(ns("table_area"))
  )
}


#' Mark one choice of an input as disabled
#'
#' Walks a rendered tag tree and adds the boolean \code{disabled} attribute to
#' the \code{<input>} (radio/checkbox) or \code{<option>} (plain select) that
#' carries \code{value}. Used instead of \code{shinyjs} (which is not
#' initialised in this app) and instead of \code{htmltools::tagQuery} (whose
#' selectors do not support \code{[attr]}).
#'
#' Note this only works on a \code{selectInput(selectize = FALSE)} — selectize
#' builds its option list in JS, so there are no \code{<option>} tags to mark.
#'
#' @param tag A \code{shiny.tag}, \code{shiny.tag.list}, or plain list.
#' @param value Character. The \code{value} attribute of the choice to disable.
#'
#' @return The tag tree with the matching choice disabled.
#' @keywords internal
#' @noRd
.disable_choice <- function(tag, value) {
  # <option> tags arrive as a pre-rendered HTML string (shiny builds a select's
  # option list with selectOptions()), so string children are patched textually.
  opt_pat <- paste0('(<option[^>]*value="', value, '")')

  if (inherits(tag, "shiny.tag")) {
    if (tag$name %in% c("input", "option") &&
        identical(as.character(tag$attribs$value), value)) {
      tag$attribs$disabled <- NA
      return(tag)
    }
    tag$children <- lapply(tag$children, .disable_choice, value = value)
    return(tag)
  }
  if (is.character(tag) && length(tag) == 1L && grepl("<option", tag, fixed = TRUE)) {
    patched <- sub(opt_pat, "\\1 disabled", tag)
    return(if (inherits(tag, "html")) shiny::HTML(patched) else patched)
  }
  if (is.list(tag)) {
    out <- lapply(tag, .disable_choice, value = value)
    attributes(out) <- attributes(tag)
    return(out)
  }
  tag
}


#' @rdname module_analysis_table1
#' @export
analysis_table1_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Which roles are eligible to stratify on ──────────────────────────────
    # Derived from the frozen dataset + spec, never from the checkbox inputs.
    # A checkbox removed from the DOM keeps its last value in Shiny's input
    # registry, so a stale TRUE would otherwise survive a role change in Step 1
    # and stratify Table 1 by a numeric variable.
    strat_eligible <- shiny::reactive({
      spec   <- shared_state$analysis_spec
      ctypes <- shared_state$column_types
      adata  <- shared_state$analysis_data

      is_groupable <- function(v) {
        if (is.null(v) || !nzchar(v)) return(FALSE)
        if (!is.null(adata) && v %in% names(adata)) {
          col <- adata[[v]]
          return(is.factor(col) || is.character(col) || is.logical(col))
        }
        !is.null(ctypes) && v %in% names(ctypes) && ctypes[[v]] == "factor"
      }

      list(
        exposure = is_groupable(spec$variable_roles$exposure_variable),
        outcome  = is_groupable(spec$variable_roles$outcome_variable)
      )
    })

    # ── Is each stratifier binary? ───────────────────────────────────────────
    # gtsummary::add_difference() requires exactly two groups, so SMD is only
    # offered for a stratifier with 2 observed levels.
    binary_stratifier <- shiny::reactive({
      spec  <- shared_state$analysis_spec
      adata <- shared_state$analysis_data

      is_binary <- function(v) {
        if (is.null(v) || !nzchar(v)) return(FALSE)
        if (is.null(adata) || !v %in% names(adata)) return(FALSE)
        col <- adata[[v]]
        if (!(is.factor(col) || is.character(col) || is.logical(col))) return(FALSE)
        length(unique(stats::na.omit(as.character(col)))) == 2L
      }

      list(
        exposure = is_binary(spec$variable_roles$exposure_variable),
        outcome  = is_binary(spec$variable_roles$outcome_variable)
      )
    })

    # Resolve a stat dropdown value, downgrading SMD when it is unavailable.
    .resolve_stat <- function(v, smd_ok) {
      if (is.null(v) || !v %in% c("none", "pvalues", "smd")) return("none")
      if (identical(v, "smd") && !smd_ok) return("none")
      v
    }

    # ── Stratification UI (conditional on variable types) ────────────────────
    output$strat_ui <- shiny::renderUI({
      spec <- shared_state$analysis_spec
      shiny::req(!is.null(spec))
      elig <- strat_eligible()
      bin  <- binary_stratifier()

      if (!elig$exposure && !elig$outcome) return(NULL)

      t1 <- spec$table1_specification

      # Initial dropdown value from the spec, unless the user already picked
      # one. The read is isolated: reacting to it would retrigger this render.
      spec_stat <- function(p_field, smd_field) {
        if (isTRUE(t1[[smd_field]])) "smd" else if (isTRUE(t1[[p_field]])) "pvalues" else "none"
      }
      current_stat <- function(input_id, p_field, smd_field, smd_ok) {
        cur <- shiny::isolate(input[[input_id]])
        sel <- if (is.null(cur)) spec_stat(p_field, smd_field) else cur
        .resolve_stat(sel, smd_ok)
      }

      # One dependent sub-control, indented under its checkbox.
      stat_block <- function(checkbox_id, input_id, selected, smd_ok) {
        sel_in <- shiny::selectInput(
          ns(input_id),
          label    = "Comparison statistic",
          choices  = stats::setNames(
            c("none", "pvalues", "smd"),
            c("None", "P-values", if (smd_ok) "SMD" else "SMD - binary only")
          ),
          selected = selected,
          width    = "100%",
          selectize = FALSE
        )
        if (!smd_ok) sel_in <- .disable_choice(sel_in, "smd")

        shiny::conditionalPanel(
          condition = paste0("input.", checkbox_id),
          ns        = ns,
          shiny::div(class = "ms-3 ps-3 border-start mb-2", sel_in)
        )
      }

      exp_block <- if (elig$exposure) shiny::tagList(
        shiny::checkboxInput(
          ns("strat_by_exposure"),
          paste0("By Exposure (", spec$variable_roles$exposure_variable, ")"),
          value = isTRUE(t1$stratify_by_exposure)
        ),
        stat_block(
          "strat_by_exposure", "stat_exposure",
          current_stat("stat_exposure", "include_pvalues_exposure",
                       "include_smd_exposure", bin$exposure),
          bin$exposure
        )
      )

      out_block <- if (elig$outcome) shiny::tagList(
        shiny::checkboxInput(
          ns("strat_by_outcome"),
          paste0("By Outcome (", spec$variable_roles$outcome_variable, ")"),
          value = isTRUE(t1$stratify_by_outcome)
        ),
        stat_block(
          "strat_by_outcome", "stat_outcome",
          current_stat("stat_outcome", "include_pvalues_outcome",
                       "include_smd_outcome", bin$outcome),
          bin$outcome
        )
      )

      shiny::tagList(
        shiny::tags$p("Stratification",
          class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
        exp_block,
        out_block,
        shiny::tags$small(class = "text-muted",
          "SMD = standardized mean difference; needs a binary stratifier.")
      )
    })

    # ── Precondition ─────────────────────────────────────────
    # Step 1 must have frozen a dataset and assigned at least one role. The
    # button says so itself rather than answering a click with a toast.
    t1_block <- shiny::reactive({
      spec  <- shared_state$analysis_spec
      adata <- shared_state$analysis_data
      if (is.null(spec) || is.null(adata)) return("analysis_start")
      vr <- spec$variable_roles
      if (is.null(vr$outcome_variable) && is.null(vr$exposure_variable) &&
          is.null(vr$candidate_covariates)) return("analysis_roles")
      NULL
    })
    edark_run_gate(output, "btn_generate",
                   enabled = shiny::reactive(is.null(t1_block())),
                   reason  = shiny::reactive(edark_lock_reason(t1_block())))

    # ── Generate Table 1 ─────────────────────────────────────────────────────
    shiny::observeEvent(input$btn_generate, {
      spec  <- shiny::isolate(shared_state$analysis_spec)
      adata <- shiny::isolate(shared_state$analysis_data)
      if (!is.null(shiny::isolate(t1_block()))) return()   # the button is disabled

      # Gate every input read on current eligibility — an input left over from
      # a previous role assignment must not reach build_table1().
      elig      <- strat_eligible()
      bin       <- binary_stratifier()
      strat_exp <- elig$exposure && isTRUE(input$strat_by_exposure)
      strat_out <- elig$outcome  && isTRUE(input$strat_by_outcome)

      stat_exp <- if (strat_exp) .resolve_stat(input$stat_exposure, bin$exposure) else "none"
      stat_out <- if (strat_out) .resolve_stat(input$stat_outcome,  bin$outcome)  else "none"

      # Overlay the spec's table1_specification with current UI state
      spec$table1_specification$stratify_by_exposure     <- strat_exp
      spec$table1_specification$stratify_by_outcome      <- strat_out
      spec$table1_specification$include_pvalues_exposure <- identical(stat_exp, "pvalues")
      spec$table1_specification$include_pvalues_outcome  <- identical(stat_out, "pvalues")
      spec$table1_specification$include_smd_exposure     <- identical(stat_exp, "smd")
      spec$table1_specification$include_smd_outcome      <- identical(stat_out, "smd")

      shiny::showModal(shiny::modalDialog(
        title = shiny::tagList(
          shiny::tags$span(
            class = "spinner-border spinner-border-sm me-2",
            role  = "status",
            shiny::tags$span(class = "visually-hidden", "Loading...")
          ),
          "Generating Table 1\u2026"
        ),
        shiny::div(
          class = "progress mb-2",
          style = "height: 6px;",
          shiny::div(
            id              = "edark_analysis_progress_bar",
            class           = "progress-bar progress-bar-striped progress-bar-animated",
            role            = "progressbar",
            style           = "width: 5%;",
            `aria-valuenow` = "5",
            `aria-valuemin` = "0",
            `aria-valuemax` = "100"
          )
        ),
        shiny::tags$p(
          id    = "edark_analysis_progress_detail",
          class = "text-muted mb-0 small",
          "Building summary table\u2026"
        ),
        footer    = NULL,
        easyClose = FALSE
      ))
      on.exit(shiny::removeModal(), add = TRUE)

      tables <- build_table1(
        data                     = adata,
        spec                     = spec,
        include_pvalues_exposure = identical(stat_exp, "pvalues"),
        include_pvalues_outcome  = identical(stat_out, "pvalues"),
        include_smd_exposure     = identical(stat_exp, "smd"),
        include_smd_outcome      = identical(stat_out, "smd")
      )

      # Store in analysis_result
      res <- shiny::isolate(shared_state$analysis_result)
      if (is.null(res)) res <- list()
      if (is.null(res$result_tables)) res$result_tables <- list()

      res$result_tables$table1_overall     <- tables$overall
      res$result_tables$table1_by_exposure <- tables$by_exposure
      res$result_tables$table1_by_outcome  <- tables$by_outcome
      shared_state$analysis_result <- res

      # Persist spec overrides
      cur_spec <- shiny::isolate(shared_state$analysis_spec)
      if (!is.null(cur_spec)) {
        cur_spec$table1_specification <- spec$table1_specification
        shared_state$analysis_spec    <- cur_spec
      }
    }, ignoreInit = TRUE)

    # ── Table area ────────────────────────────────────────────────────────────
    output$table_area <- shiny::renderUI({
      result <- shared_state$analysis_result
      spec   <- shared_state$analysis_spec

      # Determine which tabs to show
      elig         <- strat_eligible()
      exp_assigned <- !is.null(spec$variable_roles$exposure_variable)
      out_assigned <- !is.null(spec$variable_roles$outcome_variable)
      strat_exp    <- elig$exposure && isTRUE(input$strat_by_exposure)
      strat_out    <- elig$outcome  && isTRUE(input$strat_by_outcome)

      has_overall  <- !is.null(result$result_tables$table1_overall)
      has_exposure <- exp_assigned && strat_exp && !is.null(result$result_tables$table1_by_exposure)
      has_outcome  <- out_assigned && strat_out && !is.null(result$result_tables$table1_by_outcome)

      if (!has_overall) {
        return(shiny::div(
          class = "text-center text-muted mt-5",
          shiny::icon("table", style = "font-size:2rem; opacity:0.3;"),
          shiny::tags$p(class = "mt-2", "Click \u201cGenerate Table 1\u201d to build the summary table.")
        ))
      }

      tabs <- list(
        bslib::nav_panel("Overall", gt::gt_output(ns("tbl_overall")))
      )
      if (has_exposure) {
        tabs[[length(tabs) + 1]] <- bslib::nav_panel(
          paste0("By ", spec$variable_roles$exposure_variable),
          gt::gt_output(ns("tbl_by_exposure"))
        )
      }
      if (has_outcome) {
        tabs[[length(tabs) + 1]] <- bslib::nav_panel(
          paste0("By ", spec$variable_roles$outcome_variable),
          gt::gt_output(ns("tbl_by_outcome"))
        )
      }

      do.call(bslib::navset_card_tab, tabs)
    })

    # ── gt render outputs ─────────────────────────────────────────────────────
    output$tbl_overall <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_overall
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

    output$tbl_by_exposure <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_by_exposure
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

    output$tbl_by_outcome <- gt::render_gt({
      tbl <- shared_state$analysis_result$result_tables$table1_by_outcome
      shiny::req(!is.null(tbl))
      gtsummary::as_gt(tbl)
    })

  })
}
