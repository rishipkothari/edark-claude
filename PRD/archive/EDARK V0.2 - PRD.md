# Product Requirements Document
## EDARK v2 — Exploratory Data Analysis GUI

*Ground-up rewrite. All decisions in this document supersede edark v0.1.0.*
*Prepared: 2026-03-31*

---

## 1. Overview

### 1.1 Purpose

EDARK is an R package that provides an interactive Shiny GUI for exploratory data analysis (EDA) of tabular datasets, with a focus on clinical and medical research workflows. A researcher passes a pre-loaded dataset to `edark(dataset)`, manipulates it through a structured preparation stage, explores variables and their relationships through interactive visualizations, and optionally generates a publication-quality report — all without writing analysis code.

The same core functions that power the GUI are exported as a public API, allowing power users to generate plots and reports programmatically from a clean R script.

### 1.2 Target Users

- Clinical researchers and biostatisticians who prefer a GUI for routine EDA
- Analysts who need to quickly characterize a new dataset before writing analysis scripts
- Teams producing slide decks or documents for clinical presentations

### 1.3 Design Principles

1. **Modular**: Every logical UI+server block is a Shiny module with an explicit, testable interface. Modules are siblings — none owns another's server logic.
2. **No global mutation**: All shared state lives in a single `reactiveValues` object scoped to the session. No `<<-`.
3. **Explicit confirmation over auto-reactivity**: Data re-computation triggered by button clicks, not by every input change. This keeps the app performant on large datasets and makes state transitions predictable.
4. **Staged preparation**: Column selection, variable transformation, and row filtering are configured independently and applied atomically in a single pipeline. Users can navigate freely between the Prepare and Explore stages; staged (unapplied) changes persist until confirmed or discarded.
5. **Natural workflow**: The UI mirrors the arc of an analysis — prepare the data, explore it, report on it — surfaced as three top-level navigation stages.
6. **Single plotting engine**: `ggplot2` is used for all plot construction. `plotly::ggplotly()` wraps ggplot objects for interactive on-screen display. Static ggplot objects are used directly for report export. No dual rendering pipeline, no headless browser, no Python dependency.
7. **Public API**: All core functions (plot construction, summary statistics, report generation) are exported and usable without launching the GUI.

---

## 2. Functional Requirements

### 2.1 Application Entry Point

| ID | Requirement |
|----|-------------|
| EP-01 | The primary entry point is `edark(dataset, max_factor_levels = 20)` where `dataset` is a required `data.frame` or `tibble` |
| EP-02 | On launch, columns are auto-cast using deterministic rules (see §4.2) and the original dataset is stored as an immutable reference |
| EP-03 | A secondary entry point `edark_report(...)` generates reports programmatically without launching the GUI (see §2.5) |

### 2.2 Prepare Stage

The Prepare stage covers three independent concerns that together define the working dataset. All three can be configured in any order, revisited at any time, and none takes effect until the user explicitly applies them. The working dataset used by Explore is never modified without an explicit Apply action.

**Column Management**

| ID | Requirement |
|----|-------------|
| CM-01 | User sees all columns with their detected types (numeric, factor, datetime, character) |
| CM-02 | User can include or exclude individual columns from the working dataset |
| CM-03 | User can manually override a column's detected type (numeric ↔ factor ↔ datetime) |
| CM-04 | Excluded columns disappear from all downstream dropdowns after Apply |

**Row Filtering**

| ID | Requirement |
|----|-------------|
| RF-01 | User can add any included column as a row-filter criterion |
| RF-02 | Numeric columns: filter by min/max range |
| RF-03 | Factor/character/logical columns: filter by selecting which levels to retain |
| RF-04 | Multiple filters compose with AND logic |
| RF-05 | User can modify or remove any filter at any time before Apply |
| RF-06 | The resulting row count (vs. original) is displayed as filters are configured |

**Variable Transformation**

| ID | Requirement |
|----|-------------|
| VT-01 | User can recode any numeric column as an ordered factor using either: (a) auto-factoring (unique values become levels), or (b) user-defined cut-point breakpoints with optional level labels |
| VT-02 | A preview table shows old value distribution → new level assignment before Apply |
| VT-03 | Multiple transformations can be staged simultaneously |

**Apply**

| ID | Requirement |
|----|-------------|
| AP-01 | All staged changes are applied atomically when the user clicks "Apply & Proceed" |
| AP-02 | The UI displays a count of pending (unapplied) changes at all times |
| AP-03 | The resulting dataset dimensions (rows × columns) are shown before the user confirms |
| AP-04 | After Apply, the Explore stage reflects the new working dataset; any previously generated plots show a "dataset has changed — re-run" notice rather than crashing |
| AP-05 | User can return to Prepare from Explore at any time; all staged specs are preserved exactly as left |

### 2.3 Explore Stage: Single Variable

| ID | Requirement |
|----|-------------|
| SV-01 | User selects a primary variable and declares its role: **exposure** (→ X-axis) or **outcome** (→ Y-axis) |
| SV-02 | Clicking "Describe" generates a type-appropriate interactive plot and a summary statistics table |
| SV-03 | User can select a stratification variable; all subsequent plots group or facet by it |
| SV-04 | For datetime primary variables: user selects a time resolution and the plot shows aggregated counts over time |

### 2.4 Explore Stage: Bivariate

| ID | Requirement |
|----|-------------|
| BV-01 | User selects a secondary variable to correlate against the primary variable |
| BV-02 | Axis assignment is determined by the primary variable's declared role |
| BV-03 | Plot type is determined automatically by the type combination of the two variables (see §4.3) |
| BV-04 | For numeric vs. numeric: Pearson r and p-value are computed and shown as a plot annotation |
| BV-05 | Clicking "Plot" is always required to generate or update the plot; no auto-reactive plot generation |

### 2.5 Programmatic Report API

| ID | Requirement |
|----|-------------|
| PR-01 | `edark_report()` is an exported function usable without launching the GUI |
| PR-02 | Accepts: `data`, `primary_variable`, `primary_variable_role`, `secondary_variables` (character vector), `stratify_variable`, `report_format` (`"pptx"`, `"docx"`, `"html"`, `"pdf"`), `output_path` |
| PR-03 | Loops through `secondary_variables`, constructs a plot spec and ggplot object for each, assembles the report, and writes to `output_path` |
| PR-04 | Also exports: `build_plot_spec()`, `render_plot()`, `build_variable_summary()` as standalone functions for users who want to generate individual plots or tables in their own scripts |

### 2.6 Summary Statistics

| ID | Requirement |
|----|-------------|
| SS-01 | Dataset overview: one row per column — type, missing count, missing %, unique value count, mean, median, mode, standard deviation, IQR, skewness, kurtosis, min, max |
| SS-02 | Variable-level summary displayed alongside the plot in the Explore stage |
| SS-03 | Table One generated via `gtsummary::tbl_summary()`, optionally stratified with p-values |
| SS-04 | All in-app tables rendered as interactive `reactable` widgets |

### 2.7 Dataset Export

| ID | Requirement |
|----|-------------|
| DE-01 | User can download the current working dataset (post-Apply) as an `.rds` file via a `downloadButton` |

---

## 3. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NF-01 | Installable as a standard R package via `devtools::install()` |
| NF-02 | All Shiny modules independently testable with `{shinytest2}` |
| NF-03 | All exported functions independently testable with `{testthat}` |
| NF-04 | No session-global state; all reactive state in session-scoped `reactiveValues` |
| NF-05 | Long-running operations show a per-element loading indicator (not a full-page block) |
| NF-06 | Usable at 1280×800 viewport minimum |
| NF-07 | All exported functions documented with `roxygen2` |
| NF-08 | Passes `R CMD check` with no errors, no warnings |

---

## 4. Technical Specification

### 4.1 R Packages

#### Core Framework
| Package | Role |
|---------|------|
| `shiny` | Application framework |
| `bslib` | Bootstrap 5 layouts (`page_navbar`, `layout_sidebar`, `accordion`, `card`) |
| `shinyjs` | Imperative enable/disable/show/hide of UI elements |
| `shinyWidgets` | Enhanced inputs (`pickerInput`, `radioGroupButtons`, `switchInput`) |
| `waiter` | Per-element loading spinners |

#### Data Manipulation
| Package | Role |
|---------|------|
| `dplyr` | Data transformation |
| `tidyr` | Pivoting and reshaping |
| `tibble` | Modern data frames |
| `lubridate` | Date/time parsing and floor-rounding for trend aggregation |
| `stringr` | String manipulation |
| `forcats` | Factor level reordering (`fct_reorder`, `fct_infreq`) |

#### Visualization
| Package | Role |
|---------|------|
| `ggplot2` | All plot construction (screen and report) |
| `ggpubr` | Correlation annotations in plots (`stat_cor`) |
| `patchwork` | Multi-panel layouts for report pages |
| `plotly` | `ggplotly()` wrapper for interactive on-screen display only |

#### Statistics
| Package | Role |
|---------|------|
| `e1071` | Skewness and kurtosis |

#### Tables & Output
| Package | Role |
|---------|------|
| `gtsummary` | Table One / stratified summary statistics |
| `gt` | GT table rendering (consumed by gtsummary) |
| `flextable` | Tables inside Word and PowerPoint reports |
| `reactable` | Interactive in-app data tables |

#### Report Generation *(post-MVP)*
| Package | Role |
|---------|------|
| `officer` | PowerPoint and Word document creation |
| `rvg` | Vector graphic (ggplot2) insertion into Office documents |
| `rmarkdown` | HTML and PDF report rendering |
| `knitr` | Rmarkdown execution engine |

#### Developer / Quality
| Package | Role |
|---------|------|
| `roxygen2` | Documentation generation |
| `shinytest2` | Automated Shiny module UI tests |
| `testthat` | Unit tests for utility functions |

---

### 4.2 Column Auto-Cast Rules (`cast_column_types`)

Applied once at launch, in priority order. Each rule applies only if no prior rule matched.

| Priority | Condition | Action |
|----------|-----------|--------|
| 1 | Column is `Date` | Convert to `POSIXct` at midnight UTC |
| 2 | Column is `logical` | Convert to `factor` with levels `c("FALSE", "TRUE")` |
| 3 | Column is `character` and all non-NA values parse as numeric | Convert to `numeric` |
| 4 | Column is `character` and unique non-NA value count ≤ `max_factor_levels` | Convert to `factor` |
| 5 | Anything else | Leave unchanged |

`max_factor_levels` defaults to `20` and is exposed as an argument to `edark()`.

---

### 4.3 Plot Type Routing (`route_plot_type`)

The primary variable's declared role determines axis assignment before routing:

- Role = **"exposure"** → primary variable is the X-axis variable (`column_a`); secondary variable is the Y-axis variable (`column_b`)
- Role = **"outcome"** → primary variable is the Y-axis variable (`column_b`); secondary variable is the X-axis variable (`column_a`)

`route_plot_type(column_a_type, column_b_type)` returns a plot type string consumed by `render_plot()`.

| `column_a` type | `column_b` type | Plot type string | Notes |
|---|---|---|---|
| factor | *none* | `"bar_count"` | Count + % per level; bars always horizontal |
| numeric | *none* | `"histogram_density"` | Histogram with overlaid density curve; adjacent Q-Q plot via `patchwork` |
| datetime | *none* | `"trend_count"` | Aggregated event count over time |
| factor | factor | `"bar_grouped"` | Grouped bar; toggle to stacked available |
| factor | numeric | `"violin_box"` | Violin outer, box inner; one group per factor level |
| numeric | numeric | `"scatter_lm"` | Points + linear fit + Pearson r annotation |
| datetime | numeric | `"trend_mean"` | Mean (or median) of numeric over time |
| datetime | factor | `"trend_proportion"` | Proportion of each factor level over time |

**Stratification behavior per plot type:**

| Plot type | Stratification method |
|---|---|
| `bar_count`, `bar_grouped` | Fill color by stratification variable + legend |
| `violin_box` | Facet by stratification variable (color is already used for groups) |
| `scatter_lm` | Color points by stratification variable; one regression line per group |
| `histogram_density` | Faceted histograms for ≤ 3 strata; warning for > 3 |
| `trend_*` | Facet by stratification variable |

**High-cardinality guard:** If a factor column exceeds `max_factor_levels` unique values, the plot is not generated and a descriptive warning message is shown in the output panel.

---

### 4.4 Module Architecture

All modules follow the convention `module_name_ui(id)` + `module_name_server(id, shared_state)`. Every module is a sibling at the server level — no module calls another module's server function.

```
edark(dataset)
│
├── cast_column_types(dataset)       → shared_state$dataset_original
├── detect_column_types(dataset)     → shared_state$column_types
│
└── shinyApp(ui, server)
    │
    ├── UI
    │   └── bslib::page_navbar
    │       ├── nav_panel("1 · Prepare")
    │       │   ├── column_manager_ui("column_manager")
    │       │   ├── row_filter_ui("row_filter")
    │       │   ├── column_transform_ui("column_transform")
    │       │   └── prepare_confirm_ui("prepare_confirm")
    │       │
    │       ├── nav_panel("2 · Explore")
    │       │   ├── [sidebar] explore_controls_ui("explore_controls")
    │       │   └── [main]    explore_output_ui("explore_output")
    │       │
    │       └── nav_panel("3 · Report")   [post-MVP]
    │           └── report_ui("report")
    │
    └── Server
        ├── column_manager_server("column_manager", shared_state)
        ├── row_filter_server("row_filter", shared_state)
        ├── column_transform_server("column_transform", shared_state)
        ├── prepare_confirm_server("prepare_confirm", shared_state)
        ├── explore_controls_server("explore_controls", shared_state)
        ├── explore_output_server("explore_output", shared_state)
        └── report_server("report", shared_state)        [post-MVP]
```

**Shared reactive values (`shared_state`):**

```r
shared_state <- reactiveValues(

  # ── Dataset ─────────────────────────────────────────────────────────────
  dataset_original        = NULL,   # data.frame: immutable, set once at launch
  dataset_working         = NULL,   # data.frame: current applied state
  column_types            = NULL,   # named character vector: column → type string
                                    #   type strings: "numeric", "factor",
                                    #                 "datetime", "character"

  # ── Prepare stage: staged (not yet applied) ──────────────────────────────
  included_columns        = NULL,   # character vector: column names to keep
  column_type_overrides   = list(), # named list: column name → overridden type string
  row_filter_specs        = list(), # named list of row filter specifications
  column_transform_specs  = list(), # named list of column transform specifications
  has_pending_changes     = FALSE,  # logical: TRUE when staged ≠ applied

  # ── Explore stage ────────────────────────────────────────────────────────
  primary_variable        = NULL,   # character: column name of primary variable
  primary_variable_role   = NULL,   # character: "exposure" or "outcome"
  secondary_variable      = NULL,   # character: column name of secondary variable
  stratify_variable       = NULL,   # character: column name for stratification (NULL = none)
  trend_variable          = NULL,   # character: datetime column name for trend plots
  trend_resolution        = "Day",  # character: time aggregation resolution

  # ── Plot state ───────────────────────────────────────────────────────────
  plot_specification      = NULL,   # list: plot parameters (drives render_plot())
  active_plot             = NULL,   # ggplot object: current plot (wrapped by ggplotly() for display)
  variable_summary        = NULL,   # data.frame: summary stats for current primary variable
  explore_needs_refresh   = FALSE,  # logical: TRUE after Apply when plots are stale

  # ── Aesthetics ───────────────────────────────────────────────────────────
  color_palette           = "Set2",
  show_data_labels        = FALSE,
  show_legend             = TRUE,
  legend_position         = "right"
)
```

---

### 4.5 Data Flow

```
══════════════════════════════════════════════════════════════
 LAUNCH  (runs once, before the Shiny reactive graph starts)
══════════════════════════════════════════════════════════════

edark(dataset)
    │
    ├── validate_input(dataset)                 # stop() with clear message if invalid
    ├── cast_column_types(dataset)
    │       → shared_state$dataset_original
    │       → shared_state$dataset_working      # starts as a copy of original
    ├── detect_column_types(dataset)
    │       → shared_state$column_types
    └── shared_state$included_columns ← names(dataset)


══════════════════════════════════════════════════════════════
 STAGE 1: PREPARE
 Modules: column_manager, row_filter, column_transform,
          prepare_confirm
══════════════════════════════════════════════════════════════

User toggles column inclusion / overrides a column type
    └── column_manager_server writes:
            shared_state$included_columns       (staged)
            shared_state$column_type_overrides  (staged)
            shared_state$has_pending_changes ← TRUE

User adds, modifies, or removes a row filter
    └── row_filter_server writes:
            shared_state$row_filter_specs       (staged)
            shared_state$has_pending_changes ← TRUE

User adds, modifies, or removes a variable transformation
    └── column_transform_server writes:
            shared_state$column_transform_specs (staged)
            shared_state$has_pending_changes ← TRUE

    ↑ None of the above touch dataset_working.
      The UI shows a pending-change count badge.
      The user can freely navigate to Explore and back.

User clicks "Apply & Proceed"
    └── prepare_confirm_server calls apply_prepare_pipeline():
            │
            ├── start with shared_state$dataset_original
            ├── apply_column_type_overrides(shared_state$column_type_overrides)
            ├── select(shared_state$included_columns)
            ├── apply_column_transforms(shared_state$column_transform_specs)
            ├── apply_row_filters(shared_state$row_filter_specs)
            │
            └── shared_state$dataset_working      ← result
                shared_state$column_types         ← re-detected from result
                shared_state$has_pending_changes  ← FALSE
                shared_state$explore_needs_refresh ← TRUE
                [navigate to Explore tab]


══════════════════════════════════════════════════════════════
 STAGE 2: EXPLORE
 Modules: explore_controls, explore_output
══════════════════════════════════════════════════════════════

Explore tab loads or user returns from Prepare after an Apply
    └── explore_output_server observes shared_state$explore_needs_refresh:
            → shows "Dataset has changed — re-run your analysis" notice
              Plots and tables from before the Apply are cleared.

User sets primary variable + role
    └── explore_controls_server writes:
            shared_state$primary_variable
            shared_state$primary_variable_role

User clicks "Describe"
    └── explore_controls_server:
            │
            ├── build_univariate_plot_spec(shared_state)
            │       → shared_state$plot_specification
            │
            └── explore_output_server observes plot_specification:
                    │
                    ├── render_plot(spec, shared_state$dataset_working)
                    │       → shared_state$active_plot   (ggplot object)
                    │       → output: ggplotly(shared_state$active_plot)
                    │
                    └── build_variable_summary(shared_state$dataset_working,
                                               shared_state$primary_variable)
                            → shared_state$variable_summary
                            → output: reactable(shared_state$variable_summary)

User sets secondary variable and clicks "Plot Correlation"
    └── explore_controls_server:
            │
            ├── shared_state$secondary_variable ← input
            ├── build_bivariate_plot_spec(shared_state)
            │       → shared_state$plot_specification
            │
            └── (same render chain as above)

Aesthetics inputs change (palette, labels, legend)
    └── explore_controls_server writes:
            shared_state$color_palette
            shared_state$show_data_labels
            shared_state$show_legend
            shared_state$legend_position
        explore_output_server observes these values:
            → re-calls render_plot(shared_state$plot_specification,
                                   shared_state$dataset_working)
              [inexpensive — plot_specification already built, data not re-queried]
            → shared_state$active_plot ← new ggplot
            → output re-renders ggplotly(shared_state$active_plot)


══════════════════════════════════════════════════════════════
 STAGE 3: REPORT  [post-MVP]
 Module: report
══════════════════════════════════════════════════════════════

User configures scope + format, clicks "Generate"
    └── report_server calls generate_report():
            │
            ├── for each variable in scope:
            │       ├── build_bivariate_plot_spec(shared_state, secondary = variable)
            │       └── render_plot(spec, shared_state$dataset_working)
            │             [returns ggplot object — NOT wrapped in ggplotly]
            │
            ├── assemble_report(plots, summaries, format)
            └── output$download_report ← downloadHandler


══════════════════════════════════════════════════════════════
 PUBLIC API  (no Shiny, called from user R scripts)
══════════════════════════════════════════════════════════════

edark_report(
    data                  = my_df,
    primary_variable      = "age",
    primary_variable_role = "exposure",
    secondary_variables   = c("bmi", "sex", "outcome"),
    stratify_variable     = "sex",
    report_format         = "pptx",
    output_path           = "~/analysis.pptx"
)
    │
    ├── cast_column_types(data)
    ├── for each secondary_variable:
    │       ├── build_bivariate_plot_spec(...)
    │       ├── render_plot(spec, data)
    │       └── build_variable_summary(data, primary_variable)
    │
    └── assemble_report(plots, summaries, report_format, output_path)
```

---

### 4.6 File Structure

```
edark2/
├── R/
│   │
│   │  # ── Entry points ──────────────────────────────────────────────
│   ├── edark.R                      # edark(): launches the Shiny app
│   ├── edark_report.R               # edark_report(): programmatic report generation
│   │
│   │  # ── Shiny modules ─────────────────────────────────────────────
│   ├── mod_column_manager.R         # column inclusion + type override
│   ├── mod_row_filter.R             # row filter spec management
│   ├── mod_column_transform.R       # column transform spec management
│   ├── mod_prepare_confirm.R        # apply pipeline + row count + navigation
│   ├── mod_explore_controls.R       # variable selectors, role, aesthetics, action buttons
│   ├── mod_explore_output.R         # plotly output + summary table + dataset tab
│   ├── mod_report.R                 # report config + download handler [post-MVP]
│   │
│   │  # ── Utility functions ─────────────────────────────────────────
│   ├── utils_type_casting.R         # cast_column_types(), detect_column_types()
│   ├── utils_prepare_pipeline.R     # apply_prepare_pipeline(), apply_column_type_overrides(),
│   │                                #   apply_column_transforms(), apply_row_filters()
│   ├── utils_summary_stats.R        # build_variable_summary(), statistical_mode()
│   ├── utils_plot_spec.R            # route_plot_type(), build_univariate_plot_spec(),
│   │                                #   build_bivariate_plot_spec()
│   ├── utils_plot_render.R          # render_plot(): all ggplot2 sub-renderers
│   ├── utils_report.R               # generate_report(), assemble_report() [post-MVP]
│   └── utils_helpers.R              # validate_input(), is_numeric_column(),
│                                    #   is_factor_column(), is_datetime_column()
│
├── inst/
│   └── report_templates/            # .pptx templates [post-MVP]
│
├── tests/
│   ├── testthat/
│   │   ├── test-type-casting.R
│   │   ├── test-prepare-pipeline.R
│   │   ├── test-summary-stats.R
│   │   ├── test-plot-spec.R
│   │   └── test-plot-render.R
│   └── shinytest2/
│       ├── test-column-manager.R
│       ├── test-row-filter.R
│       ├── test-column-transform.R
│       └── test-explore-controls.R
│
├── man/                             # roxygen2-generated docs
├── DESCRIPTION
├── NAMESPACE
└── README.md
```

**Rationale for key decisions:**
- No `app.R`: for a package, `edark.R` calls `shiny::shinyApp()` directly. `app.R` is a script-level convention.
- No `global.R`: inside a package, `global.R` creates ambiguous load order. Constants live in `utils_helpers.R` or as internal package data.
- `utils_plot_render.R` is a single file containing all ggplot2 sub-renderers. If it grows beyond ~400 lines, split by plot family: `utils_plot_render_categorical.R`, `utils_plot_render_numeric.R`, etc.
- `mod_explore_controls.R` and `mod_explore_output.R` are separate because controls write to `shared_state` and output reads from it. Keeping them separate enforces this one-way flow.

---

## 5. UI Specification

### 5.1 Layout

```
┌────────────────────────────────────────────────────────────────┐
│  EDARK  |  1 · Prepare  |  2 · Explore  |  3 · Report         │
├────────────────────────────────────────────────────────────────┤
│  Stage-specific content                                        │
└────────────────────────────────────────────────────────────────┘
```

- **Framework**: `bslib::page_navbar()`
- Stage 1 (Prepare): full-width stacked `bslib::card()` layout
- Stage 2 (Explore): `bslib::layout_sidebar()` — controls sidebar (340px, scrollable) + main output panel
- Stage 3 (Report): simple form layout *(post-MVP)*
- Navigation between all stages is free at all times. No forced gating.

### 5.2 Stage 1: Prepare

Four stacked `bslib::card()` components, each independently collapsible.

---

**Card 1 — Columns**

| Element | Widget | Behavior |
|---------|--------|----------|
| Column list | `reactable` | One row per column: name, detected type, missing %, n unique values |
| Type override (per row) | `selectInput` inside reactable cell | "Auto", "Numeric", "Factor", "Datetime" |
| Include/exclude toggle (per row) | `switchInput` inside reactable cell | Checked = included; default all checked |
| Column count summary | `textOutput` | "X of Y columns included" |

---

**Card 2 — Row Filters**

| Element | Widget | Behavior |
|---------|--------|----------|
| Add filter selector | `selectInput` | Included columns only |
| Add Filter button | `actionButton` | Appends a filter card |
| Per-filter card (`uiOutput`) | `bslib::card` | Collapsible, one per active filter |
| — Numeric filter | `sliderInput` (range) | Min/max within observed data range |
| — Factor filter | `shinyWidgets::pickerInput` | Multi-select levels; all checked by default |
| — Remove button | `actionButton` | Removes this filter from `row_filter_specs` |
| Result row count | `textOutput` | "N rows will remain (X% of original)" — recomputes on filter change using a `debounce`d reactive preview (not the full pipeline) |

---

**Card 3 — Variable Transformations**

| Element | Widget | Behavior |
|---------|--------|----------|
| Add transform selector | `selectInput` | Numeric columns in included set only |
| Add Transform button | `actionButton` | Appends a transform card |
| Per-transform card (`uiOutput`) | `bslib::card` | Collapsible, one per staged transform |
| — Encoding type | `radioButtons` | "Auto-factor" or "Cut points" |
| — Cut points | `textInput` | Comma-separated breakpoints; shown only when "Cut points" selected |
| — Labels | `textInput` | Comma-separated level labels (optional) |
| — Preview | `reactable` (mini) | Old value range → new level, count per bin |
| — Remove button | `actionButton` | Removes this transform |

---

**Card 4 — Confirm**

| Element | Widget | Behavior |
|---------|--------|----------|
| Pending changes badge | `uiOutput` | Amber badge "N pending changes"; hidden when `has_pending_changes == FALSE` |
| Result dimensions | `textOutput` | "Result: N rows × P columns" |
| Apply & Proceed button | `actionButton` | Runs `apply_prepare_pipeline()`; highlighted style when changes are pending; navigates to Explore on success |
| Save dataset button | `downloadButton` | Downloads `dataset_working` as `.rds`; active only after at least one Apply |

### 5.3 Stage 2: Explore — Sidebar (Controls)

Single scroll pane. Controls grouped with visual separators. No nested sub-tabs.

| Section | Element | Widget | Behavior |
|---------|---------|--------|----------|
| **Primary Variable** | Primary variable | `selectInput` | Columns in `dataset_working` |
| | Variable role | `shinyWidgets::radioGroupButtons` | "Exposure" / "Outcome" — compact, inline |
| | Describe button | `actionButton` | Triggers single-variable analysis; primary button style |
| **Stratification** | Stratify by | `selectInput` | Columns in dataset + "None" option at top |
| **Bivariate** | Secondary variable | `selectInput` | Columns excluding primary variable |
| | Plot Correlation button | `actionButton` | Triggers bivariate plot |
| **Trend** | Trend variable | `selectInput` | Datetime columns only; section hidden if no datetime columns exist |
| | Resolution | `selectInput` | Day / Week / Month / Quarter / Year |
| | Plot Trend button | `actionButton` | Triggers trend plot |
| **Aesthetics** | *(collapsed by default)* | `bslib::accordion_panel` | |
| | Color palette | `selectInput` | Set1, Set2, Set3, Pastel1, Pastel2, Blues, Reds, Oranges, Purples |
| | Show data labels | `shinyWidgets::switchInput` | Toggles count/% labels on bar plots |
| | Show legend | `shinyWidgets::switchInput` | Toggles legend visibility |
| | Legend position | `selectInput` | top, right, bottom, left |

### 5.4 Stage 2: Explore — Main Panel (Output)

`bslib::navset_card_tab` with three tabs:

| Tab | Widget | Content |
|-----|--------|---------|
| **Plot** | `plotly::plotlyOutput` | Current interactive visualization (`ggplotly(shared_state$active_plot)`); stale notice shown when `explore_needs_refresh == TRUE` |
| **Statistics** | `reactableOutput` | Variable summary table for current primary variable |
| **Dataset** | `reactableOutput` | Working dataset: searchable, filterable, paginated |

### 5.5 Loading Indicators

Use `waiter::Waiter` scoped to individual output elements:

```r
waiter <- Waiter$new(id = "explore_plot_output", html = waiter::spin_fading_circles())
waiter$show()
# ... computation ...
waiter$hide()
```

Scoped overlays are preferred over full-page blocks because aesthetics changes, summary table updates, and plot re-renders can complete independently.

---

## 6. Visualization Specification

### 6.1 Architecture

All plots are built with `ggplot2` by `render_plot(plot_specification, data)`.

For on-screen display: `plotly::ggplotly(plot, tooltip = ...)` wraps the returned ggplot object.
For report export: the ggplot object is used directly.

There is one rendering function. There is no dual pipeline.

### 6.2 Plot Themes

Defined in `utils_helpers.R`:

- `theme_edark_screen`: used as the base theme for all on-screen ggplot2 builds before ggplotly conversion. White background, subtle grid, 12pt base font. ggplotly will partially override this but the base structure carries over.
- `theme_edark_slide`: larger base font (14pt), no minor grid, white background. Used for PowerPoint export.
- `theme_edark_document`: 11pt base font, minimal style. Used for Word and PDF export.

Report functions pass `theme = "slide"` or `theme = "document"` to `render_plot()`.

### 6.3 Color Palettes

Applied via `scale_fill_brewer(palette = ...)` and `scale_color_brewer(palette = ...)`.

Available: `Set1`, `Set2`, `Set3`, `Pastel1`, `Pastel2`, `Blues`, `Reds`, `Oranges`, `Purples`

Default: `Set2`

### 6.4 Plot-Specific Behaviors

---

**`bar_count` — single factor**
- `geom_bar()` with `stat = "count"`
- `coord_flip()` always applied — horizontal bars avoid label overlap unconditionally; no conditional logic
- Bars ordered by count descending via `forcats::fct_infreq()` applied to the data before plotting (unless the factor has an explicit ordered level structure)
- Labels: if `show_data_labels = TRUE`, count and percentage shown via `geom_text()` outside bars
- ggplotly tooltip: level name, count, percentage

---

**`histogram_density` — single numeric**
- Histogram: `geom_histogram()` with bin count from Sturges rule (`nclass.Sturges()`)
- Density overlay: `geom_density()` scaled to count units (`after_stat(density * nrow(data) * binwidth)`)
- Q-Q plot: `geom_qq()` + `geom_qq_line()` — ggplot2 handles this natively and ggplotly converts it correctly; no manual quantile computation needed
- The two panels (histogram and Q-Q) are composed side by side using `patchwork` before being wrapped in `ggplotly()`. Note: `ggplotly` of a patchwork layout requires converting each sub-plot individually and combining with `plotly::subplot()`. This is handled inside `render_plot()`.
- If stratified: semi-transparent overlapping histograms for ≤ 3 strata; `facet_wrap` for > 3

---

**`violin_box` — factor vs. numeric**
- `geom_violin()` + `geom_boxplot()` (width = 0.15, inside the violin)
- `geom_jitter()` for groups with n < 50; suppressed otherwise
- ggplotly tooltip: group name, median, IQR, n

---

**`scatter_lm` — numeric vs. numeric**
- `geom_point(alpha = 0.4)` for overplotting
- `geom_smooth(method = "lm", se = TRUE)` for linear fit with confidence band
- Pearson r and p-value from `cor.test()` annotated via `ggpubr::stat_cor()` placed in the top-left corner
- If stratified: `aes(color = stratify_variable)` + one smooth per group

---

**`bar_grouped` — factor vs. factor**
- `geom_bar(position = "dodge")` for grouped; an aesthetic toggle in the Explore controls switches `position` to `"fill"` for proportional stacked view
- ggplotly tooltip: group combination, count, percentage of row total

---

**`trend_count` / `trend_mean` / `trend_proportion` — datetime column_a**
- Data aggregated in R before plotting using `lubridate::floor_date()` at the selected resolution
- `geom_line()` + `geom_point()`
- X-axis formatted by resolution: `"%b %Y"` for Month/Quarter, `"%Y"` for Year, `"%d %b"` for Day/Week
- If stratified: `facet_wrap(~ stratify_variable)`
- ggplotly provides interactive zoom/pan on the time axis — no additional configuration needed

---

## 7. Report Generation Specification *(post-MVP)*

### 7.1 Rendering

All report formats use the ggplot object returned by `render_plot()` directly — no ggplotly conversion, no headless browser, no webshot.

```r
# In render_plot(), report mode selects a different theme:
render_plot(plot_specification, data, theme = "slide")   # → ggplot for PPTX
render_plot(plot_specification, data, theme = "document") # → ggplot for Word/PDF
```

### 7.2 PowerPoint

- One slide per variable or bivariate pair
- Layout: title (top), plot (left 60%), summary table as `flextable` (right 40%)
- Footer: dataset name + generation date
- Rendered via `officer` + `rvg::dml()` for vector quality
- Templates in `inst/report_templates/`

### 7.3 Word Document

- One section per variable/bivariate pair, separated by page breaks
- Plot as `rvg::dml()` vector graphic
- Summary statistics as `flextable`
- Built with `officer::read_docx()` + `officer::body_add_*()`

### 7.4 HTML

- Self-contained HTML via `rmarkdown::render(html_document(self_contained = TRUE))`
- Plots as ggplot2 SVG (static). Interactive plotly htmlwidgets are a nice-to-have toggle but not required.
- Tables as `reactable`

### 7.5 PDF

- Via `rmarkdown::render(pdf_document())` using `tinytex`
- `pagedown::chrome_print()` is explicitly excluded — Chrome as a package dependency is too heavy and environment-sensitive

---

## 8. Out of Scope for v2

- File upload (CSV, Excel, RDS from disk) — dataset is passed via `edark(dataset)` only
- Multi-dataset merging or joins
- Machine learning or predictive modeling
- Real-time or streaming data
- User authentication or multi-user session management
- Cloud storage integration
- Database connectivity (removed from v0.1.0 for MVP simplicity)

---

*Prepared: 2026-03-31*
