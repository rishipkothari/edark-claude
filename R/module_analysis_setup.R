#' Analysis Step 1 — Setup Module
#'
#' UI and server for Step 1 of the Analysis workflow: dataset freeze,
#' variable role assignment, and study type derivation.
#' Full implementation per PRD §5.3 Step 1, §6.3, §1.4, §3.4, §3.5.
#'
#' @param id Character. Module namespace ID.
#' @param shared_state A Shiny \code{reactiveValues} object.
#'
#' @importFrom magrittr %>%
#'
#' @name module_analysis_setup
NULL


# Build the JS block for role table interactivity.
# Injects the module namespace so Shiny.setInputValue targets the right input.
.setup_role_js <- function(ns) {
  shiny::tags$script(shiny::HTML(paste0("
(function() {
  var RADIO_ROLES = ['outcome', 'exposure', 'subject_id', 'cluster', 'time'];
  var NS = '", ns(""), "';

  // Radio role changed
  $(document).on('change', '.edark-role-radio', function() {
    if (!this.checked) return;
    var role    = $(this).data('role');
    var varName = $(this).data('var');

    // Uncheck other radio roles for this variable (cross-role exclusivity)
    RADIO_ROLES.forEach(function(r) {
      if (r !== role) {
        document.querySelectorAll(
          '.edark-role-radio[data-role=\"' + r + '\"][data-var=\"' + CSS.escape(varName) + '\"]'
        ).forEach(function(el) { el.checked = false; });
      }
    });

    // Uncheck candidate for this variable
    document.querySelectorAll(
      '.edark-role-checkbox[data-var=\"' + CSS.escape(varName) + '\"]'
    ).forEach(function(el) { el.checked = false; });

    Shiny.setInputValue(NS + 'role_change',
      { var: varName, role: role, value: true },
      { priority: 'event' }
    );
  });

  // Candidate checkbox changed
  $(document).on('change', '.edark-role-checkbox', function() {
    var varName = $(this).data('var');
    if (this.checked) {
      RADIO_ROLES.forEach(function(r) {
        document.querySelectorAll(
          '.edark-role-radio[data-role=\"' + r + '\"][data-var=\"' + CSS.escape(varName) + '\"]'
        ).forEach(function(el) { el.checked = false; });
      });
    }
    Shiny.setInputValue(NS + 'role_change',
      { var: varName, role: 'candidate', value: this.checked },
      { priority: 'event' }
    );
  });

  // Reference level dropdown changed
  $(document).on('change', '.edark-role-reflevel', function() {
    var varName = $(this).data('var');
    Shiny.setInputValue(NS + 'role_change',
      { var: varName, role: 'reference_level', value: $(this).val() },
      { priority: 'event' }
    );
  });

  // Column Clear button clicked
  $(document).on('click', '.edark-clear-role', function(e) {
    e.preventDefault();
    var role = $(this).data('role');
    if (role === 'candidate') {
      document.querySelectorAll('.edark-role-checkbox').forEach(function(el) {
        el.checked = false;
      });
    } else {
      document.querySelectorAll(
        '.edark-role-radio[data-role=\"' + role + '\"]'
      ).forEach(function(el) { el.checked = false; });
    }
    Shiny.setInputValue(NS + 'role_change',
      { var: '__clear__', role: role, value: false },
      { priority: 'event' }
    );
  });

  // Select All candidates button clicked
  $(document).on('click', '.edark-select-all-candidates', function(e) {
    e.preventDefault();
    document.querySelectorAll('.edark-role-checkbox').forEach(function(el) {
      var varName = el.getAttribute('data-var');
      var hasRadioRole = RADIO_ROLES.some(function(r) {
        return Array.from(document.querySelectorAll(
          '.edark-role-radio[data-role=\"' + r + '\"][data-var=\"' + CSS.escape(varName) + '\"]'
        )).some(function(radio) { return radio.checked; });
      });
      if (!hasRadioRole) el.checked = true;
    });
    Shiny.setInputValue(NS + 'role_change',
      { var: '__select_all_candidates__', role: 'candidate', value: true },
      { priority: 'event' }
    );
  });
})();
")))
}


#' @rdname module_analysis_setup
#' @export
analysis_setup_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    .setup_role_js(ns),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        position = "right",
        width    = 405,
        shiny::uiOutput(ns("action_buttons_ui")),
        shiny::tags$hr(class = "my-2"),
        shiny::uiOutput(ns("incoming_snapshot_ui")),
        shiny::tags$hr(class = "my-2"),
        shiny::uiOutput(ns("study_type_ui")),
        shiny::uiOutput(ns("role_summary_ui")),
        shiny::uiOutput(ns("selected_snapshot_ui"))
      ),
      shiny::uiOutput(ns("main_content"))
    )
  )
}


#' @rdname module_analysis_setup
#' @export
analysis_setup_server <- function(id, shared_state) {
  shiny::moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Local state ──────────────────────────────────────────────────────────
    RADIO_ROLES <- c("outcome", "exposure", "subject_id", "cluster", "time")

    # Named list keyed by variable name; each entry is a role assignment list.
    roles_state    <- shiny::reactiveVal(NULL)
    # Incremented on freeze / unfreeze to force re-render of the role table.
    frozen_trigger <- shiny::reactiveVal(0L)
    # Holds a pending role-change event while waiting for user confirmation.
    pending_change <- shiny::reactiveVal(NULL)

    .empty_role <- function() {
      list(outcome = FALSE, exposure = FALSE, candidate = FALSE,
           subject_id = FALSE, cluster = FALSE, time = FALSE,
           reference_level = NULL)
    }

    # ── Dataset freeze ───────────────────────────────────────────────────────
    .do_freeze <- function() {
      wd <- shiny::isolate(shared_state$dataset_working)
      if (is.null(wd) || nrow(wd) == 0) return()

      sig <- digest::digest(wd, algo = "sha256")
      wd[[".edark_row_id"]] <- seq_len(nrow(wd))

      reset_analysis_pipeline(shared_state, from_step = 1L)
      shared_state$analysis_data   <- wd
      shared_state$analysis_result <- NULL

      shared_state$analysis_spec <- list(
        specification_metadata = list(
          study_type        = "descriptive",
          created_at        = Sys.time(),
          dataset_signature = sig
        ),
        variable_roles = list(
          outcome_variable       = NULL,
          exposure_variable      = NULL,
          candidate_covariates   = NULL,
          table1_variables       = NULL,
          univariable_test_pool  = NULL,
          final_model_covariates = NULL,
          subject_id_variable    = NULL,
          cluster_variable       = NULL,
          time_variable          = NULL,
          reference_levels       = list()
        ),
        table1_specification = list(
          stratify_by_exposure                 = TRUE,
          stratify_by_outcome                  = FALSE,
          include_pvalues_exposure             = FALSE,
          include_pvalues_outcome              = TRUE,
          include_standardized_mean_difference = TRUE
        ),
        variable_selection_specification = list(
          method                  = "univariable",
          univariable_p_threshold = 0.2,
          stepwise_direction      = "backward",
          stepwise_criterion      = "BIC",
          lasso_lambda            = "lambda.1se",
          selected_variables      = NULL
        ),
        model_design = list(
          model_type                 = NULL,
          random_intercept_variable  = NULL,
          random_slope_variable      = NULL,
          confidence_interval_level  = 0.95,
          optimizer                  = "bobyqa",
          linked_model_specification = NULL
        ),
        analysis_options = list(
          missing_data_handling = "complete_case",
          interaction_terms     = list()
        )
      )

      ctypes <- shiny::isolate(shared_state$column_types)
      vars   <- setdiff(names(wd), ".edark_row_id")

      init_roles <- stats::setNames(
        lapply(vars, function(v) {
          role <- .empty_role()
          if (!is.null(ctypes) && v %in% names(ctypes) && ctypes[[v]] == "factor") {
            col <- wd[[v]]
            if (is.factor(col) && length(levels(col)) > 0) {
              role$reference_level <- levels(col)[1]
            }
          }
          role
        }),
        vars
      )

      roles_state(init_roles)
      frozen_trigger(shiny::isolate(frozen_trigger()) + 1L)
    }

    shiny::observeEvent(input$btn_start_analysis, {
      .do_freeze()
    }, ignoreInit = TRUE)

    # ── Dataset signature mismatch detection ─────────────────────────────────
    working_sig <- shiny::reactive({
      wd <- shared_state$dataset_working
      if (is.null(wd)) return(NULL)
      digest::digest(wd, algo = "sha256")
    })

    sig_mismatch <- shiny::reactive({
      spec <- shared_state$analysis_spec
      if (is.null(spec)) return(FALSE)
      frozen_sig <- spec$specification_metadata$dataset_signature
      ws <- working_sig()
      if (is.null(frozen_sig) || is.null(ws)) return(FALSE)
      !identical(ws, frozen_sig)
    })

    # ── Restart Analysis ─────────────────────────────────────────────────────
    shiny::observeEvent(input$btn_restart_analysis, {
      shiny::showModal(shiny::modalDialog(
        title = "Restart Analysis?",
        shiny::p("This will clear all analysis results and re-freeze the current working dataset."),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("confirm_restart"), "Restart", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$confirm_restart, {
      shiny::removeModal()
      .do_freeze()
    }, ignoreInit = TRUE)

    # ── Role change dispatcher ────────────────────────────────────────────────
    shiny::observeEvent(input$role_change, {
      ev     <- input$role_change
      result <- shiny::isolate(shared_state$analysis_result)

      if (!is.null(result)) {
        # Downstream results exist — ask for confirmation before applying
        pending_change(ev)
        shiny::showModal(shiny::modalDialog(
          title = "Clear Analysis Results?",
          shiny::p("Changing role assignments will clear all downstream results (Table 1, variable investigation, model, diagnostics, and results)."),
          shiny::tags$small(
            class = "text-muted",
            "If you click Cancel, undo your change in the table manually."
          ),
          footer = shiny::tagList(
            shiny::actionButton(ns("cancel_role_change"),  "Cancel",         class = "btn-secondary"),
            shiny::actionButton(ns("confirm_role_change"), "Clear & Continue", class = "btn-warning")
          ),
          easyClose = FALSE
        ))
      } else {
        .apply_role_change(ev)
      }
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$confirm_role_change, {
      shiny::removeModal()
      ev <- pending_change()
      pending_change(NULL)
      reset_analysis_pipeline(shared_state, from_step = 1L)
      if (!is.null(ev)) .apply_role_change(ev)
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$cancel_role_change, {
      shiny::removeModal()
      pending_change(NULL)
    }, ignoreInit = TRUE)

    # ── Apply a role change event to roles_state and sync spec ───────────────
    .apply_role_change <- function(ev) {
      var   <- ev$var
      role  <- ev$role
      value <- ev$value

      current <- roles_state()
      if (is.null(current)) return()

      if (var == "__clear__") {
        for (v in names(current)) {
          if (role %in% RADIO_ROLES) {
            current[[v]][[role]] <- FALSE
          } else if (role == "candidate") {
            current[[v]][["candidate"]] <- FALSE
          }
        }
      } else if (var == "__select_all_candidates__") {
        for (v in names(current)) {
          has_radio <- any(vapply(RADIO_ROLES, function(r) isTRUE(current[[v]][[r]]), logical(1)))
          if (!has_radio) current[[v]][["candidate"]] <- TRUE
        }
      } else {
        if (!var %in% names(current)) return()

        if (role %in% RADIO_ROLES && isTRUE(value)) {
          for (v in names(current)) {
            if (v != var) current[[v]][[role]] <- FALSE
          }
          for (r in RADIO_ROLES) {
            if (r != role) current[[var]][[r]] <- FALSE
          }
          current[[var]][["candidate"]] <- FALSE
          current[[var]][[role]] <- TRUE
        } else if (role == "candidate") {
          if (isTRUE(value)) {
            for (r in RADIO_ROLES) current[[var]][[r]] <- FALSE
          }
          current[[var]][["candidate"]] <- isTRUE(value)
        } else if (role == "reference_level") {
          current[[var]][["reference_level"]] <- value
        }
      }

      roles_state(current)
      .sync_spec(current)
    }

    # ── Sync roles_state → analysis_spec ─────────────────────────────────────
    .sync_spec <- function(rs) {
      spec <- shiny::isolate(shared_state$analysis_spec)
      if (is.null(spec)) return()

      outcome_vars    <- names(which(vapply(rs, function(r) isTRUE(r$outcome),     logical(1))))
      exposure_vars   <- names(which(vapply(rs, function(r) isTRUE(r$exposure),    logical(1))))
      candidates      <- names(which(vapply(rs, function(r) isTRUE(r$candidate),   logical(1))))
      subject_id_vars <- names(which(vapply(rs, function(r) isTRUE(r$subject_id),  logical(1))))
      cluster_vars    <- names(which(vapply(rs, function(r) isTRUE(r$cluster),     logical(1))))
      time_vars       <- names(which(vapply(rs, function(r) isTRUE(r$time),        logical(1))))

      outcome_var  <- if (length(outcome_vars)    > 0) outcome_vars[1]    else NULL
      exposure_var <- if (length(exposure_vars)   > 0) exposure_vars[1]   else NULL
      subject_var  <- if (length(subject_id_vars) > 0) subject_id_vars[1] else NULL
      cluster_var  <- if (length(cluster_vars)    > 0) cluster_vars[1]    else NULL
      time_var     <- if (length(time_vars)       > 0) time_vars[1]       else NULL

      study_type <- if (!is.null(exposure_var) && !is.null(outcome_var)) {
        "exposure_outcome"
      } else if (is.null(exposure_var) && !is.null(outcome_var)) {
        "risk_factor"
      } else if (!is.null(exposure_var) && is.null(outcome_var)) {
        "descriptive_exposure"
      } else {
        "descriptive"
      }

      ctypes <- shiny::isolate(shared_state$column_types)
      exp_is_factor <- !is.null(exposure_var) && !is.null(ctypes) &&
                       exposure_var %in% names(ctypes) && ctypes[[exposure_var]] == "factor"
      out_is_factor <- !is.null(outcome_var) && !is.null(ctypes) &&
                       outcome_var %in% names(ctypes) && ctypes[[outcome_var]] == "factor"
      t1_strat_exp <- study_type %in% c("exposure_outcome", "descriptive_exposure") && exp_is_factor
      t1_strat_out <- study_type == "risk_factor" && out_is_factor

      radio_assigned <- Filter(Negate(is.null),
                               list(outcome_var, exposure_var, subject_var, cluster_var, time_var))
      candidates <- setdiff(candidates, unlist(radio_assigned))

      t1_vars <- unique(c(exposure_var, outcome_var, candidates))
      t1_vars <- t1_vars[!vapply(t1_vars, is.null, logical(1))]
      t1_vars <- t1_vars[nzchar(t1_vars)]

      ref_levels <- Filter(Negate(is.null), lapply(rs, `[[`, "reference_level"))

      old_spec <- spec
      spec$specification_metadata$study_type     <- study_type
      spec$variable_roles$outcome_variable        <- outcome_var
      spec$variable_roles$exposure_variable       <- exposure_var
      spec$variable_roles$candidate_covariates    <- if (length(candidates) > 0) candidates else NULL
      spec$variable_roles$table1_variables        <- if (length(t1_vars) > 0) t1_vars else NULL
      spec$variable_roles$univariable_test_pool   <- if (length(candidates) > 0) candidates else NULL
      spec$variable_roles$final_model_covariates  <- if (length(candidates) > 0) candidates else NULL
      spec$variable_roles$subject_id_variable     <- subject_var
      spec$variable_roles$cluster_variable        <- cluster_var
      spec$variable_roles$time_variable           <- time_var
      spec$variable_roles$reference_levels        <- ref_levels
      spec$table1_specification$stratify_by_exposure <- t1_strat_exp
      spec$table1_specification$stratify_by_outcome  <- t1_strat_out

      if (!identical(old_spec, spec)) {
        shared_state$analysis_spec <- spec
      }
    }

    # ── Main content (pre-freeze vs post-freeze) ──────────────────────────────
    output$main_content <- shiny::renderUI({
      frozen_trigger()
      adata <- shared_state$analysis_data

      if (is.null(adata)) {
        wd   <- shared_state$dataset_working
        n_r  <- if (!is.null(wd)) nrow(wd)  else 0L
        n_c  <- if (!is.null(wd)) ncol(wd)  else 0L
        n_cc <- if (!is.null(wd)) sum(stats::complete.cases(wd)) else 0L
        pct  <- if (n_r > 0) round(n_cc / n_r * 100L) else 0L

        bslib::card(
          bslib::card_header("Ready to Start Analysis"),
          bslib::card_body(
            shiny::tags$p(
              class = "text-muted mb-3",
              sprintf("%d rows \u00b7 %d columns \u00b7 %d complete cases (%d%% complete)",
                      n_r, n_c, n_cc, pct)
            ),
            shiny::tags$p(
              class = "text-muted small mb-0",
              "Freezing the dataset creates a snapshot for analysis. Changes in Prepare",
              "after this point won't affect the analysis unless you restart."
            )
          )
        )
      } else {
        shiny::tagList(
          shiny::uiOutput(ns("mismatch_banner")),
          reactable::reactableOutput(ns("role_table"))
        )
      }
    })

    # ── Mismatch banner ──────────────────────────────────────────────────────
    output$mismatch_banner <- shiny::renderUI({
      if (!sig_mismatch()) return(NULL)
      shiny::div(
        class = "alert alert-warning d-flex align-items-center gap-2 mb-3",
        shiny::icon("triangle-exclamation"),
        shiny::span(
          "Your working dataset has changed since this analysis was started.",
          "Use \u201cRestart Analysis\u201d in the sidebar to use the updated data."
        )
      )
    })

    # ── Role assignment table ────────────────────────────────────────────────
    output$role_table <- reactable::renderReactable({
      frozen_trigger()
      adata  <- shiny::isolate(shared_state$analysis_data)
      if (is.null(adata)) return(NULL)
      ctypes <- shiny::isolate(shared_state$column_types)
      vars   <- setdiff(names(adata), ".edark_row_id")

      .type_badge <- function(t) {
        cls <- switch(t,
          numeric   = "badge text-bg-primary",
          factor    = "badge text-bg-success",
          datetime  = "badge text-bg-warning text-dark",
          character = "badge text-bg-secondary",
          "badge text-bg-light text-dark"
        )
        htmltools::tags$span(class = cls, style = "font-size:0.7rem;", t)
      }

      .radio_cell <- function(role_key) {
        function(value, index) {
          htmltools::tags$input(
            type        = "radio",
            class       = "edark-role-radio form-check-input",
            name        = paste0("role_", role_key),
            `data-var`  = vars[index],
            `data-role` = role_key
          )
        }
      }

      .clear_header <- function(label, role_key) {
        htmltools::tags$div(
          class = "d-flex flex-column align-items-center",
          htmltools::tags$span(style = "font-size:0.75rem;", label),
          htmltools::tags$button(
            "Clear",
            class       = "edark-clear-role btn btn-link btn-sm p-0 text-muted",
            style       = "font-size:0.7rem; line-height:1;",
            `data-role` = role_key
          )
        )
      }

      df <- data.frame(
        ID         = seq_along(vars),
        Variable   = vars,
        Type       = vapply(vars, function(v) {
          if (!is.null(ctypes) && v %in% names(ctypes)) ctypes[[v]] else "unknown"
        }, character(1)),
        ref_level  = vapply(vars, function(v) {
          if (!is.null(ctypes) && v %in% names(ctypes) && ctypes[[v]] == "factor") {
            col <- adata[[v]]
            if (is.factor(col) && length(levels(col)) > 0) levels(col)[1] else ""
          } else ""
        }, character(1)),
        exposure   = FALSE,
        outcome    = FALSE,
        candidate  = FALSE,
        subject_id = FALSE,
        cluster    = FALSE,
        time       = FALSE,
        stringsAsFactors = FALSE,
        row.names  = NULL
      )

      reactable::reactable(
        df,
        searchable    = TRUE,
        pagination    = FALSE,
        highlight     = TRUE,
        compact       = TRUE,
        defaultColDef = reactable::colDef(
          align  = "center",
          vAlign = "center",
          minWidth = 60
        ),
        columns = list(
          ID = reactable::colDef(
            name     = "ID",
            minWidth = 45,
            sortable = TRUE
          ),
          Variable = reactable::colDef(
            name     = "Variable",
            align    = "left",
            minWidth = 140,
            sticky   = "left"
          ),
          Type = reactable::colDef(
            name     = "Type",
            minWidth = 80,
            cell     = function(value, index) .type_badge(value)
          ),
          ref_level = reactable::colDef(
            name     = "Ref. Level",
            minWidth = 130,
            align    = "left",
            cell     = function(value, index) {
              v <- vars[index]
              if (!is.null(ctypes) && v %in% names(ctypes) && ctypes[[v]] == "factor") {
                col  <- adata[[v]]
                lvls <- if (is.factor(col)) levels(col) else character(0)
                if (length(lvls) == 0) {
                  return(htmltools::tags$span("\u2014", class = "text-muted"))
                }
                htmltools::tags$select(
                  class       = "edark-role-reflevel form-select form-select-sm",
                  `data-var`  = v,
                  style       = "font-size:0.8rem;",
                  lapply(lvls, function(lev) htmltools::tags$option(value = lev, lev))
                )
              } else {
                htmltools::tags$span("\u2014", class = "text-muted")
              }
            }
          ),
          exposure = reactable::colDef(
            header   = .clear_header("Exposure", "exposure"),
            minWidth = 80,
            cell     = .radio_cell("exposure")
          ),
          outcome = reactable::colDef(
            header   = .clear_header("Outcome", "outcome"),
            minWidth = 80,
            cell     = .radio_cell("outcome")
          ),
          candidate = reactable::colDef(
            header = htmltools::tags$div(
              class = "d-flex flex-column align-items-center",
              htmltools::tags$span(style = "font-size:0.75rem;", "Covariate"),
              htmltools::tags$div(
                class = "d-flex gap-2",
                htmltools::tags$button(
                  "All",
                  class = "edark-select-all-candidates btn btn-link btn-sm p-0 text-muted",
                  style = "font-size:0.7rem; line-height:1;"
                ),
                htmltools::tags$button(
                  "Clear",
                  class       = "edark-clear-role btn btn-link btn-sm p-0 text-muted",
                  style       = "font-size:0.7rem; line-height:1;",
                  `data-role` = "candidate"
                )
              )
            ),
            minWidth = 90,
            cell = function(value, index) {
              htmltools::tags$input(
                type        = "checkbox",
                class       = "edark-role-checkbox form-check-input",
                `data-var`  = vars[index],
                `data-role` = "candidate"
              )
            }
          ),
          subject_id = reactable::colDef(
            header   = .clear_header("Subject ID", "subject_id"),
            minWidth = 90,
            cell     = .radio_cell("subject_id")
          ),
          cluster = reactable::colDef(
            header   = .clear_header("Cluster", "cluster"),
            minWidth = 70,
            cell     = .radio_cell("cluster")
          ),
          time = reactable::colDef(
            header   = .clear_header("Time", "time"),
            minWidth = 60,
            cell     = .radio_cell("time")
          )
        )
      )
    })

    # ── Sidebar outputs ──────────────────────────────────────────────────────
    output$action_buttons_ui <- shiny::renderUI({
      adata    <- shared_state$analysis_data
      mismatch <- sig_mismatch()

      if (is.null(adata)) {
        shiny::actionButton(
          ns("btn_start_analysis"),
          label = shiny::tagList(shiny::icon("play"), " Start Analysis"),
          class = "btn-primary w-100"
        )
      } else {
        shiny::tagList(
          shiny::actionButton(
            ns("btn_restart_analysis"),
            label = shiny::tagList(shiny::icon("rotate"), " Restart Analysis"),
            class = if (mismatch) "btn-warning w-100" else "btn-outline-secondary w-100"
          )
        )
      }
    })

    output$study_type_ui <- shiny::renderUI({
      spec <- shared_state$analysis_spec
      if (is.null(spec)) return(NULL)

      st  <- spec$specification_metadata$study_type
      st  <- if (is.null(st)) "descriptive" else st
      cfg <- switch(st,
        exposure_outcome     = list(label = "Exposure-Outcome Study",   cls = "primary"),
        risk_factor          = list(label = "Risk Factor / Association", cls = "success"),
        descriptive_exposure = list(label = "Descriptive (Exposure)",   cls = "warning text-dark"),
        list(label = "Descriptive Cohort", cls = "secondary")
      )

      exp_var <- spec$variable_roles$exposure_variable
      out_var <- spec$variable_roles$outcome_variable
      nudge   <- if (!is.null(exp_var) && is.null(out_var)) {
        shiny::tags$p(
          class = "text-muted small mt-1 mb-0",
          shiny::icon("circle-info"),
          " Exposure assigned but no outcome \u2014 descriptive summaries only."
        )
      } else NULL

      shiny::tagList(
        shiny::tags$p("Study Type",
          class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
        shiny::tags$span(
          class = paste0("badge text-bg-", cfg$cls, " w-100 d-block py-2"),
          style = "font-size:0.8rem; white-space:normal;",
          cfg$label
        ),
        nudge
      )
    })

    output$role_summary_ui <- shiny::renderUI({
      rs <- roles_state()
      if (is.null(rs)) return(NULL)

      outcome    <- names(which(vapply(rs, function(r) isTRUE(r$outcome),    logical(1))))
      exposure   <- names(which(vapply(rs, function(r) isTRUE(r$exposure),   logical(1))))
      candidates <- names(which(vapply(rs, function(r) isTRUE(r$candidate),  logical(1))))
      subject_id <- names(which(vapply(rs, function(r) isTRUE(r$subject_id), logical(1))))

      .row <- function(label, display) {
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", label),
          shiny::tags$span(class = "small fw-semibold", display)
        )
      }

      shiny::tagList(
        shiny::tags$p("Role Summary",
          class = "text-muted small text-uppercase fw-semibold mt-3 mb-1"),
        .row("Outcome",    if (length(outcome) == 0)
                             shiny::span("\u2014", class = "text-muted fw-normal")
                           else outcome[1]),
        .row("Exposure",   if (length(exposure) == 0)
                             shiny::span("\u2014", class = "text-muted fw-normal")
                           else exposure[1]),
        .row("Candidates", if (length(candidates) == 0)
                             shiny::span("\u2014", class = "text-muted fw-normal")
                           else sprintf("%d variable%s", length(candidates),
                                        if (length(candidates) != 1L) "s" else "")),
        .row("Subject ID", if (length(subject_id) == 0)
                             shiny::span("\u2014", class = "text-muted fw-normal")
                           else subject_id[1])
      )
    })

    output$incoming_snapshot_ui <- shiny::renderUI({
      wd <- shared_state$dataset_working
      if (is.null(wd)) return(NULL)

      n_rows <- nrow(wd)
      n_cols <- ncol(wd)
      n_cc   <- sum(stats::complete.cases(wd))

      .row <- function(label, val) {
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", label),
          shiny::tags$span(class = "small fw-semibold", val)
        )
      }

      shiny::tagList(
        shiny::tags$p("Incoming Dataset Snapshot",
          class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
        .row("Rows",           n_rows),
        .row("Variables",      n_cols),
        .row("Complete cases", sprintf("%d (%d%%)", n_cc,
                                       round(n_cc / n_rows * 100L)))
      )
    })

    output$selected_snapshot_ui <- shiny::renderUI({
      adata <- shared_state$analysis_data
      spec  <- shared_state$analysis_spec
      if (is.null(adata) || is.null(spec)) return(NULL)

      vr <- spec$variable_roles
      selected_vars <- unique(Filter(Negate(is.null), c(
        vr$outcome_variable,
        vr$exposure_variable,
        vr$candidate_covariates,
        vr$subject_id_variable,
        vr$cluster_variable,
        vr$time_variable
      )))
      selected_vars <- intersect(selected_vars, names(adata))

      n_rows <- nrow(adata)

      if (length(selected_vars) == 0) {
        return(shiny::tagList(
          shiny::tags$hr(class = "my-2"),
          shiny::tags$p("Selected Dataset Snapshot",
            class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
          shiny::tags$small(class = "text-muted", "No variables assigned yet.")
        ))
      }

      n_cc <- sum(stats::complete.cases(adata[, selected_vars, drop = FALSE]))

      .row <- function(label, val) {
        shiny::div(
          class = "d-flex justify-content-between mb-1",
          shiny::tags$span(class = "text-muted small", label),
          shiny::tags$span(class = "small fw-semibold", val)
        )
      }

      shiny::tagList(
        shiny::tags$hr(class = "my-2"),
        shiny::tags$p("Selected Dataset Snapshot",
          class = "text-muted small text-uppercase fw-semibold mt-2 mb-1"),
        .row("Rows",           n_rows),
        .row("Variables",      length(selected_vars)),
        .row("Complete cases", sprintf("%d (%d%%)", n_cc,
                                       round(n_cc / n_rows * 100L)))
      )
    })

  })
}
