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
├── data.R                      Roxygen docs for built-in liver_tx dataset
└── data/liver_tx.rda           120-row synthetic liver transplant dataset (default for edark())

inst/
├── report_template.Rmd         Bundled Rmd template for HTML report output
└── templates/
    └── ppt_16x9_blank_template.pptx   Bundled slide template for PPT output
```

---

## Architecture rules (do not violate)

### Shared state
- ALL session state lives in a single `reactiveValues` object called `shared_state`, created inside `server()` in `edark.R`.
- No `<<-`. No session-global variables. No module owns another module's state.
- `shared_state$original_column_types` is set once at launch from `detect_column_types()` and **never overwritten**. After Apply, `shared_state$column_types` is updated from the working dataset — these two diverge intentionally (column manager shows Orig. vs Curr. type).

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
- Progress: optional `progress_fn(fraction, detail)` callback. `module_report.R` wraps in `withProgress`/`setProgress` which flush via the progress protocol during synchronous execution.
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

## What's not built yet

#### High magnitude change
- explore tab -- subtabs describe/correlate/trend
- Alternative plot type options per variable combination (heat map, balloon plot, etc.)
- Word report: reference `.docx` template with defined heading styles
- Integrate studybuddy — use working dataset for direct model creation and publication-quality outputs
- a question to investigate: how does plot theming work if edark_report is called from outside GUI? is there a plot spec variable that contains plot aesthetic data? if so, what happens when func is called without this being present in a reactive variable? is there a check for a default plot spec? i suppose all aspects of external function calls should inspect for reactive variables that are used that are not initialized within the function in a safety check, but this is far down the road -- not critical functionality

#### Mid magnitude change
- Dataset export: save working dataset to RDS, save original dataset and variable transform spec to RDS (or similar), save transformed dataset to CSV
- Statistical tests in Explore › Relationship tab for bivariate plots — numeric × factor → Kruskal-Wallis; factor × factor → chi-square/Fisher's. (Reports already have these via the table helpers; Explore summary panel does not.)
- add univariate table to correlation report (selects logistic vs linear regression vs anova to correlate) but this is also presented in a descriptive table 1 if stratified for exposure or outcome right? whats the difference between the univariate assocations in both of these tables that i know are routinely calculated for different reasons? what am i missing?
- transform --> row filter --> transform does not show warning on stage
- warnings section in apply pane - mimic "stratify by" section header in report:full report pane
- Async report generation (currently synchronous; cancel not feasible without `future`/`promises`)

#### Small magnitude change
- Report contents options Still TODO: correlation matrix option.
- `shinytest2` module tests + `testthat` unit tests
- **Bug — center tables in PPT + HTML reports**: `flextable::set_table_properties(align = "center")` is set in both `.style_dataset_summary_ft()` and `.style_section_ft()` in `generate_report.R` but tables still appear left-aligned in PPT and HTML output. DOCX may work. Investigate `officer` slide content alignment for PPT and the Rmd template's table rendering for HTML.
