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
├── validate_input.R            Input guard called before Shiny launches
├── cast_column_types.R         Auto-cast rules (PRD §4.2) — runs once at launch
├── detect_column_types.R       Returns named char vector: col → "numeric"/"factor"/"datetime"/"character"
├── route_plot_type.R           Type combo → plot type string (PRD §4.3)
├── build_plot_spec.R           build_univariate_plot_spec() / build_bivariate_plot_spec()
├── render_plot.R               All 8 plot types; dispatches from a spec list
├── build_variable_summary.R    Summary stats table for a single variable
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
│
├── data.R                      Roxygen docs for built-in liver_tx dataset
└── data/liver_tx.rda           120-row synthetic liver transplant dataset (default for edark())
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
Plot titles are **not** embedded in the ggplot/plotly object. They are rendered as a `uiOutput("plot_title")` element above the plot card in `module_explore_output.R`. This keeps them reliably clear of facet strips (ggplotly provides no reliable title-to-strip gap control). Format: `col_a [× col_b] [· stratified by stratify_col]`.

### Facet labels
All `facet_wrap()` calls use `labeller = ggplot2::label_both`, which formats strip labels as `"variable = value"`. **Critical:** the formula must be `as.formula(paste("~", stratify))`, not `~ .data[[stratify]]`. The tidy-eval `.data[[]]` syntax prevents `label_both` from extracting the column name, producing `<unknown>` labels.

### Legend defaults and positioning
Default legend position is `"top"`. ggplotly ignores `theme(legend.position)` — legend position is applied post-conversion via `plotly::layout(legend = .plotly_legend_config(position))` in `module_explore_output.R`. `.plotly_legend_config()` maps `"top"/"bottom"/"left"/"right"` to the appropriate plotly orientation/anchor settings.

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
- Correlation stats (R², r, p) are computed via `cor.test()` and formatted as a plain string. `ggpubr::stat_cor` is intentionally **not** used — it outputs plotmath expressions that ggplotly renders as raw text (e.g. `italic(R)~'='~...`).
- Annotation is anchored at `(50% of X range, near top of Y range)` with no hjust/vjust — ggplotly centers text on the anchor coordinates and ignores ggplot2's justification hints, so the anchor IS the text center (see sharp edges).

### bar_grouped specifics
- Pre-computes a complete `col_a × col_b` grid with zeros for missing combinations. Without this, absent combinations cause remaining bars in a group to expand to double width.
- Strat uses `facet_wrap(scales = "fixed", ncol = ceiling(sqrt(n_strata)))`.

### Plot strategy — facet vs group
All stratified plots use `facet_wrap(scales = "fixed")` so absolute values are comparable across panels. The one exception is **numeric primary + factor stratify** (Describe), which uses overlapping density curves rather than facets.

### Describing a numeric variable (histogram_density)
Returns an `edark_two_panel` object (not a ggplot/patchwork) with `$left` and `$right` slots:

| | No stratify | Stratified by factor |
|---|---|---|
| **Left panel** | Histogram + density overlay | Overlapping `geom_density` curves (one colour per stratum) |
| **Right panel** | Pooled Q-Q plot | Q-Q faceted by stratum (`ncol = ceiling(sqrt(n_strata))`) |

Both Q-Q panels standardise the sample first (`scale()`) so theoretical and sample quantile axes are both in z-score units. `coord_cartesian(ylim = ...)` is set from actual data range to prevent plotly from over-expanding the y-axis when `subplot()` reconciles axis domains.

The main title is rendered via `uiOutput("plot_title")` in `module_explore_output.R` (not embedded in the ggplot). `.apply_plot_aesthetics()` does **not** add a title.

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

### patchwork + ggplotly silently drops the second panel
`plotly::ggplotly()` does not understand patchwork's multi-panel layout — it silently renders only the first panel. Never return a patchwork from `render_plot()` if the output is going through `ggplotly()`.

**Fix**: return `structure(list(left = p1, right = p2), class = "edark_two_panel")` instead. In `module_explore_output.R`, detect this class and use `plotly::subplot()` to combine two separately-converted plotly objects.

### ggplotly ignores theme(legend.position)
`plotly::ggplotly()` does not honour ggplot2's `theme(legend.position = ...)`. The legend always appears in its default plotly position regardless.

**Fix**: call `plotly::layout(legend = list(orientation = "h", x = 0.5, xanchor = "center", y = 1.05, yanchor = "bottom"))` on the **final** plotly object (after `subplot()` if applicable).

To suppress a panel's traces from the shared legend (e.g. Q-Q panel in the two-panel numeric plot), use `plotly::style(p, showlegend = FALSE)` on that plotly object **before** passing it to `subplot()`.

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

### ggplotly ignores `guide = "none"` on ggplot2 scales
Setting `guide = "none"` or `guide = "legend"` on `scale_fill_brewer()` / `scale_colour_brewer()` has no effect after `ggplotly()` conversion — plotly regenerates its own legend from the trace data. To suppress a legend in plotly use `plotly::style(pl, showlegend = FALSE)` on the final plotly object. This is separate from the `theme(legend.position)` issue below.

### ggplotly clips annotations placed at `Inf` and ignores hjust/vjust
`annotate("text", x = Inf, y = Inf, hjust = 1.05, ...)` works in ggplot2 (annotations can overflow the panel) but ggplotly clips at the panel boundary, making the text invisible.

Additionally, ggplotly centers text at the anchor coordinates and ignores ggplot2's `hjust`/`vjust` justification hints entirely. The anchor point IS the text center.

**Rule:** position annotation anchors at computed data coordinates where you want the text center to land, with no hjust/vjust override:

```r
x_pos <- x_rng[1] + 0.5 * diff(x_rng)   # horizontal center
y_pos <- y_rng[2] - 0.04 * diff(y_rng)  # near top
annotate("text", x = x_pos, y = y_pos, label = label)
```

### ⚠ Density legend in two-panel numeric + factor stratify — STILL UNRESOLVED
The left density panel legend is not rendering despite multiple fix attempts. What has been tried:
1. `plotly::layout(legend = ...)` on the combined subplot — no effect on whether entries appear
2. Iterating `p_left$x$data` and forcing `showlegend = TRUE` per `legendgroup` — no visible effect

Root cause is not confirmed. Likely candidates: `ggplotly()` sets `layout$showlegend = FALSE` (layout level overrides trace level), or `legendgroup` is not being set by ggplotly for density traces so the loop never fires, or the dual `scale_colour_brewer` + `scale_fill_brewer` mapping causes ggplotly to produce ambiguous trace metadata. Diagnosing requires inspecting the raw plotly object in a live R session.

**This will be resolved by the ggplot-native transition (see TODOs).**

---

## Transform logic summary

**Auto-factor**: every unique numeric value becomes one level of an ordered factor (sorted ascending). Only available when the column has ≤ 20 unique values.

**Cut-points**: user provides comma-separated breakpoints. Breakpoints outside the actual data range are silently dropped. Default labels are generated by `.make_range_labels()` in `module_column_transform.R`:
- e.g. breakpoints `c(25, 40)` → `c("< 25", "25 – < 40", "≥ 40")`

If a column is staged for cut-point transform but has no valid breakpoints, Apply is blocked: a red alert appears in the sidebar and the app navigates to the Transforms tab.

---

## What's not built yet

### ⭐ Next: ggplot-native rendering branch
Replace `plotly::ggplotly()` / `plotly::subplot()` with native ggplot2 rendering throughout `module_explore_output.R`. Use `renderPlot()` / `plotOutput()` instead of `renderPlotly()` / `plotlyOutput()`. Motivation: ggplotly has been a persistent source of bugs (legend suppression, theme ignored, hjust/vjust ignored, annotation clipping, dual-scale ambiguity) that are difficult or impossible to work around reliably. Native ggplot2 honours all of: `theme(legend.position)`, `guide = "none"`, `annotate()` positioning, plot titles, facet strip spacing. The `edark_two_panel` class and `.plotly_legend_config()` helper can be removed. The plotly-specific sharp edges documented above become irrelevant.

Work to do in this branch:
- `module_explore_output.R`: swap `plotlyOutput` → `plotOutput`, `renderPlotly` → `renderPlot`, remove all `plotly::ggplotly()` / `plotly::subplot()` / `plotly::style()` / `plotly::layout()` calls, remove `.plotly_legend_config()`
- `render_plot.R`: the `edark_two_panel` class was introduced only because ggplotly drops patchwork's second panel. With native rendering, the two-panel histogram can use `patchwork` directly — remove the `edark_two_panel` structure and return a patchwork instead
- Restore plot titles into `.apply_plot_aesthetics()` and remove the `uiOutput("plot_title")` shim (or keep it — a Shiny title element above the card is actually cleaner regardless)
- Remove `plotly` from `DESCRIPTION` imports if no longer needed
- The density legend bug resolves automatically

### Other todos

#### Tier 1: 
- **TODO**: Filter datetime/POSIXct columns out of the primary and secondary variable pickers in `module_explore_controls.R` — datetime variables should not be available for correlation/describe; they belong in the trend feature below
- `edark_report()` programmatic API (PRD §2.5, §2.3 PR-01–PR-04)
- Report module UI/server — `3 · Report` tab is a placeholder
- add reset button to prepare
- fix transforms workflow -- still clunky; maybe a table that offers all transform logic in one
- **TODO**: `show_data_labels` aesthetic not yet wired for bivariate plot types (`violin_jitter`, `scatter_loess`, `bar_grouped`) — currently only `bar_count` respects it. For violin_jitter the label should show the median value per group.

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

