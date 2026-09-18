# CLAUDE.md — EDARK v0.2

## What this is
An R package providing an interactive Shiny GUI for exploratory data analysis of tabular datasets, focused on clinical research workflows. A researcher calls `edark(dataset)`, prepares the data, explores variables interactively, and optionally exports a report.

Full spec: see `EDARK V0.2 - PRD.md` in the project root.

---

## How to run

```r
devtools::load_all()   # load all R/ source files (use instead of library() during dev)
edark(liver_tx)        # launch with built-in dataset
edark(your_dataframe)

devtools::check()      # must pass with 0 errors, 0 warnings
devtools::document()   # rebuild roxygen2 docs
devtools::install_deps()
```

---

## File map

```
R/
├── edark.R                     Entry point: validates input, casts types, builds UI+server
├── edark_report.R              Programmatic API: edark_report() — no Shiny required
├── validate_input.R            Input guard called before Shiny launches
├── cast_column_types.R         Auto-cast rules — runs once at launch
├── detect_column_types.R       Returns named char vector: col → "numeric"/"factor"/"datetime"/"character"
├── route_plot_type.R           Type combo → plot type string (Analyze tab only)
├── build_plot_spec.R           build_univariate_plot_spec() / build_bivariate_plot_spec() / build_trend_plot_spec()
├── render_plot.R               All 11 plot types; dispatches from a spec list
├── build_variable_summary.R    Summary stats table for a single variable
├── generate_report.R           Core report generation: builds sections, assembles PPT/Word/HTML
│
├── module_column_manager.R     Prepare › Columns tab — include/exclude only
├── module_column_transform.R   Pipeline helpers: .apply_column_transforms, .make_range_labels, .transform_spec_is_valid
├── module_transform_variables.R Prepare › Transforms tab — flat table, one row per numeric col
├── module_row_filter.R         Prepare › Row Filters tab
├── module_prepare_confirm.R    Apply Changes sidebar — pipeline, validation, navigation
├── module_data_preview.R       Prepare › Data Preview tab — original + working reactables + summary sub-tabs
│
├── module_explore_controls.R   Explore › Describe + Relationship tab sidebars — describe_controls_ui/server + relationship_controls_ui/server
├── module_trend_controls.R     Explore › Trend tab sidebar — timestamp/resolution/variable/stat pickers
├── module_explore_output.R     Explore main panel — plot output + summary reactable + "Add to Custom Report" / "View Report" buttons
├── module_report.R             Report tab — Full Report pill (type selector, variable modal, download) + Custom Report pill (gallery, reorder, download)
│
├── module_analysis_main.R          Analyze tab — orchestrator; 8-step navset_pill + JS progress handler + step gating
├── module_analysis_setup.R         Analyze › Step 1: Setup — dataset freeze, role assignment (outcome/exposure/candidates/clusters), study type, reset modal with undo (Phase 1)
├── module_analysis_table1.R        Analyze › Step 2: Table 1 — gtsummary descriptive table (Phase 2)
├── module_analysis_varinvestigation.R   Analyze › Step 3: Variable Investigation — univariable screen, collinearity, stepwise/LASSO (Phase 3)
├── module_analysis_covariate_confirm.R  Analyze › Step 4: Covariate Confirmation — final covariates, reference levels, live missingness; writes to spec on every change (Phase 4)
├── module_analysis_modelspec.R     Analyze › Step 5: Model Specification — Summary tab (audit) + Run Model tab (auto model type, optimizer, live preflight, fit, results) (Phase 5)
├── module_analysis_diagnostics.R   Analyze › Step 6: Diagnostics — residuals, influence, VIF, ROC (Phase 6)
├── module_analysis_results.R       Analyze › Step 7: Results — tables, forest plot, methods paragraph (Phase 7)
├── module_analysis_export.R        Analyze › Step 8: Export — zip assembly, preset selector, download (Phase 8)
│
├── analysis_utils.R                build_analysis_formula() / apply_reference_levels() / compute_complete_cases() / compute_covariate_sample()
├── service_analysis_pipeline.R     reset_analysis_pipeline(shared_state, from_step) — clears downstream state per PRD §8.6
├── service_analysis_validation.R   validate_analysis(spec, data, tier, verbose) — all Tier 1 + Tier 2 preflight checks
├── service_analysis_models.R       Model fitting engines: lm / glm / lmerTest::lmer / lme4::glmer; model options, outcome event, stale check (Phase 5)
├── service_analysis_summary.R      build_analysis_summary() — Step 5 Summary sections, pure, reusable by export (Phase 5)
├── service_analysis_diagnostics.R  Post-fit diagnostic computation (Phase 6)
├── service_analysis_tables.R       gtsummary table generation — Table 1, results, combined table (Phases 2, 7)
├── service_analysis_plots.R        ggplot figure generation — forest plot, residuals, ROC, etc. (Phases 6, 7)
├── service_analysis_variable_selection.R  Univariable screen / stepwise / LASSO (Phase 3)
├── service_analysis_codegen.R      Reproducible R script generator (Phase 5)
├── service_analysis_export.R       Export zip assembly pipeline (Phase 8)
│
├── data.R                      Roxygen docs for built-in liver_tx dataset
└── data/liver_tx.rda           500 × 36 synthetic liver transplant dataset (default for edark())

data-raw/
└── liver_tx_sample.R           Regenerates data/liver_tx.rda — run with Rscript; seeded, reproducible

inst/
├── report_template.Rmd         Bundled Rmd template for HTML report output
└── templates/
    └── ppt_16x9_blank_template.pptx   Bundled slide template for PPT output
```

### UI princples.md 
- available in .claude folder to guide UI development so it's not reinventing the wheel every time, for internal consistency

---

## Architecture rules (do not violate)

### Shared state
- ALL session state lives in a single `reactiveValues` object called `shared_state`, created inside `server()` in `edark.R`.
- No `<<-`. No session-global variables. No module owns another module's state.
- `shared_state$original_column_types` is set once at launch from `detect_column_types()` and **never overwritten**. After Apply, `shared_state$column_types` is updated from the working dataset — these two diverge intentionally (column manager shows Orig. vs Curr. type).
- Three fields are reserved exclusively for the Analysis module — Prepare/Explore/Report never read or write them:
  - `shared_state$analysis_data` — frozen `data.frame` with `.edark_row_id` appended; set on "Start Analysis" click
  - `shared_state$analysis_spec` — named list: full declarative analysis specification (PRD §3.5)
  - `shared_state$analysis_result` — named list: fitted objects, result tables, plots, summaries (PRD §3.6)

### Module convention
- Every module is `foo_ui(id)` + `foo_server(id, shared_state)`.
- Modules are siblings at the server level. No module calls another module's server function.
- All server calls are in `edark.R`'s `server()` function.

### Reactivity discipline
- Data recomputation is triggered by **button clicks**, not by input changes — keeps the app performant and state transitions predictable.
- Aesthetic changes (palette, legend, `trend_zero_baseline`, etc.) are the only exception: they re-render the current plot cheaply without rebuilding the spec. These are read directly from `shared_state` inside `current_plot()` in `module_explore_output.R` and merged over the stored spec via `modifyList()`.
- All changes in Prepare are **staged** — nothing touches `dataset_working` until Apply is clicked.

### Prepare pipeline order (mandatory, do not reorder)
1. Start from `dataset_original`
2. Apply column type overrides
3. Select included columns
4. Apply column transforms
5. Apply row filters

---

## Explore stage

The Explore sidebar has three pill tabs — **Describe**, **Relationship**, and **Trend** — sharing the same output panel (`module_explore_output.R`). All three tabs write to `shared_state$plot_specification`; clicking a plot button overwrites it.

Sidebar styling convention: flat sections (no `card()` wrapper), section headers use `tags$p("LABEL", class = "text-muted small text-uppercase fw-semibold mt-2 mb-1")`, one `btn-primary w-100` CTA per tab, no icons in headers.

### Describe tab (module_explore_controls.R — describe_controls_ui/server)
Eligible columns: numeric + factor only (datetime excluded from pickers here). Provides: primary variable picker, optional stratify, conditional factor statistic picker (count/proportion). One CTA: **Describe** → `build_univariate_plot_spec()`.

### Relationship tab (module_explore_controls.R — relationship_controls_ui/server)

Eligible columns: numeric + factor only. Provides: primary variable picker + role (Exposure/Outcome), secondary variable picker, conditional factor statistic picker, optional stratify. One CTA: **Plot Relationship** → `build_bivariate_plot_spec()`.

Stratify picker: factor columns only; excludes the current primary variable.

`build_bivariate_plot_spec()` assigns axes by role (exposure → primary is X; outcome → primary is Y), then normalises so factor is always X for `violin_jitter`. Routes via `route_plot_type()`:

| column_a type | column_b type | plot type |
|---|---|---|
| factor | factor | `bar_grouped` |
| factor | numeric | `violin_jitter` |
| numeric | factor | `violin_jitter` (axis normalised) |
| numeric | numeric | `scatter_loess` |

### Trend tab (module_trend_controls.R)
Eligible timestamp: datetime columns only. Eligible trend variable: numeric + factor (or "None" for event count).

`build_trend_plot_spec()` sets `plot_type` directly — it **bypasses `route_plot_type()`**:
- No trend variable → `trend_count`
- Numeric trend variable → `trend_numeric`
- Factor trend variable → `trend_proportion`

Resolutions: Hour / Day / Week / Month / Quarter / Year (`.trend_floor_fn()` in `render_plot.R`).

**Stratification behaviour differs by plot type:**
- `trend_numeric` + stratify → coloured lines on one graph (no facets)
- `trend_proportion` + stratify → facet by stratum; factor levels as coloured lines within each facet

Numeric stat options (stored in `shared_state$trend_summary_stat`):
`mean_only`, `mean_sd`, `mean_se`, `mean_ci`, `median_only`, `median_iqr`, `count`, `sum`, `max`, `min`. Stats with intervals (`mean_sd/se/ci`, `median_iqr`) render a `geom_ribbon`; `mean_only` and `median_only` are line+point only.

**Zero baseline** (`shared_state$trend_zero_baseline`): checkbox in the trend sidebar, reactive like aesthetics (re-renders without re-clicking Plot Trend). Defaults to TRUE when no trend variable is selected (count mode), FALSE for numeric/factor variables. Applied via `expand_limits(y = 0)` in all three trend plot functions.

**Impute zero for missing timepoints** (`shared_state$trend_impute_zero`): checkbox shown only when the trend variable is a factor (rendered inside `bar_display_ui`). **Not** reactive — takes effect on the next Plot Trend click. When TRUE, builds a complete time × level (× stratum) grid via `expand.grid` + `left_join` and fills missing `n` with `0L`. When the stat is proportion and all levels at a timepoint are zero (`sum(n) == 0`), proportion is set to 0 (not NaN) via `dplyr::if_else`. Defaults to TRUE.

Trend tab has its own shared_state fields: `trend_timestamp_variable`, `trend_variable`, `trend_summary_stat`, `trend_resolution`, `trend_stratify_variable`, `trend_zero_baseline`, `trend_impute_zero`. These are separate from the Describe/Relationship tab fields (`primary_variable`, `stratify_variable`, etc.).

### Plot types reference

| Plot type | When used | Key behaviour |
|---|---|---|
| `bar_count` | Univariate factor | NA dropped before plotting; natural level order, no fct_infreq |
| `histogram_density` | Univariate numeric | Returns `edark_two_panel` ($left/$right); patchwork in app, split for reports |
| `bar_grouped` | Factor × factor | Pre-computes complete col_a × col_b grid so missing combos show as zero bars |
| `violin_jitter` | Factor × numeric | NA levels shown via addNA(); median marker; legend always suppressed |
| `scatter_loess` | Numeric × numeric | cor.test() annotation via geom_label (not annotate); stratified = colour+facet |
| `trend_count` | Datetime only | Event counts per period |
| `trend_numeric` | Datetime × numeric | All summary stats; ribbon for interval stats; no facets when stratified |
| `trend_proportion` | Datetime × factor | Count per level per period; facets when stratified |

### Plot title & labels
`.apply_plot_aesthetics()` sets title: `col_a [× col_b] [· stratified by stratify_col]`. All `facet_wrap()` calls use `labeller = ggplot2::label_both` and `as.formula(paste("~", stratify))` — **not** `~ .data[[stratify]]` (that breaks `label_both`, producing `<unknown>` strip labels).

### histogram_density split-panel handling
In the Shiny app (`split_panels = FALSE`): patchwork combining left + right at `widths = c(0.45, 0.55)`. In reports (`split_panels = TRUE`): returns `list(left_p, right_p)`. All three report assemblers detect split panels via `is.list(x) && !inherits(x, "ggplot")` and render each independently. Q-Q axes must be symmetric — compute `ax_range = range(c(z_range, qnorm(ppoints(n))))` and apply to both `xlim`/`ylim` of `coord_cartesian()`.

### Legend suppression
Applied in `module_explore_output.R` after `current_plot()` returns (not inside the plot function):
- `violin_jitter` — always suppressed
- `scatter_loess` stratified — always suppressed

---

## Known sharp edges

### Named character vectors crash with `[[` on missing keys
`shared_state$column_types` is a **named character vector**, not a list. Missing key with `[[` throws `subscript out of bounds` (does NOT return `NULL`). Always guard:
```r
curr_type <- if (col %in% names(types)) types[[col]] else fallback
```

### Every shared_state observer must guard with `!identical()`
`renderUI` + input observers can loop: an input change triggers renderUI which re-renders the input which fires the observer again. Without the guard, brief `""` values during re-render overwrite valid data. Every `observeEvent` that writes to `shared_state` needs `if (!identical(old, new))`.

### Inputs removed from the DOM keep their last value
When a `renderUI` stops emitting an input, Shiny **retains that input's last value** in the input registry — `input$foo` keeps returning the stale value indefinitely. `updateXInput(session, "foo", ...)` cannot clear it either, because the message targets an element that no longer exists (or is being removed in the same render pass) and is silently dropped.

Never trust a conditionally-rendered input on its own. Derive eligibility from state, and gate every read:
```r
elig      <- strat_eligible()                                  # from spec + frozen data
strat_exp <- elig$exposure && isTRUE(input$strat_by_exposure)   # not the raw input
```
This caused the Table 1 bug where switching exposure/outcome from factor to numeric still produced tables stratified by a numeric variable. Pure functions downstream (`build_table1()`) should guard independently too — see `.can_stratify()`.

### Interactive inputs inside reactable cells: patch, don't re-render
Steps 1 and 4 render raw HTML inputs in reactable cells and report changes via `Shiny.setInputValue`. Re-rendering the table on every click loses search text and scroll position, and reactable **remounts rows from their original HTML** when a search filter is cleared (so checkbox state silently resets). Pattern: render the table only on structural change (route the trigger through a `reactiveVal`, which ignores identical values — a plain reactive re-fires on every `analysis_spec` write); push live state with `session$sendCustomMessage`; in JS keep the last payload and re-apply it from a `MutationObserver` on a stable wrapper div. Guard every DOM write with a has-it-changed check so the observer doesn't loop.

Two hard rules, because reactable converts cell tags into **React elements** (not HTML): (1) never use valueless attributes like `checked = NA` / `disabled = NA` / `selected = NA` — `NA` serialises to `null` and crashes reactable's renderer, unmounting the whole table (blank panel, error only in the browser console); use strings (`disabled = "disabled"`) and set state from the patch instead; (2) JS may only fill elements React rendered **empty** (e.g. an empty `<select>` or `<span>`) — replacing children React created breaks its next reconciliation. Server-side `testServer` cannot catch either; drive the app with `chromote` (installed) to see client errors. Step 1 uses the same push to undo a role click when the user cancels the reset modal.

### shinyjs needs `useShinyjs()` — it lives in the `page_navbar` header in `edark.R`
Every shinyjs helper depends on it, including `shinyjs::disabled()`, which only adds a `shinyjs-disabled` CSS class that shinyjs's JS turns into a real `disabled` attribute. Remove that call and all disable/toggle logic silently stops working (buttons render clickable).

### Listwise deletion can collapse a factor to one level
A factor with several levels in the full data can have only one left once rows missing *any* other model variable are dropped — `glm`/`lm`/`model.matrix` then fail with "contrasts can be applied only to factors with 2 or more levels". No upfront check can predict this; it depends on the surviving rows. In Step 3, `.prepare_selection_data()` / `.partition_modelable()` in `service_analysis_variable_selection.R` exclude such candidates after complete-casing and return `excluded_variables`, `n_used`, `n_total`, which the UI shows as an amber alert. Any new model-fitting path should do the same.

### Disabling one choice of a radio/select without shinyjs
`shinyjs::toggleState()` / `disable()` act on a whole input by id — they cannot disable a single choice within it. `htmltools::tagQuery` is no help either — its selectors do not support `[attr=value]`. `.disable_choice(tag, value)` in `module_analysis_table1.R` walks the tag tree and sets the boolean `disabled` attribute instead. Note `<option>` tags arrive as a **pre-rendered HTML string** (shiny builds a select's option list via `selectOptions()`), so string children are patched textually — and the select must be built with `selectize = FALSE`, since selectize.js constructs its list in JS and leaves no `<option>` markup to patch.

### `apply_prepare_pipeline()` uses `isolate()` — reactive callers must declare dependencies explicitly
Any `reactive({})` that only calls `apply_prepare_pipeline(shared_state)` will **never invalidate** — the function reads everything via `isolate()`. Callers must read the relevant `shared_state` fields on their own lines first to create dependencies.

### `shiny::isolate()` inside a reactive returns stale values
Read aesthetic (or any) values from `shared_state` once and store them — that single read creates the dependency AND captures the current value. A separate dependency-line + later `isolate()` re-read can return the pre-change value.

### Duplicate function definitions silently use the wrong one
R loads whichever definition was sourced last — no warning. Never define the same function in two files. Shared pipeline helpers live in `module_column_transform.R` only.

### `switch(NULL, ...)` crashes
When `route_plot_type()` returns `NULL`, passing it to `switch()` throws "EXPR must be a length 1 vector". Always NULL-guard `spec$plot_type` before dispatch.

### `annotate("label")` ignores `label.colour`
Use `geom_label()` with a one-row data frame and `inherit.aes = FALSE` instead. `annotate("label")` silently drops `label.colour`.

### Row filter and transform observers must be registered lazily
Both modules use a `registered_cols` guard (`setdiff`) to prevent double-registering observers when the eligible column set re-fires. Without this, every reactive update to the spec list re-registers all existing observers, causing duplicate writes.

### chi-square on small expected counts
In `.build_bivariate_fac_fac_table()`: `suppressWarnings(chisq.test(...))`, then if any expected cell < 5 fall back to `fisher.test(simulate.p.value = TRUE, B = 2000)`. Never let chi-square warnings reach report generation logs.

### patchwork + rvg::dml incompatibility
`rvg::dml()` only accepts plain ggplot objects. `histogram_density` uses `split_panels = TRUE` in reports so the patchwork is never constructed. Any other patchwork reaching a report assembler is rasterised via `ggsave()` + `external_img()` / `body_add_img()`.

---

## Transform logic

Transforms are staged in the **Transforms tab** only. `column_transform_specs` persists through Apply so the table reflects the current applied state on return. The tab navigation guard blocks leaving with invalid transforms. `eligible_cols` uses `original_column_types` (never changes) so all initially-numeric columns always appear.

Adding a new transform type: (1) new dropdown option in `transform_variables_ui`, (2) new config `renderUI` case, (3) new branch in `.apply_column_transforms()` + `.transform_spec_is_valid()` in `module_column_transform.R`. No other files need changes.

| Method | Output type | Invalid when |
|---|---|---|
| `"auto"` (Auto-factor) | ordered factor | never |
| `"cutpoints"` | ordered factor | no valid breakpoints in data range |
| `"log"` | numeric | any value ≤ 0 |
| `"winsorize"` | numeric | lower percentile ≥ upper |
| `"round"` | numeric | never |
| `"standardize"` | numeric | SD = 0 |

Cut-point labels from `.make_range_labels()`: e.g. `c(25, 40)` → `c("< 25", "25 – < 40", "≥ 40")`. Breakpoints outside the data range are silently dropped.

---

## Report stage

### Report types
The Report tab has two pill tabs: **Full Report** and **Custom Report**.

**Full Report** — auto-generated from the working dataset:

| UI label | `report_type` value | Behaviour |
|---|---|---|
| **Describe Variables** | `"all_vars"` | One section per numeric/factor variable. Univariate plot + summary table. Optional stratify adds per-stratum columns. |
| **Correlation** | `"primary_vs_others"` | One bivariate section per secondary variable. Single global stratify applies to all. |

Datetime columns are excluded from both Full Report types.

**Custom Report** — user-curated from the Explore tab:
- "Add to Custom Report" button (top-right of plot panel) appends the current plot spec + PNG thumbnail to `shared_state$custom_report_items`.
- "View Report" button navigates to the Report tab via `shared_state$requested_tab` (observed in `edark.R`, calls `bslib::nav_select()`).
- Custom Report pill shows a thumbnail gallery with up/down reorder arrows and remove buttons.
- Preview panel in the main area shows a thumbnail grid of queued items.
- `generate_custom_report()` in `generate_report.R` is the Shiny-free entry point; reuses all three existing assemblers (`.assemble_pptx()`, `.assemble_docx()`, `.assemble_html()`).
- Trend plot items: plot only, no table (consistent with Full Report behaviour).
- If a column referenced in a custom item was removed after adding, `.build_custom_report_sections()` traps the error per-item and renders a placeholder rather than aborting.
- PNG thumbnails are saved to `tempdir()` and cleaned up via `session$onSessionEnded` in `edark.R`.

### Report contents options (Full Report only)
Two checkboxes in the sidebar between "Select Variables" and "Output Format":
- **Dataset Summary** (default on): one row per numeric/factor variable across the whole dataset. When unchecked the dataset summary slide/page is omitted entirely.
- **Table One** (default off, only shown in Describe Variables mode): classic clinical Table 1 — one row per numeric variable (mean ± SD + Kruskal-Wallis p) and multi-row for factor variables (N per level + chi-square/Fisher's p). Rendered before the dataset summary. Stratification follows the sidebar Stratify By picker; columns are `Overall (N=X)`, one per stratum, and `p-value`. Built by `.build_tableone_df()` / `.style_tableone_ft()` in `generate_report.R`. `generate_report()` accepts `include_dataset_summary` and `include_tableone` flags (both default safe for backward-compatible programmatic API calls).

### Output formats
All formats optionally open with a **Table One** and/or **Dataset Summary**, then plot + table per section. Plot and table are **never on the same slide/page**.

- **HTML**: `rmarkdown::render()` with `inst/report_template.Rmd`. Floating TOC, plain `<table>` for dataset summary (so Variable column accepts raw HTML links), Pandoc anchor IDs (`{#sec-...}`) on headings, back-to-top links.
- **PPTX**: `officer` + `rvg`. Plain ggplot via `rvg::dml()`; patchwork rasterised to temp PNG.
- **DOCX**: `officer` + `flextable`. No Word template (Tier 2 TODO).

### Section table helpers
| Report type | Variable types | Content |
|---|---|---|
| all_vars | numeric | Statistic \| Overall \| [Stratum…] |
| all_vars | factor | Level \| N \| % \| [per stratum] |
| primary_vs_others | num × num | r, R², p, 95% CI from `cor.test()` |
| primary_vs_others | num × fac | N/Mean/Median/SD/IQR per level + Kruskal-Wallis p |
| primary_vs_others | fac × fac | Cross-tab N (%) + chi-square / Fisher's p |

### Overlap guards
- `primary_vs_others`: skips secondary == stratify variable.
- `all_vars`: removes stratify variable from section list before iterating (prevents self-join crash in `bar_count`).
- Report UI: stratify var excluded from variable modal in Correlation mode.

### HTML anchor system
`.make_html_anchor(x)` → `"sec-"` + lowercased, non-alphanumeric replaced with `-`. Same logic as `make_anchor()` in `report_template.Rmd`. For `primary_vs_others`, anchor is keyed on the secondary variable name (not the full title) so summary table links resolve correctly.

### Architecture notes
- `generate_report()` and `generate_custom_report()` are both Shiny-free (take plain R args, no `shared_state`). Work from both `downloadHandler` and programmatic API.
- Progress: optional `progress_fn(fraction, detail)` callback. `module_report.R` shows a **blocking modal** (`showModal(easyClose = FALSE)`) with an animated Bootstrap progress bar and detail text. The JS custom message handler `edark_report_progress` (registered in `report_ui`) drives bar width and detail text via `session$sendCustomMessage`. `on.exit(shiny::removeModal(), add = TRUE)` ensures cleanup. The Analysis module uses the same pattern with handler name `edark_analysis_progress` (registered in `analysis_main_ui`).
- `custom_report_items` list structure: `list(id, plot_spec, thumb_path, title, added_at)`. `plot_spec` is a snapshot at add-time (aesthetics frozen); dataset is re-rendered from current `dataset_working` at generation time.
- Dynamic observers for gallery up/down/remove use the same lazy-registration + `local({})` closure pattern as `module_row_filter.R`. `registered_item_ids` reactiveVal prevents double-registration.
- Stale-data guard: clicking Apply, Reset, or navigating Prepare sub-tabs (auto-apply) when `custom_report_items` is non-empty shows a modal. "Cancel & Revert Changes" calls `.revert_to_last_applied()` which restores `included_columns`, `column_type_overrides`, `column_transform_specs`, `row_filter_specs` from `shared_state$last_applied_specs` and increments `shared_state$revert_trigger`. Modules observe `revert_trigger` to sync their UIs (column_manager via `updateCheckboxInput`, transform_variables via `updateSelectInput`, row_filter by clearing `registered_cols`). `last_applied_specs` is snapshotted after every successful Apply or Reset via `.snapshot_last_applied_specs()`.

### Programmatic API
```r
options(pkgType = "binary")  # always set before installing packages

edark_report(liver_tx, report_format = "html", output_path = tempfile(fileext = ".html"))
edark_report(liver_tx, report_type = "primary_vs_others",
             primary_variable = "age_tx", primary_role = "exposure",
             stratify_variable = "graft_type",
             report_format = "pptx", output_path = tempfile(fileext = ".pptx"))
```

---

## Analysis stage

Tab 4 (`4 · Analyze`) — an 8-step guided workflow for fitting and reporting statistical models. Full spec: `PRD/EDARK_Analysis_Module_PRD.md`. Build sequence: `PRD/EDARK_Analysis_Build_Plan.md`.

### Current state
Phases 0–5 complete (infrastructure, Setup, Table 1, Variable Investigation, Covariate Confirmation, Model Specification), including the pre-Phase 5 refactor: subject ID and time roles removed in favour of a multi-select **cluster** role, random slopes removed, Step 4's Confirm button removed (live writes), Step 3 stepwise/LASSO hold the exposure. Steps 6–8 are placeholder stubs. The R code generator (`service_analysis_codegen.R`) is deferred. The PRD and build plan are updated for all of this (build plan marks Phases 4–5 complete "as built" and adds a deferred Phase 5b for the code generator); where they ever disagree, the PRD wins.

### Test data for Phase 3
`liver_tx` (500 × 36) is built to exercise variable investigation. Regenerate via `Rscript data-raw/liver_tx_sample.R` (seeded).

- **Outcomes**: `ead` (logical → 2-level factor, ~28% prevalence) for logistic; `postop_los_days` for linear.
- **Cluster**: `transplant_center` — 12 unbalanced centers with real random intercepts. Deliberately above the `PF_FEW_CLUSTERS` threshold (<10) and below `PF_UNBALANCED_CLUSTERS` (size CV >1), so neither fires by default; induce both with a row filter.
- **Collinearity tiers**: `preop_meld` ↔ `preop_meld_na` (r 0.92, VIF ~10); `recipient_bmi` = weight/height² (VIF 41–151); `intraop_ebl_ml` ↔ `intraop_rbc_units` (r 0.92); `preop_meld` vs its three component labs (VIF ~5 — the MELD formula is on the log scale, so it is only moderately *linearly* redundant).
- **Noise block (zero effect on every outcome)**: `donor_blood_type`, `donor_height_cm`, `or_room_number`, `surgery_start_hour`, `preop_ferritin`, `referral_source`. Verified: backward/forward stepwise (BIC) and LASSO (`lambda.1se`) all retain 0 of 6.
- **Weak-but-real**: `preop_sodium` survives a liberal univariable screen, dropped by BIC. Use it to test p-threshold sensitivity.
- **Missingness**: `preop_ferritin` 35% (trips `PF_MISSING_GT20`), `donor_age` 12%, `preop_albumin` 8%, `intraop_max_lactate` 5%, `preop_inr` 3%. `postop_aki_stage` NA means *no AKI*, not missing — including it in a model guts the complete-case n.

### Pipe mandate
**Use `magrittr` `%>%` exclusively throughout all analysis module code and generated R scripts. Never use the base R pipe `|>`.**

### Architecture overview
- **Consumer only**: the Analysis module reads `shared_state$dataset_working` and `shared_state$column_types` at freeze time. It never writes back to any Prepare or Explore field.
- **Spec-driven**: `analysis_spec` is the single source of truth for model fitting, code generation, and export. Every user decision is encoded in the spec before execution.
- **Result-cached**: `analysis_result` stores all fitted objects, tables, and plots. Export reads from cache — no recomputation.
- **Dataset frozen**: clicking "Start Analysis" copies `dataset_working` → `analysis_data` with `.edark_row_id` appended. A mismatch banner detects upstream Prepare changes and prompts restart.

### Utility functions (`analysis_utils.R`)
- `build_analysis_formula(spec)` — assembles formula from `variable_roles`; for mixed models appends one `(1 | cluster)` per entry in `cluster_variables`. No random slopes.
- `apply_reference_levels(data, reference_levels)` — calls `stats::relevel()` per spec before any model fit
- `compute_complete_cases(data, variables)` — returns `list(data, n_excluded)`; always uses `na.action = na.omit` logic
- `compute_covariate_sample(data, outcome, exposure, covariates, candidates, cluster_vars)` — Step 4's live listwise-deletion summary: row counts (base / fixed / mixed), per-variable row cost, factor levels surviving in the complete rows, EPV, and `issues` (`error`: outcome/exposure/checked covariate left with < 2 levels or no variation — shown in Step 4, blocks the model via Step 5 preflight; `warning`: EPV < 10, > 20% rows dropped, a cluster with < 2 values)
- `.default_model_design()` (`service_analysis_pipeline.R`) — the one place the `model_design` block is built (freeze + resets)

### Step gating (`module_analysis_main.R`)
Steps 1–4 are always reachable (each shows its own guidance when Step 1 is incomplete). Step 5 opens once the dataset is frozen and an outcome is assigned — Table 1, variable investigation and covariate selection are all optional (nothing checked in Step 4 = exposure-only model). Steps 6–8 open once `analysis_result$fitted_models$primary_model` exists. Locking adds Bootstrap's `disabled` class to the nav link (via `shinyjs::toggleClass`) with a tooltip on the parent `<li>`. Step 5's Run Model is gated only by the Tier 2 preflight.

### Roles (`variable_roles`)
One role per variable: `outcome_variable` and `exposure_variable` (single-select, radios), `candidate_covariates` and `cluster_variables` (multi-select, checkboxes). **No subject ID, time, or random-slope fields exist** — a subject ID is just a cluster. Each cluster variable is one random intercept; several = nested or crossed groupings. Any non-datetime column may be a cluster (Step 5 converts with `factor()` at fit time). Assigning clusters commits the analysis to a mixed model — a non-mixed model with clusters assigned is a preflight **error** (`PF_CLUSTERS_UNUSED`).

### Step 1 — role changes (`module_analysis_setup.R`)
- `RADIO_ROLES` (outcome, exposure) / `MULTI_ROLES` (candidate, cluster). JS mirrors this: `.edark-role-radio` vs `.edark-role-checkbox`, both carrying `data-role`; checking any role clears the variable's other roles. Cluster cells render "—" for datetime columns.
- A role change asks for confirmation ("Clear Analysis Results?") when anything downstream exists: `analysis_result` is non-NULL **or** `final_model_covariates` is non-empty. Confirm → `reset_analysis_pipeline(shared_state, 1)` then apply the change.
- **Cancel undoes the click**: the table's inputs have already changed in the browser, so `.push_roles_to_table()` sends `roles_state` back via the `sync_roles` custom message and JS restores every radio/checkbox/ref-level. The same push runs after every applied change, and JS re-applies it when reactable remounts rows (search filter cleared).
- `.sync_spec()` writes only when a Step 1-owned field actually changed. It sets `final_model_covariates` to `NULL` (covariates start unselected — deviation from the original PRD, now updated).
- Spec fields created at freeze: `specification_metadata$roles_version` (0) and `specification_metadata$step1_roles` (Step 1's snapshot).

### Step 3 — guards and exposure (`module_analysis_varinvestigation.R`, `service_analysis_variable_selection.R`)
- No candidate covariates → red banner in the Univariable and Stepwise/LASSO pills, Run buttons disabled (`.has_candidates()`); Collinearity shows a placeholder. The selection services return `NULL` silently in that case, so the UI must guard.
- **Exposure held** (exposure-outcome studies): stepwise uses `~ exposure` as the scope floor and null model; LASSO sets `penalty.factor = 0` on the exposure's columns. The exposure is never in `selected_variables`; results carry `held_variables` and the UI notes it. The univariable screen stays unadjusted (it is the "unadjusted" column of the Phase 7 combined table). Variable names are mapped from `terms()` labels / `model.matrix` `assign` — never `startsWith()` (a candidate that prefixes another name would steal its terms).

### Step 4 — Covariate Confirmation (`module_analysis_covariate_confirm.R`)
- Layout: table in the main panel, right sidebar with Model/Sample counts (with a separate "If mixed model" row count when clusters exist) and Checks. **No Confirm button, no status/pending state.**
- Role variables (outcome, exposure, each cluster) are locked, checked rows at the top; candidates start **unchecked**. Include header has **All** / **Clear**.
- Row cost column: checked → rows the variable is costing now; unchecked → rows lost by adding it; cluster → rows lost to the mixed model.
- Method columns (Univariable / Stepwise / LASSO): green ✓ suggested (univariable shows the smallest term p), pink — not suggested, grey not run / `n/a` excluded. Header **Add** only adds checks (no modal); **Replace** swaps the selection for the method's list (modal).
- Reference-level dropdowns list only levels present in the complete rows for the current selection; a preferred level that drops out falls back to the first surviving level (amber icon). Clusters are grouping factors and get no reference level.
- **Live commit**: a commit observer writes `final_model_covariates`, `reference_levels` (outcome, exposure, checked covariates — effective levels), and `variable_selection_specification$selected_variables` whenever the staged selection or its surviving levels change. Errors are written anyway; Step 5's preflight blocks the model.
- **Every edit goes through `.propose()`**. If a model exists, the first edit opens "Clear Model Results?"; Cancel re-sends the current patch (undoing the click in the browser), Clear & Continue runs `reset_analysis_pipeline(shared_state, 4)` then applies it. `patch()` is a reactive so Cancel can re-push it.
- **Staged selection carries its `roles_key`** (`created_at` + `roles_version`). The reset observer clears the selection when the key changes; the commit observer only writes when `staged()$key` matches the current key. Without this, observer ordering after a Step 1 role change could write the old selection into the new spec.
- Step 3 reruns no longer affect Step 4 beyond refreshing the suggestion columns (`run_seq` / `.bump_run_seq()` were removed).

### Step 5 — Model Specification (`module_analysis_modelspec.R`)
- Two tabs (`navset_underline`): **Summary** (first) and **Run Model**.
- **Model type is automatic**: `analysis_model_options(spec, data)` returns all four types with `available` / `reason`; exactly one is available for a supported outcome (family from `analysis_outcome_type()`, mixed iff clusters assigned). An observer writes it to `model_design$model_type` (NULL for an unsupported outcome). The dropdown is display-only — others are disabled via `.disable_choice()` with the reason in their label.
- **Optimizer** (mixed only, Advanced accordion) is the only Step 5 setting. Changing it after a fit does **not** clear the model — `analysis_fit_is_stale(spec, result)` compares model inputs against `analysis_result$specification_snapshot` and the UI shows a stale banner.
- **Preflight is live** (`validate_analysis(verbose = TRUE)` on every spec change). Sidebar shows errors + warnings; the Summary tab shows everything including passes. No Run Preflight button, no verbose checkbox, **no warning modal** on Run.
- **Pulse**: Bootstrap gives disabled buttons `pointer-events: none`, so a click on disabled Run Model lands on its wrapper `#run_wrap`; JS adds `.edark-pulse` to `#preflight_box`.
- **Run**: `fit_analysis_model(spec, data)` inside the blocking progress modal → `reset_analysis_pipeline(shared_state, 4)` (clears the previous fit and anything downstream) → writes `specification_snapshot`, `run_status` (status, fitted_at, error, n_used, n_total, formula, outcome_event, reference_levels, preflight warnings, run_messages), `fitted_models$primary_model`, `inference_summary$coefficients / fit_statistics / predicted_values`. A failed fit stores `status = "failed"` and no model.
- `.analysis_progress_modal()` lives in `module_analysis_varinvestigation.R` and is shared.

### Model fitting (`service_analysis_models.R`)
- Model data: complete cases over outcome + predictors (+ clusters if mixed) → **ordered factors made unordered** (treatment contrasts, not `.L`/`.Q` polynomial terms — Auto-factor and cut-point transforms produce ordered factors) → reference levels → `droplevels` → clusters `factor()`.
- Coefficients come from `summary(model)$coefficients` for all four engines; Wald CI = est ± 1.96·SE. **Don't use `confint.default()` on a merMod** — `coef()` of a merMod is per-group, not the fixed effects. Terms map to variables via the model matrix `assign` attribute (`lme4::getME(model, "X")` for mixed), never by name prefix.
- `summary()` of an `lmerTest::lmer` fit gives Satterthwaite p-values only because lmerTest's S3 method is registered — always fit linear mixed models with `lmerTest::lmer`, not `lme4::lmer`.
- Warnings/messages are captured with `withCallingHandlers` + `tryCatch`, never thrown. Convergence and separation warnings get plain-language hints (`.explain_fit_warning()`); lme4's "boundary (singular) fit" message is replaced by our own singular-fit warning.
- `analysis_outcome_event(spec, data)` → the event level for a binary outcome (the non-reference level) — drives "Modelling: ead = TRUE (vs FALSE)".

### Summary (`service_analysis_summary.R`)
`build_analysis_summary(spec, result, data, validation)` → list of sections `list(id, title, rows)`, each row `list(label, value, items, level)`. Current state only (not a click log). Data preparation comes from `specification_metadata$prepare_snapshot`, which Step 1 copies from `shared_state$last_applied_specs` (+ original columns/dims, working dims) at freeze — the only time Analysis reads Prepare state.

### Validator (`service_analysis_validation.R`)
`validate_analysis(spec, data, tier = "full", verbose = FALSE)` — pure function, no Shiny.

Returns `list(validity_flag, messages, display_messages)` where `validity_flag` is `"valid"` / `"warnings"` / `"invalid"`.

**Tier 1** (core data validity — runs before any analysis operation): `PF_NO_OUTCOME`, `PF_ZERO_COMPLETE`, `PF_OUTCOME_NO_VARIANCE_BINARY`, `PF_OUTCOME_NO_VARIANCE_CONTINUOUS`, `PF_FACTOR_SINGLE_LEVEL` (exposure only).

**Tier 2** (model specification — adds to Tier 1, runs before multivariable model): errors: `PF_NO_PREDICTORS`, `PF_OUTCOME_MODEL_MISMATCH`, `PF_MIXED_NO_CLUSTER`, `PF_MIXED_SINGLE_CLUSTER` (per cluster), `PF_CLUSTERS_UNUSED` (clusters assigned + non-mixed model), `PF_FACTOR_SINGLE_LEVEL` (covariates, checked on the full-model complete cases); warnings: `PF_LOW_EPV_10`, `PF_LOW_EPV_5`, `PF_MISSING_ANY/GT20/GT50`, `PF_RARE_FACTOR_LEVEL`, `PF_HIGH_CORRELATION`, `PF_FEW_CLUSTERS`, `PF_UNBALANCED_CLUSTERS` (both per cluster), `PF_CLUSTER_IDS_SHARED` (≥ 2 clusters: values of the finer one recur under several values of the coarser — merged clusters if IDs are only unique within the parent, harmless if crossed), `PF_RARE_OUTCOME`, `PF_EXPOSURE_NOT_IN_MODEL`; notes (verbose only): `PF_SINGLE_COVARIATE`, `PF_SAMPLE_SUMMARY`, `PF_MODEL_SUMMARY`, `PF_DATA_STRUCTURE`, `PF_REFERENCE_LEVELS`.

Also Tier 2: error `PF_OUTCOME_UNSUPPORTED` (outcome neither numeric nor 2-level factor); warning `PF_LOOKS_CATEGORICAL` (numeric outcome/predictor with ≤ 10 distinct whole-number values, `.PF_CATEGORICAL_MAX_VALUES`; the app never factors silently).

Tier 1 complete-cases over outcome + exposure only. Tier 2 adds predictors, plus clusters only when the model is mixed.

Return value also has `checks_run` and `passed` (pass messages from `.PF_PASS_LABELS`). **Adding a check**: call `.ran("PF_CODE")` where it is evaluated, add a pass label to `.PF_PASS_LABELS`, and if it is a stricter variant of another code map it in `.PF_GROUP_HEAD`.

### Pipeline reset (`service_analysis_pipeline.R`)
`reset_analysis_pipeline(shared_state, from_step)` — called by modules after user confirms a destructive upstream change. Never shows its own modal.

| `from_step` | Clears |
|---|---|
| `1` | Entire `analysis_result`; resets `variable_selection_specification` and `model_design` in spec; sets `final_model_covariates` to `NULL` |
| `4` or `5` | Fitted model, run status, result tables/plots, inference summary, generated script from `analysis_result`; step 5 also resets `model_design` in spec |

### Model types and `model_type` values
| UI label | `model_type` value | Outcome type | Cluster variables |
|---|---|---|---|
| Linear regression | `"linear"` | continuous | must be none |
| Logistic regression | `"logistic"` | binary factor (2 levels) | must be none |
| Linear mixed model | `"linear_mixed"` | continuous | ≥ 1 required |
| Logistic mixed model | `"logistic_mixed"` | binary factor (2 levels) | ≥ 1 required |

Step 5 selects the model automatically from outcome type + whether clusters are assigned.

All CIs are Wald-based (`confint.default()`). All p-values are model-native (t-tests for lm, Wald z for glm/glmer, Satterthwaite df for lmerTest::lmer).

### Study type derivation (Step 1)
Derived from role assignments; displayed as a persistent badge:

| Exposure assigned | Outcome assigned | `study_type` value |
|---|---|---|
| Yes | Yes | `"exposure_outcome"` |
| No | Yes | `"risk_factor"` |
| Yes | No | `"descriptive_exposure"` |
| No | No | `"descriptive"` |

### Blocking modal pattern (Analysis module)
Same structure as `module_report.R`. JS handler `edark_analysis_progress` is registered in `analysis_main_ui`. In each step module's run button handler:
```r
shiny::showModal(shiny::modalDialog(
  title = shiny::tagList(spinner, "Running..."),
  progress_bar_div,   # id = "edark_analysis_progress_bar"
  detail_p,           # id = "edark_analysis_progress_detail"
  footer = NULL, easyClose = FALSE
))
on.exit(shiny::removeModal(), add = TRUE)
# ... long computation ...
session$sendCustomMessage("edark_analysis_progress", list(frac = 0.5, detail = "Fitting model..."))
```

---

## What's not built yet

#### In progress
- **Analysis module** (Phases 1–9): Phases 0–5 complete; Steps 6–8 are placeholder stubs. R code generator (`service_analysis_codegen.R`) deferred — Step 5's R Code Preview is a placeholder; it should consume `prepare_snapshot` + the spec. Step 5 stores coefficients + fit stats only (gtsummary tables are Phase 7). See `PRD/EDARK_Analysis_Build_Plan.md` for phase definitions and acceptance criteria.

#### High magnitude change
- Alternative plot type options per variable combination (heat map, balloon plot, etc.)
- Word report: reference `.docx` template with defined heading styles
- Integrate studybuddy — use working dataset for direct model creation and publication-quality outputs

#### Mid magnitude change
- Dataset export: save working dataset to RDS, save original dataset and variable transform spec to RDS (or similar), save transformed dataset to CSV
- Statistical tests in Explore › Relationship tab for bivariate plots — numeric × factor → Kruskal-Wallis; factor × factor → chi-square/Fisher's. (Reports already have these via the table helpers; Explore summary panel does not.)
- transform → row filter → transform does not show warning on stage
- warnings section in apply pane — mimic "stratify by" section header in report:full report pane
- Async report generation (currently synchronous; cancel not feasible without `future`/`promises`)

#### Small magnitude change
- Report contents options still TODO: collinearity investigation option.
- `shinytest2` module tests + `testthat` unit tests
- **Bug — center tables in PPT + HTML reports**: `flextable::set_table_properties(align = "center")` is set in both `.style_dataset_summary_ft()` and `.style_section_ft()` in `generate_report.R` but tables still appear left-aligned in PPT and HTML output. DOCX may work. Investigate `officer` slide content alignment for PPT and the Rmd template's table rendering for HTML.

#### Analysis module debugging
- Univariable screen flags a multi-level factor as suggested if *any* level term clears the threshold; an overall likelihood-ratio p per variable would be more correct (`service_analysis_variable_selection.R`).
- collinearity plot base size should be similarly scaled to # of variables; still too small when theres just a few
- **EPV is computed two ways**: Step 4 / Summary (`compute_covariate_sample`) divides events by *parameters* (a 3-level factor = 2); the validator's `PF_LOW_EPV_*` divides by *predictors* (a factor = 1), so the validator is more lenient. Pick one (parameters is the usual convention).
- **`PF_LOOKS_CATEGORICAL` may be noisy** on genuine small counts (e.g. transfusion units 0–8). Threshold is `.PF_CATEGORICAL_MAX_VALUES` (10) in `service_analysis_validation.R`.
- **`postop_aki_stage` conflates "no AKI" with "missing"** — `NA` means the patient had no AKI, but every complete-case path reads it as missing. Including it as a covariate silently drops ~62% of rows and trips `PF_MISSING_GT50`. Consider splitting into a `has_aki` logical plus stage-among-those-with-AKI.