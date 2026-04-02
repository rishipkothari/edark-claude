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
└── module_explore_output.R     Explore main panel — plotly output + summary reactable
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

---

## Transform logic summary

**Auto-factor**: every unique numeric value becomes one level of an ordered factor (sorted ascending). Only available when the column has ≤ 20 unique values.

**Cut-points**: user provides comma-separated breakpoints. Breakpoints outside the actual data range are silently dropped. Default labels are generated by `.make_range_labels()` in `module_column_transform.R`:
- e.g. breakpoints `c(25, 40)` → `c("< 25", "25 – < 40", "≥ 40")`

If a column is staged for cut-point transform but has no valid breakpoints, Apply is blocked: a red alert appears in the sidebar and the app navigates to the Transforms tab.

---

## What's not built yet
- `edark_report()` programmatic API (PRD §2.5, §2.3 PR-01–PR-04)
- Report module UI/server — `3 · Report` tab is a placeholder
- Dataset export button (PRD §2.7, DE-01)
- `shinytest2` module tests
- `testthat` unit tests for utility functions
