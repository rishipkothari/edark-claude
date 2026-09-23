#' Shared UI helpers
#'
#' Tag-building helpers, plus the single home for interface strings that must
#' agree in more than one place. Everything here returns tag objects or wires
#' one output; nothing here holds reactive state or calls a module server.
#'
#' Grown one stage at a time by the UI consistency plan
#' (`PRD/BUILD_UI-redesign.md`). Stage 1 adds only what honest locking needs:
#' the lock-reason table and the run button that shows its own reason. Stage 2
#' adds the rest of the component library (`edark_section_label()`,
#' `edark_empty_state()`, `edark_message()`, `edark_button()`, ...).
#'
#' @name ui_helpers
#' @keywords internal
NULL


# ── Lock reasons ──────────────────────────────────────────────────────────────

#' Every "do X first" message, written once
#'
#' A locked step's popover, an in-panel placeholder and a disabled run button's
#' reason text all read from this vector, so the three cannot disagree
#' (§BUILD_UI-redesign Stage 1).
#'
#' Wording rules:
#' \itemize{
#'   \item Name the destination exactly as the navigation shows it -
#'     \code{Step 1 \\u00b7 Setup}, \code{Model \\u203a Create}.
#'   \item Say what to do, not what is wrong: "Fit a model ... first", not
#'     "no model fitted".
#'   \item One sentence, ending in a full stop - the same string has to read
#'     well in a popover, a placeholder and small text under a button.
#' }
#'
#' @keywords internal
#' @noRd
EDARK_LOCK_REASON <- c(
  # Step 1 preconditions
  analysis_start      = "Freeze a dataset in Step 1 \u00b7 Setup first.",
  analysis_roles      = "Assign at least one variable role in Step 1 \u00b7 Setup first.",
  analysis_outcome    = "Freeze a dataset and assign an outcome in Step 1 \u00b7 Setup first.",
  analysis_candidates = "Assign candidate covariates in Step 1 \u00b7 Setup first.",
  analysis_tier1      = "Resolve the Step 1 \u00b7 Setup errors shown above first.",

  # Model preconditions
  model_preflight     = "Resolve the preflight errors before fitting the model.",
  fit_model           = "Fit a model in Model \u203a Create first.",

  # Nothing selected to act on
  pick_check          = "Tick at least one assumption check.",
  pick_measure        = "Tick at least one measure.",
  pick_output         = "Tick at least one output."
)


#' Look up a lock reason
#'
#' Fails loudly on an unknown key so a typo cannot silently produce an empty
#' reason. Always use this rather than subsetting `EDARK_LOCK_REASON` directly.
#'
#' @param key Character. A name of `EDARK_LOCK_REASON`.
#'
#' @return Character scalar.
#' @keywords internal
#' @noRd
edark_lock_reason <- function(key) {
  if (length(key) != 1L || !key %in% names(EDARK_LOCK_REASON)) {
    stop("Unknown lock reason key: ", paste(key, collapse = ", "),
         ". Add it to EDARK_LOCK_REASON in R/ui_helpers.R.", call. = FALSE)
  }
  unname(EDARK_LOCK_REASON[[key]])
}


# ── Run buttons that explain themselves ──────────────────────────────────────

#' A primary run button with a slot for its unmet precondition
#'
#' Renders the button plus an output directly beneath it that carries the
#' reason the button is disabled. Pair it with [edark_run_gate()] in the
#' module server: the button is never re-rendered (so its click count is
#' stable), only its enabled state and the reason text change.
#'
#' Disabled-with-visible-reason is the app's only precondition affordance - a
#' button must not sit enabled and answer a click with a toast
#' (§BUILD_UI-redesign Stage 1).
#'
#' @param ns The module's namespace function (`session$ns` or `shiny::NS(id)`).
#' @param id Character. The button's bare (un-namespaced) id. The reason slot
#'   takes `paste0(id, "_reason")`.
#' @param label Character or tag. The button label - verb + object
#'   ("Fit Model", never "Run").
#' @param icon Character or NULL. Font Awesome name shown before the label.
#' @param variant Character. Bootstrap variant, without the `btn-` prefix.
#'
#' @return A `shiny::tagList`.
#' @keywords internal
#' @noRd
edark_run_button <- function(ns, id, label, icon = "play", variant = "primary") {
  body <- if (is.null(icon)) label else shiny::tagList(shiny::icon(icon), " ", label)
  shiny::tagList(
    shiny::actionButton(ns(id), label = body,
                        class = sprintf("btn-%s w-100", variant)),
    shiny::uiOutput(ns(paste0(id, "_reason")))
  )
}


#' Gate an [edark_run_button()] on a precondition
#'
#' Call once per run button inside `moduleServer()`. Disables the button while
#' `enabled` is false and writes `reason` into the button's reason slot, so the
#' reason is on screen rather than hidden in a tooltip or delivered as a toast
#' after the click.
#'
#' @param output The module's `output` object.
#' @param id Character. The same bare id passed to [edark_run_button()].
#' @param enabled A reactive expression (or plain logical) - TRUE when the
#'   button may be clicked.
#' @param reason A reactive expression returning a character scalar, or a plain
#'   character scalar, from [edark_lock_reason()]. Only read while disabled;
#'   NULL or "" shows no text.
#'
#' @return Invisible NULL, called for its side effects.
#' @keywords internal
#' @noRd
edark_run_gate <- function(output, id, enabled, reason) {
  .value <- function(x) if (is.function(x)) x() else x

  ok <- shiny::reactive(isTRUE(.value(enabled)))

  shiny::observe(shinyjs::toggleState(id, condition = ok()))

  output[[paste0(id, "_reason")]] <- shiny::renderUI({
    if (ok()) return(NULL)
    txt <- .value(reason)
    if (is.null(txt) || !nzchar(txt)) return(NULL)
    shiny::tags$p(class = "edark-run-reason small text-muted mt-2 mb-0",
                  shiny::icon("lock"), " ", txt)
  })

  invisible(NULL)
}
