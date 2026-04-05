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
├── module_column_manager.R     Prepare › Columns tab — include/exclude only (no transform controls)
├── module_column_transform.R   Pipeline helpers: .apply_column_transforms, .make_range_labels, .transform_spec_is_valid
├── module_transform_variables.R Prepare › Transforms tab — flat table, one row per numeric col, inline config
├── module_row_filter.R         Prepare › Row Filters tab
├── module_prepare_confirm.R    Apply Changes sidebar — pipeline, validation, navigation
├── module_data_preview.R       Prepare › Data Preview tab — original + working reactables + summary sub-tabs
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
4. Apply column transforms (see transform types below)
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
- Annotation is placed top-right (`x = x_rng[2] - 0.02 * diff(x_rng)`, `y = y_rng[2] - 0.04 * diff(y_rng)`) with `hjust = 1`. **Both stratified and non-stratified paths use `geom_label()` with a one-row data frame** — `annotate("label")` does not accept `label.colour` and will warn. The `geom_label()` path uses `label.colour = "#cccccc"`, `label.size = 0.3`, white fill.

### bar_count specifics
- NA values in the factor column are **dropped before plotting** (`df <- df[!is.na(df[[col_a]]), ]`). This prevents an empty axis slot for `NA` that has no corresponding bar. Do not use `addNA()` or `scale_x_discrete(na.translate = FALSE)` here — just filter.
- Bar order follows natural factor level order. Do **not** reorder by frequency (`fct_infreq`).

### bar_grouped specifics
- Pre-computes a complete `col_a × col_b` grid with zeros for missing combinations. Without this, absent combinations cause remaining bars in a group to expand to double width.
- Strat uses `facet_wrap(scales = "fixed", ncol = ceiling(sqrt(n_strata)))`.

### Plot strategy — facet vs group
All stratified plots use `facet_wrap(scales = "fixed")` so absolute values are comparable across panels. The one exception is **numeric primary + factor stratify** (Describe), which uses overlapping density curves rather than facets.

### Describing a numeric variable (histogram_density)
`.plot_histogram_density()` returns an internal `edark_two_panel` list (`$left`, `$right`). `render_plot()` applies aesthetics to each panel separately, overrides the right panel title to `"Q-Q Plot: {col_a}"`.

**In the Shiny app** (`split_panels = FALSE`, the default): the two panels are combined with `patchwork::wrap_plots(widths = c(0.45, 0.55))` and returned as a single patchwork.

**In reports** (`split_panels = TRUE`): `render_plot()` returns a plain `list(left_p, right_p)` instead of a patchwork. The section builders in `generate_report.R` pass `split_panels = TRUE`. All three assemblers normalise `plot_obj` to a list before iterating — `is.list(x) && !inherits(x, "ggplot")` distinguishes a split-panel list from a single ggplot. Each panel is rendered independently at full size (HTML: two `print()` calls; PPTX: two slides; DOCX: two pages).

| | No stratify | Stratified by factor |
|---|---|---|
| **Left panel** | Histogram + density overlay | Overlapping `geom_density` curves (one colour per stratum) |
| **Right panel** | Pooled Q-Q plot | Q-Q faceted by stratum (`ncol = ceiling(sqrt(n_strata))`) |

Non-stratified left panel: primary Y axis is **Count** (raw histogram bars), density curve is scaled to count units via `after_stat(density) * n * binwidth`. Secondary Y axis shows Density via the inverse transform (`/ (n * binwidth)`). `binwidth ≈ range / 30`.

**Q-Q axis symmetry (critical):** Both Q-Q panels (`$right`) must have identical X and Y axis limits so the 45° reference diagonal is interpretable. Compute `ax_range = range(c(z_range, qnorm(ppoints(n))))` — the union of sample z-score range and expected theoretical quantile range — then apply it to both `xlim` and `ylim` of `coord_cartesian()`. Without this, variables with extreme skew (e.g. bimodal at 0) produce a Y axis that extends to 5 while X stays at ±2, making the plot unreadable.

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

### Transforms tab — flat table renderUI layering
The Transforms tab uses two-level `renderUI`:
1. **`output$transform_table`** — rebuilds only when the **set** of `eligible_cols` changes (not on per-column edits). Renders the full table skeleton including each `selectInput` and a `uiOutput` config cell per column.
2. **`output$config_{col}`** — re-renders only when `input$type_{col}` changes. Renders the inline config inputs for that column's method.

Per-column observers (breakpoints, log base, percentiles, etc.) are registered lazily via `registered_cols` guard — same pattern as `module_row_filter.R`. This prevents double-registration when `eligible_cols` re-fires.

### Row filter observers must be registered lazily with a guard
Row filter input observers (`sliderInput`, `checkboxGroupButtons`) are registered inside a `shiny::observe()` that fires when new filter specs are added. Without tracking which columns already have observers (`registered_cols` vector + `setdiff`), every time `row_filter_specs` changes the observe re-runs and double-registers observers for existing columns — leading to duplicate writes and erratic filter behavior.

### Bootstrap `table-warning` is too saturated
Using `class = "table-warning"` on a `<tr>` applies Bootstrap's full yellow background. For a subtle "this column is transformed" indicator, use a custom CSS class with `rgba(251, 191, 36, 0.08)` instead.

### `shiny::NULL` is not valid R
`NULL` is a base R keyword, not a member of the `shiny` namespace. Writing `shiny::NULL` is a parse error. Just write `NULL`.

### `apply_prepare_pipeline()` uses `isolate()` — reactive callers must create their own dependencies
`apply_prepare_pipeline()` wraps all `shared_state` reads in `shiny::isolate()` so it can be called from both reactive contexts (dimension preview) and non-reactive ones (`downloadHandler`, `edark_report()`). This means a `reactive({})` that only calls `apply_prepare_pipeline(shared_state)` will **never invalidate** — it creates no reactive dependencies.

**Rule:** any reactive that needs to re-run when prepare state changes must read the relevant fields directly before calling the pipeline:

```r
preview_dataset <- shiny::reactive({
  shared_state$included_columns       # dependency
  shared_state$row_filter_specs       # dependency
  shared_state$column_transform_specs # dependency
  tryCatch(apply_prepare_pipeline(shared_state), error = function(e) NULL)
})
```

This bit us in `module_prepare_confirm.R` — the dimension preview showed stale row/col counts until the explicit dependency reads were added.

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

### `annotate("label")` does not accept `label.colour`
`ggplot2::annotate("label", ..., label.colour = "#cccccc")` emits `Ignoring unknown parameters: 'label.colour'`. The `label.colour` argument only works with `geom_label()`. For annotation labels that need separate text and border colours, always use `geom_label()` with a one-row data frame and `inherit.aes = FALSE`. Both scatter_loess paths (stratified and non-stratified) now use this pattern.

### chi-square warning for small expected counts
`chisq.test()` emits a warning when any expected cell count < 5. In `.build_bivariate_fac_fac_table()`, use `suppressWarnings(chisq.test(...))` then check `$expected` — if any < 5, fall back to `fisher.test(simulate.p.value = TRUE, B = 2000)` and note in the footer. Never let chi-square warnings propagate into report generation logs.

---

## Transform logic summary

Transforms are staged and configured entirely in the **Transforms tab** — the Columns tab no longer has transform controls. The tab navigation guard (`edark.R`) blocks leaving the Transforms tab if any staged transform fails validation. `column_transform_specs` is **not cleared** by Apply — specs persist so the table shows the current applied state on return.

`eligible_cols` in `module_transform_variables.R` uses `original_column_types` (never changes), so all initially-numeric included columns always appear in the table regardless of what type they currently have after Apply.

Adding a new transform type requires: (1) new dropdown option in `transform_variables_ui`, (2) new config `renderUI` case, (3) new branch in `.apply_column_transforms()` + `.transform_spec_is_valid()` in `module_column_transform.R`. No other files need changes.

| Method | UI label | Config | Output type | Invalid when |
|---|---|---|---|---|
| `"auto"` | Auto-factor | none | ordered factor | never |
| `"cutpoints"` | Cut-points | breakpoints (req) + labels (opt) | ordered factor | no valid breakpoints in data range |
| `"log"` | Log transform | base: ln / log10 / log2 | numeric | any value ≤ 0 |
| `"winsorize"` | Winsorize | lower % + upper % (defaults 1/99) | numeric | lower ≥ upper |
| `"round"` | Round | decimal places (default 0) | numeric | never |
| `"standardize"` | Standardize (z-score) | none | numeric | SD = 0 |

**Auto-factor**: every unique numeric value becomes one level of an ordered factor (sorted ascending). Recommended for columns with ≤ 20 unique values.

**Cut-points**: user provides comma-separated breakpoints. Breakpoints outside the actual data range are silently dropped. Default labels generated by `.make_range_labels()` in `module_column_transform.R`:
- e.g. breakpoints `c(25, 40)` → `c("< 25", "25 – < 40", "≥ 40")`

**Log**: applies `log()` / `log10()` / `log2()` per chosen base. Blocked if any non-NA value ≤ 0.

**Winsorize**: clamps values to `[quantile(lo%), quantile(hi%)]` using `pmin`/`pmax`. Blocked if lower percentile ≥ upper.

**Round**: `round(x, digits = dp)`. Always valid.

**Standardize**: `(x - mean) / sd`. Falls back to identity if SD = 0 (all values identical).

`.find_invalid_transforms()` in `module_prepare_confirm.R` validates all spec types (not just cut-points) by calling `.transform_spec_is_valid(spec, x)` for each staged column.

---

## Report stage — current behaviour

### Two report types (UI labels vs internal values)
UI labels differ from internal `report_type` string values — do not change the internal values:

| UI label | `report_type` value | Behaviour |
|---|---|---|
| **Describe Variables** | `"all_vars"` | One section per variable (numeric + factor only). Univariate plot + summary table. Optional global stratify adds per-stratum columns to the table. |
| **Correlation** | `"primary_vs_others"` | One bivariate section per secondary variable. Axis assignment and violin_jitter normalisation mirrors `build_bivariate_plot_spec()`. Single global stratify variable applies to all sections. |

### Output formats
All formats open with a **Dataset Summary** page/slide (one row per numeric/factor variable; full wide EDA table), then plot unit(s) + one table unit per section.

- **HTML** (`html`): `rmarkdown::render()` with `inst/report_template.Rmd`. Floating TOC sidebar (box styling stripped via CSS — plain vertical list). Dataset summary rendered as a plain HTML `<table>` (`results='asis'` chunk) with clickable Variable links where a section exists. Section headings carry explicit Pandoc anchor IDs (`{#sec-...}`). Each plot in a section's plot list is `print()`ed individually at full `fig.height`. Back-to-top link after each section. Date shown as ISO `"Date created: yyyy-mm-dd hh:mm"` in the subtitle.
- **PPTX** (`pptx`): `officer` + `rvg`. Dataset summary = 1 slide (full-width flextable). Per section = one slide per plot + one table slide. `rvg::dml()` for plain ggplot; patchwork rasterised to temp PNG via `ggsave()` then inserted as `officer::external_img()`.
- **DOCX** (`docx`): `officer` + `flextable`. Dataset summary page first (heading + table + page break). Per section = one page per plot + one table page. Plain ggplot uses `body_add_gg()`; patchwork uses `ggsave()` + `body_add_img()`. No Word template — uses `officer::read_docx()` default blank (Tier 2 TODO).

### Layout — two output units per section
Plot and table are **never on the same slide/page**. Each section produces a plot unit first, then a table unit. This applies to all three formats.

### Section table contents by type

| Report type | Variable types | Table helper | Content |
|---|---|---|---|
| all_vars | numeric | `.build_univariate_numeric_table()` | Statistic \| Overall \| [Stratum…] — transposed key-value |
| all_vars | factor/logical | `.build_univariate_factor_table()` | Level \| N (Overall) \| % (Overall) \| [N/% per stratum] |
| primary_vs_others | numeric × numeric | `.build_bivariate_num_num_table()` | r, R², p-value, 95% CI from `cor.test()` |
| primary_vs_others | numeric × factor | `.build_bivariate_num_fac_table()` | N/Mean/Median/SD/IQR per factor level + Kruskal-Wallis p |
| primary_vs_others | factor × factor | `.build_bivariate_fac_fac_table()` | Cross-tab N (%) + chi-square p footer (Fisher's exact if expected < 5) |

Datetime columns are excluded everywhere in reports — section builders filter to `column_types %in% c("numeric", "factor")` before iterating.

### Overlap guards — both modes
- **Correlation** (`primary_vs_others`): `.build_primary_vs_others_sections()` skips any secondary variable that equals the stratify variable. Plotting a variable against itself as both a comparison target and a stratifier produces degenerate plots.
- **Describe** (`all_vars`): `.build_all_vars_sections()` removes the stratify variable from the section variable list before iterating. Without this, `bar_count`'s stratified path calls `dplyr::left_join(by = c("col", "col"))` when `col_a == stratify`, which crashes with "Input columns in `x` must be unique."
- **UI (module_report.R)**: In Correlation mode, the stratify variable is also excluded from the variable selection modal, Select All, and the sidebar section count — so the display matches what actually generates.

### Dataset summary table — `.build_dataset_summary()`
One row per numeric/factor column. Columns: Variable, Type, N, N_missing, Pct_miss, N_unique, Min, Max, Mean, SD, Median, IQR, Skewness, Kurtosis (NA for factors), Top_values (NA for numerics — top 5 levels pipe-separated). Styled via `.style_dataset_summary_ft()` for PPTX/DOCX. For HTML, rendered as a plain `<table>` (not flextable) so Variable column can contain raw HTML links.

This same function is also used in `module_data_preview.R` — the Data Preview tab renders summary sub-tabs (Original › Summary and Working › Summary) as reactables via `.render_summary_reactable()`. NA numerics display as em-dash.

### HTML anchor system
`.make_html_anchor(x)` in `generate_report.R` produces consistent anchor IDs:
```r
.make_html_anchor <- function(x) {
  x <- tolower(x); x <- gsub("[^a-z0-9_-]", "-", x)
  x <- gsub("-+", "-", x); x <- gsub("^-+|-+$", "", x)
  paste0("sec-", x)
}
```
The same logic is duplicated as `make_anchor()` in `report_template.Rmd`. Each section object carries an `anchor` field set at build time. Section headings in the Rmd use `{#anchor_id}` syntax. For `all_vars`, anchor = `sec-{variable_name}`. For `primary_vs_others`, anchor = `sec-{secondary_variable_name}` (keyed on the secondary var, not the full "primary × secondary" title, so summary table links can resolve them).

`linked_var_anchors` is a named character vector (var name → anchor ID) passed to the Rmd as a param. For `all_vars`, all section variables are linked. For `primary_vs_others`, only secondary variables are linked — the primary, stratify var, and non-selected variables get plain text in the summary table.

### Progress tracking during generation
`generate_report()` accepts an optional `progress_fn(fraction, detail)` callback. Section builders call it at each iteration. `module_report.R`'s `downloadHandler` wraps the call in `shiny::withProgress()` and passes `shiny::setProgress()` as the callback — this provides real-time step updates in the Shiny progress overlay during synchronous download execution. (`withProgress/setProgress` flush via the progress protocol, unlike reactive updates or `sendCustomMessage` which are blocked during sync execution.)

### Architecture — generate_report.R is Shiny-free
`generate_report()` takes plain R arguments (no `shared_state`, no `shiny::isolate()`). This lets it work from both `downloadHandler` (inside Shiny) and `edark_report()` (outside Shiny). The `progress_fn` defaults to `NULL` and is simply ignored by `edark_report()`.

### Variable selection modal — report tab
`reactiveVal(selected_vars)` initialised to **eligible columns only** (numeric + factor; datetime excluded). In **Correlation** mode, both the primary variable and the stratify variable are excluded from the modal choices (and from Select All) since neither is ever a secondary variable. The summary count in the sidebar mirrors this. Resets on dataset change (after Apply).

### Stratify picker — report tab
The Stratify By card is always visible (both Describe and Correlation modes). In Correlation mode, the primary variable is additionally excluded from the picker's choices. The stratify variable is passed to section builders in both modes — in Describe it adds per-stratum columns to summary tables, in Correlation it facets/colours all bivariate plots.

### Programmatic API
```r
options(pkgType = "binary")  # always set before installing packages

edark_report(liver_tx, report_format = "html", output_path = tempfile(fileext = ".html"))
edark_report(liver_tx, report_type = "primary_vs_others",
             primary_variable = "age_tx", primary_role = "exposure",
             stratify_variable = "graft_type",
             report_format = "pptx", output_path = tempfile(fileext = ".pptx"))
```

### patchwork + rvg::dml incompatibility
`rvg::dml(ggobj = p)` only accepts plain `ggplot` objects, not `patchwork`. In reports, `histogram_density` now uses `split_panels = TRUE` so both panels arrive as plain ggplots — the patchwork is never constructed. Any other future patchwork that reaches an assembler is detected via `inherits(plot_obj, "patchwork")` and rasterised to temp PNG via `ggplot2::ggsave()` then inserted as `officer::external_img()` (PPTX) or `officer::body_add_img()` (DOCX).

---

## What's not built yet

### Todos

#### Tier 1:
- Time-trend feature (datetime columns' only use) — separate UI section (not part of Correlate With); trend numeric variables (mean over time) and factor variables (proportion/count over time) by Day / Month / Quarter / Year, optional stratification as separate coloured lines (run chart style). datetime/POSIXct columns should autocasted via `cast_column_types()` to POSIXct (confirm this is happening). Visualisation: line chart with points.
- Statistical tests in Explore tab for bivariate sections — use appropriate test by variable type combination: numeric × factor → Kruskal-Wallis (with p-value); factor × factor → chi-square or Fisher's (with p-value); numeric × numeric → already has r/R²/p from `cor.test()`. Tests should display in the summary panel in Explore. (Reports already have these via the table helpers.)
- `show_data_labels` aesthetic not yet wired for bivariate plot types (`violin_jitter`, `scatter_loess`, `bar_grouped`) — currently only `bar_count` respects it. For violin_jitter the label should show the median value per group.

#### Tier 2:
- integrate studybuddy stuff to move onwards towards using working dataset for direct model creation and pub quality outputs
- correlation matrix for selecting variable inclusion?
- Word report: create a reference `.docx` template with heading styles defined so `officer` renders `"heading 1"` correctly across Word versions

#### Tier 3:
- Dataset export button (PRD §2.7, DE-01)
- `shinytest2` module tests
- `testthat` unit tests for utility functions
- offer user some options for plot types relevant to var combinations (something about a balloon, maybe a heat map, can ask claude what other types might be helpful or creative)
- custom report generation ("add this graph/plot/table" button)
- Report cancel button — currently not feasible with synchronous `downloadHandler` (the event loop is blocked during sync execution; `observeEvent` cannot fire to set a cancel flag). Would require converting report generation to async (`future`/`promises`) with a separate "Generate" `observeEvent` + subsequent download of a tempfile. Deferred.

#### Tier 4:
- expand aesthetic options
- add outlier detection option in transforms (winsorize is already implemented)
- add imputation possibility?
