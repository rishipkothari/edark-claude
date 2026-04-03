# CLAUDE.md — EDARK v0.2

## What this is
An R package providing an interactive Shiny GUI for exploratory data analysis of tabular datasets, focused on clinical research workflows. A researcher calls `edark(dataset)`, prepares the data, explores variables interactively, and optionally exports a report.

Full spec: see `EDARK V0.2 - PRD.md` in the project root.

---

## How to run

```r
# Load all R source files into the session (use instead of library() during dev)
devtools::load_all()

# Launch the app
edark(mtcars)
edark(your_dataframe)

# Check the package (must pass with 0 errors, 0 warnings)
devtools::check()

# Rebuild documentation from roxygen2 comments
devtools::document()

# Install all dependencies listed in DESCRIPTION
devtools::install_deps()
```

---

## File map

```
R/
├── edark.R                     Entry point: validates input, casts types, builds UI+server
├── edark_report.R              Programmatic API: edark_report() — no Shiny required
├── validate_input.R            Input guard called before Shiny launches
├── cast_column_types.R         Auto-cast rules (PRD §4.2) — runs once at launch
├── detect_column_types.R       Returns named char vector: col → "numeric"/"factor"/"datetime"/"character"
├── route_plot_type.R           Type combo → plot type string (PRD §4.3)
├── build_plot_spec.R           build_univariate_plot_spec() / build_bivariate_plot_spec()
├── render_plot.R               All 8 plot types; dispatches from a spec list
├── build_variable_summary.R    Summary stats table for a single variable
├── generate_report.R           Core report generation: builds sections, assembles PPT/Word/HTML
│
├── module_column_manager.R     Prepare › Columns tab — include/exclude + transform checkboxes
├── module_column_transform.R   Pipeline helpers only: .apply_column_transforms, .make_range_labels
├── module_transform_variables.R Prepare › Transforms tab — accordion of staged transform configs
├── module_row_filter.R         Prepare › Row Filters tab
├── module_prepare_confirm.R    Apply Changes sidebar — pipeline, validation, navigation
├── module_data_preview.R       Prepare › Data Preview tab — original + working reactables
│
├── module_explore_controls.R   Explore sidebar — variable pickers, Describe/Plot buttons
├── module_explore_output.R     Explore main panel — plot output + summary reactable
├── module_report.R             Report tab — type selector, variable modal, download handler
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
- `shared_state$original_column_types` is set once at launch from `detect_column_types()` and **never overwritten**. After Apply, `shared_state$column_types` is updated from the working dataset — these two can diverge (that's intentional — it's how the column manager shows Orig. vs Curr. type).

### Module convention
- Every module is `foo_ui(id)` + `foo_server(id, shared_state)`.
- Modules are siblings at the server level. No module calls another module's server function.
- All server calls are in `edark.R`'s `server()` function.

### Reactivity discipline
- Data recomputation is triggered by **button clicks**, not by input changes. This is intentional — keeps the app performant and state transitions predictable.
- Aesthetic changes (palette, legend, etc.) are the only exception: they re-render the current plot cheaply without rebuilding the spec.
- All changes in Prepare are **staged** — nothing touches `dataset_working` until Apply is clicked.

### Prepare pipeline order (mandatory, do not reorder)
1. Start from `dataset_original`
2. Apply column type overrides
3. Select included columns
4. Apply column transforms (numeric → ordered factor)
5. Apply row filters

---

## Explore stage — current behaviour

### Stratify picker
Only factor columns (ordered and unordered, both classified as `"factor"` by `detect_column_types()`) appear in the stratify picker. Numeric, datetime, and character columns are excluded. The current primary variable is also excluded.

### Bivariate correlation plot types
`build_bivariate_plot_spec()` assigns axes based on the primary variable's role (exposure → primary is X / column_a; outcome → primary is Y / column_b), then calls `route_plot_type()` with the resulting `column_a_type|column_b_type` key.

**Special case — mixed numeric/factor:** `build_bivariate_plot_spec()` normalises the axis assignment after the role-based swap so that the factor is always `column_a` (X) and the numeric is always `column_b` (Y), regardless of role. This is required because `.plot_violin_jitter()` always reads col_a as X.

| column_a type | column_b type | plot type |
|---|---|---|
| factor | factor | `bar_grouped` |
| factor | numeric | `violin_jitter` |
| numeric | factor | `violin_jitter` (axis normalised — see above) |
| numeric | numeric | `scatter_loess` |
| datetime | numeric | `trend_mean` |
| datetime | factor | `trend_proportion` |

All stratified bivariate plots use `facet_wrap(scales = "fixed", ncol = ceiling(sqrt(n_strata)))`. The one exception is `scatter_loess` which maps stratify to colour and still facets (coloured points + coloured loess curves per facet).

### Plot title rendering
Plot titles are embedded in the ggplot object by `.apply_plot_aesthetics()` via `labs(title = ...)`. Format: `col_a [× col_b] [· stratified by stratify_col]`. The `edark_two_panel` Q-Q right panel overrides its title to `"Q-Q Plot: {col_a}"` in `render_plot()` after aesthetics are applied, so it is self-contained for reporting.

### Facet labels
All `facet_wrap()` calls use `labeller = ggplot2::label_both`, which formats strip labels as `"variable = value"`. **Critical:** the formula must be `as.formula(paste("~", stratify))`, not `~ .data[[stratify]]`. The tidy-eval `.data[[]]` syntax prevents `label_both` from extracting the column name, producing `<unknown>` labels.

### Legend defaults and positioning
Default legend position is `"top"`. `.apply_plot_aesthetics()` applies `theme(legend.position = spec$legend_position)` directly — native ggplot2 honours this. Legend suppression for certain plot types is applied in `renderPlot` after `current_plot()` returns, via `+ theme(legend.position = "none")`.

Plots where legend is always suppressed regardless of user toggle:
- `violin_jitter` — axes + facet strips are sufficient
- `scatter_loess` stratified — facet strips label each stratum

### violin_jitter specifics
- `col_a` is always the factor (X); `col_b` is always the numeric (Y).
- NA factor levels are made explicit via `addNA()` and relabelled `"NA"` so they appear on the X-axis rather than being silently dropped.
- A median marker (`stat_summary`, shape 21, white fill, black border) is drawn on top of each violin.
- Legend always suppressed — X-axis labels and facet strips make it redundant.

### scatter_loess specifics
- Non-stratified: single loess smoother with SE band, hardcoded blue palette.
- Stratified: colour aesthetic mapped to stratify, coloured loess + SE per group, faceted.
- Correlation stats (R², r, p) are computed via `cor.test()` and formatted as a plain string. `ggpubr::stat_cor` is intentionally **not** used — it outputs plotmath expressions that render as raw text rather than formatted output.
- Annotation is placed top-right (`x = x_rng[2] - 0.02 * diff(x_rng)`, `y = y_rng[2] - 0.04 * diff(y_rng)`) with `hjust = 1`. Uses `annotate("label")` / `geom_label()` with white fill and `#cccccc` border (`label.size = 0.3`) so it doesn't compete with points or the loess line.

### bar_grouped specifics
- Pre-computes a complete `col_a × col_b` grid with zeros for missing combinations. Without this, absent combinations cause remaining bars in a group to expand to double width.
- Strat uses `facet_wrap(scales = "fixed", ncol = ceiling(sqrt(n_strata)))`.

### Plot strategy — facet vs group
All stratified plots use `facet_wrap(scales = "fixed")` so absolute values are comparable across panels. The one exception is **numeric primary + factor stratify** (Describe), which uses overlapping density curves rather than facets.

### Describing a numeric variable (histogram_density)
`.plot_histogram_density()` returns an internal `edark_two_panel` list (`$left`, `$right`). `render_plot()` applies aesthetics to each panel separately, overrides the right panel title to `"Q-Q Plot: {col_a}"`, then combines them with `patchwork::wrap_plots(widths = c(0.45, 0.55))`. The caller always receives a patchwork — `edark_two_panel` never escapes `render_plot()`.

| | No stratify | Stratified by factor |
|---|---|---|
| **Left panel** | Histogram + density overlay | Overlapping `geom_density` curves (one colour per stratum) |
| **Right panel** | Pooled Q-Q plot | Q-Q faceted by stratum (`ncol = ceiling(sqrt(n_strata))`) |

Non-stratified left panel: primary Y axis is **Count** (raw histogram bars), density curve is scaled to count units via `after_stat(density) * n * binwidth`. Secondary Y axis shows Density via the inverse transform (`/ (n * binwidth)`). `binwidth ≈ range / 30`.

Both Q-Q panels standardise the sample first (`scale()`) so theoretical and sample quantile axes are both in z-score units. `coord_cartesian(ylim = ...)` is set from actual data range to keep the Y axis tight.

### Factor bar ordering
Bar charts preserve the natural factor level order. Do **not** reorder by frequency (`fct_infreq`).

---

## Known sharp edges

### Named character vectors crash with `[[` on missing keys
`shared_state$column_types` and `shared_state$original_column_types` are **named character vectors** (returned by `vapply`), not lists. Accessing a missing key with `[[` throws `subscript out of bounds` — it does NOT return `NULL` like a list would. Always guard with `col %in% names(vec)` before indexing.

```r
# WRONG — crashes if col was excluded and is absent from column_types
curr_type <- current_types[[col]]

# RIGHT
curr_type <- if (col %in% names(current_types)) current_types[[col]] else orig_type
```

This bit us in `module_column_manager.R` when unchecking a column after Apply had rebuilt `column_types` from the (now smaller) working dataset.

### Duplicate function definitions cause silent wrong behavior
During development, `.apply_column_transforms()` existed in both `module_column_transform.R` (correct, uses `.make_range_labels()`) and `module_prepare_confirm.R` (stale copy, used `paste0("Level ", ...)`). R uses whichever was sourced last — no warning, no error, wrong output. The stale copy in `module_prepare_confirm.R` was the one that ran, causing cut-point labels to always show "Level 1 / Level 2" regardless of breakpoints.

**Rule:** never define the same function in two files. If a pipeline helper is shared, it lives in one file (currently `module_column_transform.R`) and is called from everywhere else.

### Observer feedback loops with renderUI + textInput
When a `textInput` value is saved to `shared_state`, it can trigger a `renderUI` that re-renders the input with the same value — which fires the observer again. Without an `!identical()` guard this loops silently, and on some iterations the input value is briefly `""` (empty string), which overwrites valid breakpoints with `numeric(0)`.

**Rule:** every observer that writes to `shared_state` must guard with `!identical(current_value, new_value)` before writing.

```r
observeEvent(input$cutpoints_col, {
  parsed <- ...
  s <- shared_state$column_transform_specs
  if (!is.null(s[[col]]) && !identical(s[[col]]$breakpoints, parsed)) {
    s[[col]]$breakpoints <- parsed
    shared_state$column_transform_specs <- s
  }
})
```

### Transform accordion collapses when method toggle re-renders
If the accordion `renderUI` depends on `shared_state$column_transform_specs` directly, toggling the method (auto ↔ cutpoints) updates the spec, which triggers a full accordion re-render, which collapses the open panel. 

The fix in `module_transform_variables.R`: use a separate `reactiveVal(transform_structure)` that only fires when the **set of staged columns** changes (not when method/breakpoints/labels change). The per-column cut-point inputs are separate `renderUI` outputs keyed on method alone — so toggling method only re-renders that inner section, not the accordion shell.

### Row filter observers must be registered lazily with a guard
Row filter input observers (`sliderInput`, `checkboxGroupButtons`) are registered inside a `shiny::observe()` that fires when new filter specs are added. Without tracking which columns already have observers (`registered_cols` vector + `setdiff`), every time `row_filter_specs` changes the observe re-runs and double-registers observers for existing columns — leading to duplicate writes and erratic filter behavior.

### Bootstrap `table-warning` is too saturated
Using `class = "table-warning"` on a `<tr>` applies Bootstrap's full yellow background. For a subtle "this column is transformed" indicator, use a custom CSS class with `rgba(251, 191, 36, 0.08)` instead.

### `shiny::NULL` is not valid R
`NULL` is a base R keyword, not a member of the `shiny` namespace. Writing `shiny::NULL` is a parse error. Just write `NULL`.

### `shiny::isolate()` inside a reactive returns stale aesthetic values
When a `reactive()` reads a value to create a dependency (e.g. `shared_state$color_palette` on its own line), then re-reads the same value later with `shiny::isolate()`, the `isolate()` call can return the pre-change value. This caused palette changes to visually trigger a re-render (waiter appeared) but the plot colours didn't update.

**Rule:** read aesthetic values from `shared_state` directly once, storing them in local variables. That one read both creates the dependency and captures the current value.

```r
# WRONG — isolate() may return stale value even though dependency fired
shared_state$color_palette   # dependency line
...
color_palette <- shiny::isolate(shared_state$color_palette)  # stale!

# RIGHT — one read, one dependency, always current
color_palette <- shared_state$color_palette
```

### `switch(NULL, ...)` crashes with "EXPR must be a length 1 vector"
When `route_plot_type()` returns `NULL` for an unsupported type combination, passing that `NULL` directly to `switch()` throws this error. Always NULL-guard `spec$plot_type` before dispatching.

```r
if (is.null(spec$plot_type)) {
  return(.plot_warning_card("Unsupported variable type combination ..."))
}
plot_fn <- switch(spec$plot_type, ...)
```

---

## Transform logic summary

**Auto-factor**: every unique numeric value becomes one level of an ordered factor (sorted ascending). Only available when the column has ≤ 20 unique values.

**Cut-points**: user provides comma-separated breakpoints. Breakpoints outside the actual data range are silently dropped. Default labels are generated by `.make_range_labels()` in `module_column_transform.R`:
- e.g. breakpoints `c(25, 40)` → `c("< 25", "25 – < 40", "≥ 40")`

If a column is staged for cut-point transform but has no valid breakpoints, Apply is blocked: a red alert appears in the sidebar and the app navigates to the Transforms tab.

---

## Report stage — current behaviour

### Two report types
- **All Variables** (`report_type = "all_vars"`): one section per variable; univariate describe plot + summary stats table. No stratification.
- **Primary vs All Others** (`report_type = "primary_vs_others"`): one bivariate section per secondary variable. Axis assignment and violin_jitter normalisation mirrors `build_bivariate_plot_spec()`. Single global stratify variable applies to all sections.

### Output formats
- **PPT** (`pptx`): `officer` + `rvg`. Layout: title bar top, plot left 60% (`rvg::dml()` for ggplot, raster PNG fallback for patchwork), flextable right 40%.
- **Word** (`docx`): `officer` + `flextable`. Heading 1 per section, `body_add_gg()` raster plot, flextable summary, page break between sections.
- **HTML** (`html`): `rmarkdown::render()` with `inst/report_template.Rmd`. Sections loop via `results='asis'`. Self-contained output with floating TOC.

### Architecture — generate_report.R is Shiny-free
`generate_report()` takes plain R arguments (no `shared_state`, no `shiny::isolate()`). The spec lists are built inline from `column_types` directly. This lets it work from both `downloadHandler` (inside Shiny) and `edark_report()` (outside Shiny).

### Programmatic API
```r
edark_report(liver_tx, report_format = "html", output_path = tempfile(fileext = ".html"))
edark_report(liver_tx, report_type = "primary_vs_others",
             primary_variable = "age_tx", primary_role = "exposure",
             report_format = "pptx", output_path = tempfile(fileext = ".pptx"))
```

### Variable selection modal
The module uses a `reactiveVal(selected_vars)` initialised to all working dataset columns. A `modalDialog` with `checkboxGroupInput` + Select All / Deselect All buttons lets users subset variables without consuming sidebar space. `selected_vars` resets when the working dataset changes (after Apply).

### patchwork + rvg::dml incompatibility
`rvg::dml(ggobj = p)` only accepts plain `ggplot` objects, not `patchwork`. The `histogram_density` plot type returns a patchwork from `render_plot()`. In `.assemble_pptx()` this is detected via `inherits(plot_obj, "patchwork")` and the plot is rasterised to a temp PNG via `ggplot2::ggsave()` before insertion as `officer::external_img()`.

---

## What's not built yet

### Todos

#### Tier 1:
- **TODO**: Filter datetime/POSIXct columns out of the primary and secondary variable pickers in `module_explore_controls.R` — datetime variables should not be available for correlation/describe; they belong in the trend feature below
- add reset button to prepare
- fix transforms workflow — still clunky; maybe a table that offers all transform logic in one
- **TODO**: `show_data_labels` aesthetic not yet wired for bivariate plot types (`violin_jitter`, `scatter_loess`, `bar_grouped`) — currently only `bar_count` respects it. For violin_jitter the label should show the median value per group.
- **TODO**: Fix console warning in `.plot_scatter_loess()` (`render_plot.R`) when plotting numeric × numeric: `Ignoring unknown parameters: 'label.colour' and 'label.size'` from `ggplot2::annotate("label", ...)`. The `label.colour` and `label.size` params are not valid for `annotate()` — replace with the correct ggplot2 equivalents (`colour` for border colour, `label.size` → `label.padding` or just remove if not needed).

#### Tier 2:
- **TODO**: Time-trend functionality — separate UI section (not part of Correlate With); user wants ability to trend numeric variables (mean over time) and factor variables (proportion/count over time) by Day / Month / Quarter / Year, with optional stratification shown as separate colored lines (run chart style). Visualisation: line chart with points. This is distinct from the existing `trend_count` / `trend_mean` / `trend_proportion` plot types which are bivariate correlations — the trend feature is a standalone workflow.
- integrate studybuddy stuff to move onwards towards using working dataset for direct model creation and pub quality outputs
- correlation matrix for selecting variable inclusion?

#### Tier 3:
- Dataset export button (PRD §2.7, DE-01)
- `shinytest2` module tests
- `testthat` unit tests for utility functions
- offer user some options for plot types relevant to var combinations (something about a balloon, maybe a heat map, can ask claude what other types might be helpful or creative)
- custom report generation (add this graph button)

#### Tier 4:
- expand aesthetic options
- add outlier detection and winsorization option in transforms
- add imputation possibility?

