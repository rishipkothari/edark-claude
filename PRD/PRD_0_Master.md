# EDARK — Master Product Requirements Document

**Scope:** the whole application — what EDARK is, the principles every part follows, how the app is laid out, and how its parts interact.
**Stage PRDs:** [PRD_1_Prepare.md](PRD_1_Prepare.md) (§P) · [PRD_2_Explore.md](PRD_2_Explore.md) (§E, includes Report) · [PRD_3_Analyze.md](PRD_3_Analyze.md) (§A)
**Implementation details and pitfalls:** [NOTE_implementation.md](NOTE_implementation.md) (§N)

**Section references.** Every section ID carries its document's prefix: §M (this document), §P, §E, §A, §N. A reference such as §A8.6 is unambiguous anywhere in the repo.

**Precedence.** A stage PRD is authoritative for its stage. This document is authoritative for anything that spans stages. If code and PRD disagree, the PRD wins unless the discrepancy is recorded in CLAUDE.md as a known doc issue.

---

## M1 — Overview

### M1.1 Purpose

EDARK is an R package that provides an interactive Shiny GUI for preparing, exploring, reporting on and modelling tabular datasets, focused on clinical and medical research. A researcher calls `edark(dataset)`, shapes the data in **Prepare**, explores variables and relationships in **Explore** (and builds slide/document reports from it), and fits and reports statistical models in **Analyze** — without writing analysis code.

The core functions behind the GUI are pure R functions. The report and model pipelines can be called from a script without launching the app.

### M1.2 Target Users

- **Clinical researchers** who prefer a GUI for routine data work and need output that looks like a published paper.
- **Analysts** who need to characterise a new dataset quickly before scripting.
- **Biostatisticians** who use the app for speed and reproducibility, and need to audit what it did.

Analyze defines three user archetypes (Clinician, Clinician-Researcher, Biostatistician) that apply to the whole app — see §A1.3 and §A2. The rule that follows from them: **serve the Biostatistician without patronising them, and never lose the Clinician.**

### M1.3 The Workflow at a Glance

```
edark(dataset)
   │  validate → auto-cast column types → store original (immutable)
   ▼
1 · Prepare   choose columns, transform variables, filter rows  → Apply → working dataset
   ▼
2 · Explore   Plot:   describe / correlate / trend  (working dataset)
              Report: full or custom PPTX / DOCX / HTML report
   ▼
3 · Analyze   freeze working dataset → roles → Table 1 → variable investigation →
              covariates → model → diagnostics → results → export
```

Navigation between the three tabs is free. The stages form an arc, not a locked sequence.

---

## M2 — Design Principles

### M2.1 Product Principles

1. **No code required.** Every task the app supports can be completed with clicks alone.
2. **Clinical language first.** Framing, labels and messages use the vocabulary of the research question, not of the statistics. Problems are explained in plain language with what to do about them.
3. **No silent decisions.** Every default is visible and can be overridden. The app never recodes, drops or converts data without saying so (e.g. it warns that a numeric variable looks categorical but never factors it silently).
4. **Guide, don't gate — except where a result would be wrong.** Soft nudges steer the user; hard constraints only block combinations that cannot produce a valid result (§A4.4–A4.5).
5. **Publication-ready output.** Tables, figures and reports are formatted to drop into a manuscript or slide deck.
6. **Reproducible.** Decisions are recorded as data (specs), so a run can be described, re-run and exported (§A7.9 code generation; §M8 sessions).

### M2.2 Engineering Principles

1. **Modular.** Every logical UI + server block is a Shiny module with an explicit interface (§M5.1).
2. **One state object.** All session state lives in one `reactiveValues` object, `shared_state`. No `<<-`, no session-global variables (§M5.2).
3. **Pure services.** Computation lives in plain functions that take plain arguments and never touch Shiny: report generation, model fitting, validation, summaries. Modules gather inputs, call services and render.
4. **Specs, not side effects.** User decisions are written to spec objects (`column_transform_specs`, `row_filter_specs`, `plot_specification`, `analysis_spec`). Outputs are computed from specs.
5. **Original data is immutable.** `dataset_original` is set once at launch. Every derived dataset is rebuilt from it.
6. **One statistical engine.** Every p-value and confidence interval is computed in one place (`R/stats_inference.R`) under one set of rules (§A4.2, §N2). Numbers shown in different parts of the app for the same quantity must agree.
7. **One plotting engine.** All plots are static `ggplot2` objects — the same object is shown on screen and written to reports. No plotly, no headless browser.
8. **Public API.** The report pipeline is callable without Shiny (`edark_report()`, `generate_report()`, `generate_custom_report()`).

### M2.3 Deliberate Exceptions

Some parts of the app depart from the defaults above on purpose. New work should follow the defaults unless it fits one of these cases.

| Default | Exception | Where | Why |
|---|---|---|---|
| Recompute on button click (§M3.2) | Aesthetics re-render the current plot live | Explore (§E7) | Cheap: the spec is reused, only styling changes |
| Recompute on button click | Step 4 writes covariates to the spec on every click | Analyze (§A5.3 Step 4) | Selection is cheap to record; the model itself still needs Run |
| Recompute on button click | Preflight validation runs live on every spec change | Analyze (§A8.3) | Users need to see blocking problems before they click Run |
| Free navigation (§M4.2) | Analyze steps are gated | Analyze (§A5) | Later steps have no meaning without a model |
| Staged changes (§M3.1) | Switching Prepare sub-tabs auto-applies staged changes | Prepare (§P7.3) | Keeps Data Preview and downstream tabs in sync with what the user sees |

---

## M3 — Functional Principles

These are behaviours the user can rely on in every part of the app.

### M3.1 Staging and Explicit Apply
Data-shaping changes are **staged** and take effect only when applied. In Prepare nothing touches the working dataset until Apply (§P7). Staged changes survive navigation to other tabs.

### M3.2 Compute on Click
Expensive work (plots, reports, Table 1, variable selection, model fitting, diagnostics, results) runs when the user clicks its button, never on every input change. The exceptions are listed in §M2.3.

### M3.3 Destructive Changes Ask First — and Cancel Undoes
A change that would discard results the user has produced asks for confirmation first:
- Prepare Apply / Reset / sub-tab switch while custom report items exist (§P7.5)
- Analyze role changes, covariate changes after a fit, optimizer changes after a fit (§A8.6)

**Cancel restores the previous state in the UI**, not just in the server, so the screen never shows a choice that was not applied.

### M3.4 Stale State Is Shown, Not Hidden
When upstream data changes, downstream views say so instead of silently showing old results or crashing:
- Explore shows a "dataset has changed" notice after an Apply (§E6).
- Analyze shows a mismatch banner when the working dataset no longer matches the frozen one (§A3.4).
- Custom report items whose columns were removed render a placeholder instead of aborting the report (§E12).

### M3.5 Progress for Long Operations
Report generation and every Analyze run use a **blocking progress modal**: a progress bar plus a detail line, with no close button, removed automatically when the work ends or fails. No `withProgress` toasts.

### M3.6 Consistent Statistics and Formatting
One method per quantity, one formatter per display: p-values display as "< 0.001" or three decimals; estimates and CIs use one formatting rule (§N2). Where two parts of the app report the same kind of test, they use the same function.

### M3.7 Graceful Handling of Imperfect Data
Missing columns, dropped factor levels, and variables that no longer exist are handled by skipping or falling back — with a plain-language message where the user needs to act, silently where they don't. A single bad item never aborts a whole report or load.

---

## M4 — Application Structure

### M4.1 Navigation Layout

`bslib::page_navbar` with three numbered tabs, plus two navbar utilities:

| Tab | Contents | Layout |
|---|---|---|
| **1 · Prepare** | Sub-tabs Columns · Transforms · Row Filters · Data Preview | Left sidebar (Apply) + `navset_card_tab` (§P3) |
| **2 · Explore** | Sub-tabs **Plot** (pills Describe · Correlate · Trend) and **Report** (pills Full Report · Custom Report) | Plot: left sidebar controls + output panel (§E2); Report: §E10 |
| **3 · Analyze** | Nine numbered step pills: Setup · Table 1 · Variable Investigation · Covariate Confirmation · Model Creation · Diagnostics · Performance · Results · Export | `navset_pill` orchestrator (§A5.1) |
| *(navbar right)* | Debug button; light/dark theme toggle | — |

### M4.2 Navigation and Gating
- The three top-level tabs are always reachable.
- Prepare sub-tab switches auto-apply staged changes; invalid transforms block the switch (§P7.3).
- Explore → Report navigation is requested through `shared_state$requested_tab` / `requested_report_subtab` (§M6.4).
- Analyze steps are gated by what exists (§A5, CLAUDE.md "Step gating"): Steps 1–4 always open; Step 5 once the dataset is frozen and an outcome is assigned; Steps 6–9 once a model is fitted. Locked steps show a tooltip explaining what unlocks them.

### M4.3 Entry Points

| Function | Purpose |
|---|---|
| `edark(dataset = liver_tx, max_factor_levels = 20)` | Launch the app. Validates input, auto-casts types (§P2), builds UI and server. |
| `edark(dataset, session = path)` | *Planned* — launch and restore a saved session (§M8.8). |
| `edark_report(data, report_type, variables, primary_variable, primary_role, stratify_variable, report_format, output_path, max_factor_levels)` | Generate a Full Report without the app (§E15). |
| `generate_report()` / `generate_custom_report()` | Shiny-free report builders used by both the app and `edark_report()` (§E15). |

### M4.4 UI Conventions
Layout, action placement and visual hierarchy follow [NOTE_UI-principles.md](NOTE_UI-principles.md). Summary of the recurring patterns:
- Sidebars are flat: no card wrappers; section headers are small uppercase muted labels; one full-width primary button per sidebar.
- Tables with interactive cells use `reactable`, patched in place rather than re-rendered (§N1).
- Disabled controls explain themselves (tooltip or inline message).

---

## M5 — State and Module Architecture

### M5.1 Module Convention
- Every module is `foo_ui(id)` + `foo_server(id, shared_state)`.
- Modules are siblings. No module calls another module's server function; all server calls are in `edark.R`'s `server()`.
- Modules communicate **only** through `shared_state`.
- Private module state (`reactiveVal`) is allowed for UI mechanics (staged selections, pending modals). Anything another module or a saved session needs must live in `shared_state`.

### M5.2 `shared_state` Ownership

`shared_state` is created once per session in `edark.R`'s `server()`. Field groups and their owners:

| Group | Fields | Written by | Read by |
|---|---|---|---|
| Dataset | `dataset_original`, `original_column_types` (set once, never overwritten); `dataset_working`, `column_types` (updated on Apply) | launch; Prepare Apply | everyone |
| Prepare staging | `included_columns`, `column_type_overrides`, `column_transform_specs`, `row_filter_specs`, `has_pending_changes` | Prepare modules | Prepare; Analyze once at freeze (via `last_applied_specs`) |
| Prepare revert | `last_applied_specs`, `revert_trigger` | Prepare Apply / Reset / revert | Prepare modules; Analyze at freeze |
| Explore (Describe / Correlate) | `primary_variable`, `primary_variable_role`, `secondary_variable`, `stratify_variable`, `bar_display` | Explore controls | Explore output |
| Explore (Trend) | `trend_timestamp_variable`, `trend_variable`, `trend_summary_stat`, `trend_resolution`, `trend_stratify_variable`, `trend_zero_baseline`, `trend_impute_zero` | Trend controls | Explore output |
| Plot | `plot_specification`, `active_plot`, `variable_summary`, `explore_needs_refresh` | Explore controls / output; Prepare Apply sets the refresh flag | Explore output |
| Aesthetics | `ggplot_theme`, `color_palette`, `show_data_labels`, `show_legend`, `legend_position` | Explore controls | Explore output |
| Custom report | `custom_report_items`, `requested_tab`, `requested_report_subtab` | Explore output; Report | Report; `edark.R` navigation observer |
| Analyze | `analysis_data`, `analysis_spec`, `analysis_result` | Analyze modules only | Analyze modules only (§M5.3) |
| Session *(planned)* | `session_restore`, `session_loaded_at` | Session module | Analyze Steps 1 and 4 (§M8.10) |

Stage PRDs list their fields in detail: §P10, §E9, §A3.3.

### M5.3 Analysis-Reserved Fields
`analysis_data`, `analysis_spec` and `analysis_result` belong to Analyze. Prepare, Explore and Report never read or write them. Analyze reads Prepare state exactly once — at freeze — and never writes back (§A1.2, §M6.6). The only planned exception is the session module reading `analysis_spec` to save it (§M8.10).

---

## M6 — Module Interactions and Data Flow

### M6.1 Launch
`edark(dataset)` → `validate_input()` → `cast_column_types()` → `detect_column_types()`. The cast dataset becomes both `dataset_original` and the initial `dataset_working`; `column_types` becomes both `original_column_types` and `column_types` (§P2).

### M6.2 Prepare → Working Dataset
Prepare modules stage specs. Apply runs the pipeline **from `dataset_original`** in a fixed order — type overrides → column selection → transforms → row filters (§P7.2) — then sets `dataset_working`, re-detects `column_types`, clears `has_pending_changes`, sets `explore_needs_refresh`, and snapshots `last_applied_specs`.

### M6.3 Explore and Report Consume the Working Dataset
Explore plots and the Report tab always read the current `dataset_working` and `column_types`. They never modify them.

### M6.4 Explore → Report
- **Add to Custom Report** (Explore output) appends a snapshot of the current plot spec plus a thumbnail to `custom_report_items`. Data is not snapshotted — reports re-render items from the working dataset at generation time.
- **View Report** sets `requested_tab` / `requested_report_subtab`; an observer in `edark.R` switches tabs and clears the request.

### M6.5 Stale-Data Guard and Revert
If custom report items exist, an Apply, Reset or Prepare sub-tab switch first warns that the report may be affected (§P7.5). Choosing to revert restores the staged specs from `last_applied_specs` and increments `revert_trigger`; each Prepare module observes it and resyncs its UI.

### M6.6 Prepare → Analyze
- **Start Analysis** (Step 1) copies `dataset_working` into `analysis_data`, appends `.edark_row_id`, stores a dataset signature, and copies `last_applied_specs` plus original/working dimensions into `analysis_spec$specification_metadata$prepare_snapshot`. This is the only time Analyze reads Prepare state.
- If `dataset_working` later changes, Analyze shows a mismatch banner offering to restart (§A3.4). It never follows upstream changes automatically.
- `prepare_snapshot` feeds the Step 5 Summary and (planned) the generated R script, so both can describe how the analysis dataset was produced.

### M6.7 Interaction Diagram

```
                     ┌──────────── dataset_original (immutable) ────────────┐
                     │                                                      │
   Prepare modules ──┴─ staged specs ── Apply ──► dataset_working ──┬──► Explore › Plot ──► custom_report_items ──► Explore › Report
        ▲                                   │                       │                                                   ▲
        │ revert_trigger                    │ last_applied_specs    ├──► Explore › Report (Full) ───────────────────────┘
        └──── stale-data guard ◄────────────┘        │              │
                                                     ▼              ▼
                                         prepare_snapshot ◄── Analyze Step 1 freeze ──► analysis_data / analysis_spec / analysis_result
```

---

## M7 — Outputs and Exports

EDARK produces four kinds of output. They are deliberately separate.

| Output | What it is | Where | Status |
|---|---|---|---|
| **Explore reports** | Full or custom PPTX / DOCX / HTML report of plots and summary tables | Explore › Report (§E10–E14) | Built |
| **Analysis materials** | Tables, figures, methods, report, R script, spec, optional dataset — for publication and reproduction | Analyze Step 9 (§A10) | Planned (Phase 8) |
| **Dataset export** | Working dataset (and optionally original + Prepare spec) as RDS / CSV | Prepare (§P9) | Backlog |
| **Session file** | Saved decisions for resuming work, optionally with data | Session menu (§M8) | Planned (Phase S) |

Single-plot exports (Save Plot, Copy to Clipboard) are in the Explore output panel (§E6).

---

## M8 — Session Save and Load

**Status:** planned — build plan Phase S. Spans Prepare and Analyze.

### M8.1 Purpose

Let a researcher save their setup and pick up where they left off — on the same dataset, or on a new version of it with the same columns (e.g. a refreshed data pull). A session file stores **decisions, not results**. Loading one sets up the app; nothing is fitted or computed. Anything that needs to run (Table 1, variable investigation, the model) is re-run by the user.

This is separate from **materials** (Analyze Step 9, §A10), which exports outputs for publication and reproduction.

### M8.2 What a Session Contains

The minimum session is the work that is slowest to redo by hand:

| Area | Content | Source |
|---|---|---|
| Prepare | Included columns, type overrides, transforms, row filters | `shared_state$last_applied_specs` |
| Analyze Step 1 | Outcome, exposure, candidate covariates, clusters; model purpose and train/test split | `analysis_spec$variable_roles`, `analysis_spec$purpose_specification` |
| Analyze Step 4 | Checked covariates and reference levels. Only saved if Step 4 was used (`final_model_covariates` is not `NULL`) | `analysis_spec$variable_roles` |

**Not in a v1 session:** Explore settings, custom report items, Report settings, Table 1 options, Step 3 settings and results, model settings (including the optimizer), and any fitted object, table, or plot.

Prepare settings that were staged but not yet applied are not saved. A session reflects the last Apply.

### M8.3 File Format

A single `.rds` file with the extension `.edark.rds`, containing a plain named list. It must hold no functions or environments, and nothing from the file is ever run as code.

```r
list(
  session_schema_version = 1L,
  edark_version          = "0.2.x",
  saved_at               = <POSIXct>,
  dataset_definition = list(
    columns       = c(age_tx = "numeric", graft_type = "factor", ...),  # EDARK types, original data
    factor_levels = list(graft_type = c("DBD", "DCD", "LD"), ...)
  ),
  prepare  = list(included_columns, column_type_overrides,
                  column_transform_specs, row_filter_specs),
  analysis = list(                        # NULL if Start Analysis was never clicked
    roles = list(outcome_variable, exposure_variable,
                 candidate_covariates, cluster_variables),
    covariates = list(                    # NULL if Step 4 was not used
      final_model_covariates, reference_levels
    )
  ),
  data = NULL                             # or the original data.frame, if the user chose to include it
)
```

### M8.4 Dataset Definition

The dataset definition describes the **original** dataset (`dataset_original`, after the automatic type casting at launch): each column's name, its EDARK type (numeric / factor / datetime / character — not the R class, so integer vs double never matters), and each factor's levels. It is **not a hash of the data**. Different or additional rows never affect loading.

When a session is loaded, a saved column **still applies** if a column with the same name and the same EDARK type exists in the current dataset. A saved column that is missing, or whose type differs, is treated as absent. Factor levels are never a reason to reject a load; §M8.6 covers them.

This is separate from the full-data hash that Step 1 stores at freeze (`specification_metadata$dataset_signature`), which still drives the "working dataset has changed" banner within a single session.

### M8.5 Schema Versioning

`session_schema_version` describes the session file format, not the app version. It changes only when the file's structure changes.

- **Older file:** upgraded on load by running migration functions in order (`.session_migrate_v1_to_v2()`, then v2→v3, and so on). Every schema change ships with its migration.
- **Newer file** (saved by a later EDARK): refused with *"This session was saved with a newer version of EDARK (x.y.z). Update EDARK to load it."*
- **Unreadable or wrong structure:** refused with *"This file is not a valid EDARK session."*

### M8.6 Partial Loads

A session may be a mid-work save, and it may be loaded onto a different version of the dataset. **Apply whatever still fits, skip whatever doesn't, and don't report what was skipped.**

| Item | Rule |
|---|---|
| Included columns | Keep the saved columns that still apply. Columns new to the dataset are included (the user never excluded them). |
| Type override | Skipped if its column no longer applies. |
| Transform | Skipped if its column no longer applies, or if it is invalid on this data (`.transform_spec_is_valid()`, e.g. log of values ≤ 0). Cut points outside the new range are dropped as usual. |
| Factor row filter | Keep saved levels that still exist. Levels new to the dataset are kept (the user never excluded them). If no saved level survives, the filter is skipped. |
| Numeric row filter | A saved bound that sat at the old data edge (the user did not restrict that side) moves to the new data edge. Any other bound is kept as the user set it, clamped to the new data range. |
| Outcome / exposure | Skipped if the variable no longer applies. |
| Candidates / clusters | Keep the variables that still apply. |
| Covariates | Keep the variables that still apply and are still candidates. |
| Reference level | If the saved level no longer exists, fall back to the first level that does (existing Step 4 behaviour). |

A load is refused only if **no** saved column applies: *"This session does not match this dataset."*

### M8.7 Load Sequence

The load follows the order the user would have worked in. Later stages are handed to their modules as waiting payloads, so no module's reset logic can clear what the load just set.

1. **Confirm.** If the app has any applied Prepare changes or a frozen analysis, show *"Load session? This replaces your current data preparation and analysis setup."* with Cancel / Load.
2. **Read** the file, validate it, upgrade old schemas, and apply the §M8.6 rules against the current `dataset_original`.
3. **Prepare.** Write the adjusted settings into the staged Prepare fields and run the same pipeline Apply uses. Then save them as `last_applied_specs` and increment `revert_trigger`, so every Prepare tab refreshes its UI.
4. **Analyze.** If the session has an `analysis` block, write `shared_state$session_restore <- list(token, roles, covariates)`.
   - **Step 1** sees the payload, freezes the dataset (as if Start Analysis were clicked), applies the roles through its normal path (`.sync_spec()` + `.push_roles_to_table()`), and clears `roles` from the payload. No "Clear Analysis Results?" dialog appears; step 1 of this sequence already confirmed.
   - **Step 4**: when its `roles_key` changes and a `covariates` payload is waiting, it applies the payload only if the spec's current roles match the payload's roles. It then sets its covariate selection from the payload instead of starting empty, and clears the payload. Its existing live-write logic then writes the covariates to the spec.
5. **Navigate** to the furthest stage restored: Analyze Step 4 if covariates were restored, Step 1 if roles were, otherwise Prepare.
6. **Notify** with a toast: *"Session loaded (saved 2026-09-18 14:02)."*

### M8.8 Entry Points

- **In the app:** a **Session** menu on the right of the navbar with *Save session…* and *Load session…*.
  - **Save** shows an "Include dataset" checkbox (off by default) with the note *"Includes patient-level data. Only share where your data governance allows."* The file downloads as `edark_session_YYYY-MM-DD_HHMMSS.edark.rds`.
  - **Load** accepts a session file. Any data inside it is **ignored**; an app session never switches datasets.
- **At launch:** `edark(dataset, session = "path.edark.rds")`.
  - `dataset` given → the session is applied to that dataset, and any data in the file is ignored.
  - `dataset` omitted and the file contains data → that data is launched, then the session is applied.
  - `dataset` omitted and the file has no data → error: *"This session has no data. Call edark(your_data, session = ...)."*

### M8.9 Autosave

- **What:** a session without data. Data is never written automatically.
- **When:** whenever saved content changes (`last_applied_specs`, `variable_roles`, `final_model_covariates`, `reference_levels`), with a ~2 s delay so a burst of clicks becomes one save. It only writes if the content differs from the last autosave. It also saves once when the session ends.
- **Where:** `tools::R_user_dir("edark", "data")/autosave/`. Files are named by a short hash of the dataset definition (not the data), with the newest 10 kept per definition.
- **Resume:** at launch, if an autosave exists for this dataset definition and no `session` argument was passed, show *"Resume your previous session from 2026-09-18 14:02?"* with **Resume** / **Start fresh**. Resume runs the load sequence in §M8.7.

### M8.10 Architecture Notes

- Pure functions (no Shiny) go in `R/service_session.R`: `build_session()`, `read_session()`, `.session_migrate_*()`, `dataset_definition()`, `reconcile_session()` (the §M8.6 rules).
- `R/module_session.R`: `session_ui()` / `session_server()` handle the navbar menu, the save/load modals, autosave, and the resume prompt.
- **An exception to the analysis-field rule (§M5.3):** the session module may read `analysis_spec` to save it. It never writes analysis fields directly; Steps 1 and 4 apply their parts of `shared_state$session_restore` themselves.
- New `shared_state` fields: `session_restore` (the waiting payload, `NULL` when idle) and `session_loaded_at`.

---

## M9 — Technical Foundation

### M9.1 Packages

`DESCRIPTION` is the authoritative list. Grouped by role:

| Role | Packages |
|---|---|
| App framework | `shiny`, `bslib`, `shinyjs`, `shinyWidgets`, `waiter` |
| Data manipulation | `dplyr`, `tidyr`, `tibble`, `lubridate`, `stringr`, `forcats`, `magrittr` |
| Plotting | `ggplot2`, `scales`, `ggpubr`, `ggthemes`, `cowplot`, `see`, `patchwork` |
| Tables | `reactable`, `DT`, `gt`, `gtsummary`, `flextable` |
| Reports and file output | `officer`, `rvg`, `rmarkdown`, `knitr`, `base64enc`, `haven`, `writexl`, `jsonlite`, `zip` |
| Statistics and modelling | `e1071`, `smd`, `lme4`, `lmerTest`, `glmnet`, `broom`, `broom.mixed`, `parameters`, `performance`, `insight`, `correlation`, `lmtest`, `pROC`, `detectseparation` |
| Utilities | `digest` |
| Suggests (dev) | `testthat`, `shinytest2` |

Generated R scripts (planned, §A7.9) load their own packages with `pacman::p_load()`; `pacman` is not an app dependency.

### M9.2 Code Organisation
- `R/edark.R` — entry point, UI, `shared_state`, server wiring, cross-tab navigation.
- `module_*.R` — Shiny modules (one per UI block).
- `service_*.R`, `build_*.R`, `render_plot.R`, `generate_report.R`, `stats_inference.R`, `analysis_utils.R` — pure functions.
- `inst/report_template.Rmd`, `inst/templates/ppt_16x9_blank_template.pptx` — report templates.
- `data/liver_tx.rda` — built-in dataset (§M9.4); regenerated by `data-raw/liver_tx_sample.R`.

The per-file map is in CLAUDE.md.

### M9.3 Coding Conventions
- **Pipe:** `magrittr` `%>%` only — never the base pipe `|>`. Applies to app code and generated scripts.
- **No duplicate definitions:** each function is defined in exactly one file.
- **Documentation:** exported functions documented with roxygen2.

### M9.4 Non-Functional Requirements

| ID | Requirement |
|---|---|
| NF-01 | Installs as a standard R package (`devtools::install()`) |
| NF-02 | `devtools::check()` passes with 0 errors and 0 warnings |
| NF-03 | Exported functions documented with roxygen2 |
| NF-04 | No session-global state; all reactive state in session-scoped `reactiveValues` |
| NF-05 | Usable at a 1280 × 800 viewport |
| NF-06 | Long operations show progress (§M3.5) |
| NF-07 | Pure functions testable with `testthat`; modules testable with `shinytest2` / `chromote` *(test suite is backlog)* |

### M9.5 Built-in Dataset
`liver_tx` — 500 × 36 synthetic liver transplant dataset, the default for `edark()`. It is engineered to exercise every Analyze path (outcomes, clusters, collinearity tiers, a noise block, missingness patterns). Details: §N7.

---

## M10 — Scope

### M10.1 Out of Scope
- Loading data from files, databases or cloud storage — data is passed to `edark(dataset)` in R.
- Multi-dataset merging or joins.
- Real-time or streaming data.
- User accounts or multi-user sessions.
- PDF reports (HTML, PPTX and DOCX only).
- Analyze-specific permanent exclusions: §A11.3.

### M10.2 Deferred and Backlog
- Analyze deferrals by priority: §A11.2.
- App-wide backlog and known bugs: CLAUDE.md "To-dos".
