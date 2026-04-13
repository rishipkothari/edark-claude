# EDARK Analysis Module — PRD Section 6
## Screen-by-Screen UI Specification

---

## 6.1 Purpose of This Section

Section 5 defined the workflow and sequencing. This section specifies the precise UI components, input types, and rendering behavior for each screen. This is the section Claude Code reads to build each step. It should be unambiguous enough that no UI decisions need to be made during implementation.

---

## 6.2 Global UI Component Conventions

These apply to every screen in the analysis module without exception. Behavioral principles (buttons in config panel, no per-object downloads, message areas, placeholders) are defined in §5.2 and are not repeated here. This section covers component-level conventions only.

**Component library:** `bslib` for layout, `shinyWidgets` for enhanced inputs, `shiny` native for standard inputs. Consistent with existing app.

**Spacing and typography:** inherit from existing `bs_theme` — flatly bootswatch, Bootstrap 5, primary `#2c7be5`. No new theme variables introduced in the analysis module.

**Input widths:** all inputs in sidebar panels are full width (`width = "100%"`). No half-width inputs in sidebars.

**Section labels within sidebars:** use `tags$p(class = "mt-2 mb-1 fw-semibold", ...)` consistent with existing `prepare_confirm_ui` pattern.

**Horizontal rules between sidebar sections:** `hr(class = "my-2")` consistent with existing pattern.

**Icons:** `shiny::icon()` throughout. No raw Font Awesome strings.

**Notifications:** `shiny::showNotification()` with `type = "message"` for success, `type = "warning"` for warnings, `type = "error"` for errors. Duration 4 seconds for success, 8 seconds for errors. Consistent with existing app.

**Blocking modal progress display:** every time-consuming operation launches a modal via `shiny::showModal()` with `easyClose = FALSE`. The modal contains a step list with per-step status icons (pending: grey circle, running: blue spinner, complete: green check, error: red x) and a progress bar. No `withProgress` toast for any operation in the analysis module.

**Message area:** every output panel begins with a `uiOutput` message card rendered by the module server. Default state is empty. Populated with status, warnings, or placeholder text as appropriate. Uses `bslib::card` with appropriate border color class.

**Placeholder cards:** when an output has not been generated or was not selected, a `bslib::card` with muted border and centered italic text explains why the space is empty. Never a blank space.

**Stale indicators:** when a cached output is invalidated by an upstream change, its tab label in any `navset_card_tab` gains an amber warning icon. The output itself remains visible but a banner appears at the top: *"This output may be out of date. Rerun to refresh."*

**Numeric display:** all numeric values displayed to a maximum of 3 decimal places globally. Values < 0.001 displayed as *"< 0.001"*. Dynamic significant-figure-based rounding is a planned future improvement (see §12).

---

## 6.3 Step 1 — Setup

**Module file:** `R/module_analysis_setup.R`

**UI function:** `analysis_setup_ui(id)`

**Server function:** `analysis_setup_server(id, shared_state)`

---

**Layout:** `layout_sidebar(position = "right")`
- **Main panel (left):** role assignment table — primary action area
- **Sidebar (right):** role summary and study type badge — read-only

---

**Pre-start state:**

Main panel renders a centered card:
```
[dataset icon]
Working dataset: 400 rows × 14 variables
13 rows contain missing values across at least one column

[ Start Analysis ]
```

The Start Analysis button is `class = "btn-primary"`. Clicking it executes the freeze sequence and renders the role assignment table.

---

**Post-start main panel — role assignment table:**

Implemented as a `DT::datatable` with custom column renderers for interactive inputs.

| Column | Render type | Width |
|---|---|---|
| Variable | Static text | 140px |
| Type | Badge via `renderUI` | 80px |
| Outcome | Radio via `renderUI` | 80px |
| Exposure | Radio via `renderUI` | 80px |
| Candidate | Checkbox via `renderUI` | 90px |
| Subject ID | Radio via `renderUI` | 90px |
| Cluster | Radio via `renderUI` | 70px |
| Time | Radio via `renderUI` | 60px |
| Reference level | `selectInput` via `renderUI` | 130px |

Above the table: `shinyWidgets::searchInput` for variable name filtering. Filters table rows reactively.

Radio button columns (outcome, exposure, subject ID, cluster, time) each have a **"Clear"** button in the column header — small `actionButton` with `icon("xmark")` and `class = "btn-outline-secondary btn-sm"`. Clicking clears that column's selection across all rows.

Mutual exclusivity enforced reactively:
- Assigning outcome or exposure automatically unchecks candidate covariate for that variable
- Assigning subject ID, cluster, or time automatically unchecks candidate covariate for that variable
- Checking candidate covariate clears outcome, exposure, and structural role assignments for that variable

Reference level dropdown:
- Visible only for factor variables
- Populated with factor levels in R factor order (not alphabetically)
- Shows "—" for non-factor variables
- Defaults to first level in R factor order

---

**Sidebar (right) — read-only role summary:**

```r
tags$div(
  tags$p(class = "mt-2 mb-1 fw-semibold", icon("tag"), " Study Type"),
  uiOutput(ns("study_type_badge")),
  hr(class = "my-2"),
  tags$p(class = "mt-2 mb-1 fw-semibold", icon("list"), " Role Assignments"),
  uiOutput(ns("role_summary_table")),
  hr(class = "my-2"),
  tags$p(class = "mt-2 mb-1 fw-semibold", icon("database"), " Dataset"),
  uiOutput(ns("dataset_snapshot"))
)
```

Study type badge colors: exposure-outcome = blue, risk factor = green, descriptive exposure = grey, descriptive = grey. Updates live as role assignments change.

Unassigned roles display as `tags$span(class = "text-muted fst-italic", "— not assigned")`.

Dataset snapshot shows: row count, column count, complete cases across selected variables.

Example sidebar state:
```
Study type:     Exposure-outcome association

Outcome:        aki (binary)
Exposure:       hypotension (binary)
Covariates:     age, asa_class, baseline_cr  (3)
Subject ID:     patient_id
Cluster:        —
Time:           —
─────────────────────────────────────────
Dataset:        400 rows · 14 variables
Complete cases: 387 / 400 across selected variables
```

---

**Reactive behavior:**
- Role assignment table inputs observed via `observeEvent` on each input ID
- Mutual exclusivity enforced in observers
- `analysis_spec$variable_roles` updated reactively as assignments change — no confirm button needed for role assignment
- Downstream steps marked stale on any role change per §5.4

**Defaults written to `analysis_spec` from Step 1:**

| Field | Default |
|---|---|
| `table1_variables` | Exposure + outcome + full candidate pool in role assignment order |
| `univariable_test_pool` | Full candidate pool |
| `final_model_covariates` | Full candidate pool |

**Step complete when:** `analysis_spec$variable_roles$outcome_variable` is not NULL.

---

## 6.4 Step 2 — Table 1

**Module file:** `R/module_analysis_table1.R`

**UI function:** `analysis_table1_ui(id)`

**Server function:** `analysis_table1_server(id, shared_state)`

---

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** configuration and generate button
- **Main panel (right):** generated table output

---

**Sidebar (left):**

```
[Section: Stratification]
checkboxInput — By Exposure
  default: TRUE if exposure assigned, per study type rules §3.7

checkboxInput — By Outcome
  default: TRUE if no exposure assigned, per study type rules §3.7

[Section: Options]
checkboxInput — Include p-values
  default: FALSE for exposure stratification
           TRUE for outcome stratification
  tooltip: "These p-values describe group differences in
            baseline characteristics. They are not used
            for variable selection — see Step 3 for
            outcome-regressed associations."

checkboxInput — Include Standardized Mean Difference
  default: TRUE

[hr]

actionButton — "Generate Table 1"
  class = "btn-primary w-100"
  icon = icon("table")
  launches blocking modal
```

---

**Main panel (right) — `navset_card_tab`:**

Message area at top: `uiOutput(ns("table1_message"))`.

Tabs rendered dynamically based on stratification selections:
- **Overall** tab — always present; unstratified Table 1
- **By Exposure** tab — present only if exposure assigned and By Exposure checkbox checked
- **By Outcome** tab — present only if outcome assigned and By Outcome checkbox checked

Table column structure when stratified: Overall column first, then stratification level columns, p-values between stratified levels if enabled.

Variables included: exposure first, then outcome, then all candidate covariates in role assignment order. No user selection of which variables to include.

Placeholder cards for tabs that exist structurally but were not generated. No tab rendered for structurally impossible stratifications (e.g. By Exposure tab does not exist if no exposure assigned).

---

**Reactive behavior:**
- Stratification checkbox changes update p-value toggle default silently
- Results stored in `analysis_result$result_tables$table1_overall`, `$table1_by_exposure`, `$table1_by_outcome`
- Changing any config after generation marks Table 1 stale

**Step complete when:** Table 1 generated at least once.

---

## 6.5 Step 3 — Variable Investigation

**Module file:** `R/module_analysis_varinvestigation.R`

**UI function:** `analysis_varinvestigation_ui(id)`

**Server function:** `analysis_varinvestigation_server(id, shared_state)`

---

**Layout:** full-width. A `navset_pill` with `nav_stacked = TRUE` (vertical pills) on the left. Three tools as vertical pills:

```
● Univariable Screen
  Collinearity
  Stepwise / LASSO
```

Each pill renders a `layout_sidebar(position = "left")` to its right.

---

**Univariable Screen pill:**

`layout_sidebar(position = "left")`

Sidebar (left):
```
[Section: About]
tags$p — "Runs unadjusted regression of each candidate
          covariate against the outcome. Model family
          is selected automatically based on outcome
          type."

tags$p class="text-muted small" —
  "Linear regression — continuous outcome"
  OR
  "Logistic regression — binary outcome"
  (rendered conditionally)

tags$p class="text-muted small" —
  "Note: Clustering not accounted for in
   screening models."
  (shown only if subject ID assigned)

[hr]

actionButton — "Run Univariable Screen"
  class = "btn-primary w-100"
  icon = icon("play")
  launches blocking modal
```

Always runs on all Step 1 candidate covariates — no pool selector.

Main panel (right):
- Message area
- Results table: `DT::datatable` — Variable, Estimate (β or OR), 95% CI Lower, 95% CI Upper, P-value; sorted by p-value ascending by default; sortable by any column
- Model family note below table
- Placeholder if not run: *"Run the univariable screen to see unadjusted associations between each candidate variable and the outcome."*

---

**Collinearity pill:**

`layout_sidebar(position = "left")`

Sidebar (left):
```
[Section: About]
tags$p — "Pairwise correlations among candidate
          variables. Computed automatically from
          the candidate pool assigned in Step 1.
          No configuration required."

uiOutput — warning flags
  Lists flagged pairs inline if any exceed
  threshold:
  · amber: correlation > 0.7
  · red: correlation > 0.9
```

No run button — computed on tab entry from candidate pool.

Main panel (right) — `navset_card_tab`:

- **Correlation Heatmap** tab:
  - Numeric candidates only
  - `ggplot2` heatmap clustered by hierarchical ordering for large variable sets
  - Scrollable container
  - If > 30 variables: note shown — *"Showing top 30 variables by variance. Full matrix available in export."*

- **Cramér's V** tab:
  - Categorical candidates only
  - Shown only if categorical candidates exist in pool
  - Same heatmap format

- **Flagged Pairs** tab:
  - Always shown regardless of variable count
  - `DT::datatable` — Variable 1, Variable 2, Correlation / Cramér's V, Warning level
  - Rows colored amber (> 0.7) or red (> 0.9)
  - Empty table with message if no pairs exceed threshold

---

**Stepwise / LASSO pill:**

`layout_sidebar(position = "left")`

Sidebar (left):
```
[Section: Method]
radioGroupButtons — toggle
  choices: "Stepwise"  "LASSO"
  selected: "Stepwise"

[Stepwise config — shown when Stepwise selected]
radioGroupButtons — Direction
  choices: "Backward"  "Forward"
  selected: "Backward"

radioGroupButtons — Criterion
  choices: "BIC"  "AIC"
  selected: "BIC"

actionButton — "Run Stepwise"
  class = "btn-primary w-100"
  icon = icon("play")
  launches blocking modal

[LASSO config — shown when LASSO selected]
radioGroupButtons — Lambda
  choices: "lambda.1se"  "lambda.min"
  selected: "lambda.1se"

actionButton — "Run LASSO"
  class = "btn-primary w-100"
  icon = icon("play")
  launches blocking modal
```

Main panel (right):
- Message area
- Advisory banner: persistent `bslib::card` with amber border — *"These results are advisory only. Confirm your final covariate selection in Step 4."*
- Output mirrors sidebar toggle selection; state preserved for both methods when toggling

Stepwise output (shown when Stepwise selected):
- Selected formula: `tags$code` block
- Selection path table: `DT::datatable` — Step, Action (added/removed), Variable, Criterion value
- Suggested variable list: styled badge list

LASSO output (shown when LASSO selected):
- Coefficient path plot: `renderPlot`
- Cross-validation plot: `renderPlot`
- Suggested variable list at chosen lambda: styled badge list

Placeholder shown for each method if not yet run.

---

**Step complete when:** at least one investigation tool has been run.

---

## 6.6 Step 4 — Covariate Confirmation

**Module file:** `R/module_analysis_covariate_confirm.R`

**UI function:** `analysis_covariate_confirm_ui(id)`

**Server function:** `analysis_covariate_confirm_server(id, shared_state)`

---

**Layout:** full-width — no sidebar.

---

**Top — summary card:**

`bslib::card` with light background, always visible, rendered via `renderUI`:
```
Study type:      Exposure-outcome association
Outcome:         aki (binary)
Exposure:        hypotension (binary)
Candidate pool:  age, asa_class, baseline_cr, sex, bmi  (5 variables)
Subject ID:      patient_id
```

---

**Import buttons row:**

```r
layout_columns(
  col_widths = c(3, 3, 6),
  actionButton(ns("import_stepwise"),
    "Import Stepwise Selection",
    icon = icon("download"),
    class = "btn-outline-secondary w-100"),
  actionButton(ns("import_lasso"),
    "Import LASSO Selection",
    icon = icon("download"),
    class = "btn-outline-secondary w-100"),
  tags$div(class = "text-muted small fst-italic pt-2",
    "Importing unchecks variables not selected by
     the method. Review and re-check any you wish
     to include.")
)
```

Import Stepwise button disabled if stepwise not run. Import LASSO button disabled if LASSO not run. Each shows confirmation modal before applying: *"This will uncheck variables not selected by [method]. Continue?"*

---

**Confirmation table:**

Search input above table. `DT::datatable` with columns:

| Column | Render type | Notes |
|---|---|---|
| Variable | Static text | Sortable; filterable |
| Type | Badge | |
| Include in model | Checkbox | All pre-checked by default |
| Stepwise suggestion | Static icon | ✓ selected, — not selected, — if not run |
| LASSO suggestion | Static icon | ✓ selected, — not selected, — if not run |
| Reference level | `selectInput` | Factor variables only; R factor level order |

---

**Confirm button:**

```r
actionButton(ns("confirm_covariates"),
  "Confirm Covariate Selection",
  icon = icon("circle-check"),
  class = "btn-primary w-100 mt-3")
```

On click:
- Writes checked variables to `analysis_spec$variable_roles$final_model_covariates`
- Writes reference levels to `analysis_spec$variable_roles$reference_levels`
- Marks Step 4 complete
- Shows success notification: *"Covariate selection confirmed. [N] variables will enter the model."*
- Clears pending state if previously stale

---

**Pending state behavior:**

If confirmation table is modified after a previous confirmation:
- Step 4 status → amber "Pending — unconfirmed changes"
- Confirm button reappears with pulsing amber border
- Step 5 Run Model button disabled
- Step 5 preflight card shows blocking error: *"Covariate selection has unconfirmed changes. Return to Step 4 and confirm before running."*

**Step complete when:** covariate selection confirmed at least once with no pending changes.

---

## 6.7 Step 5 — Model Specification

**Module file:** `R/module_analysis_modelspec.R`

**UI function:** `analysis_modelspec_ui(id)`

**Server function:** `analysis_modelspec_server(id, shared_state)`

---

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** model config and run button
- **Main panel (right):** preflight results, formula preview, R code preview, post-fit summary

---

**Sidebar (left):**

```
[Section: Model]
selectInput — Model type
  choices:
    "Linear regression"
    "Logistic regression"
    "Linear mixed model"      (disabled if no subject ID,
                               reason shown inline)
    "Logistic mixed model"    (disabled if no subject ID,
                               reason shown inline)
  width = "100%"

[Model options — visible only for mixed models]
[Section: Random Effects]
selectInput — Random intercept variable
  choices: subject ID variable (default) +
           cluster variable if different
  width = "100%"

selectInput — Random slope variable (optional)
  choices: c("None", time variable,
             candidate covariates)
  selected: "None"
  width = "100%"

[Advanced options — accordion, mixed models only]
bslib::accordion(open = FALSE,
  bslib::accordion_panel("Advanced Options",
    icon = icon("gear"),
    selectInput — Optimizer
      choices: "bobyqa" (default),
               "Nelder_Mead",
               "nlminbwrap"
      width = "100%"
  )
)

[hr]

[Preflight error inline message — renderUI]
# Shown only when preflight errors exist or
# unconfirmed covariate changes pending
tags$div(
  class = "text-danger small mt-1 mb-2",
  icon("triangle-exclamation"),
  "Resolve preflight errors before running —
   see details opposite"
)

actionButton — "Run Model"
  class = "btn-primary w-100"
  icon = icon("play")
  launches blocking modal
  two disabled states per §5.2
```

---

**Main panel (right):**

**Preflight card** — `bslib::card` with `id = ns("preflight_card")` for pulse animation target:
```
── Preflight ────────────────────────────────────────
✓  Outcome variable assigned
✓  Model type compatible with outcome
⚠  Events per variable: 12.9 — borderline
✓  No empty factor levels
✓  Complete-case reduction: 3.3%  (13 rows excluded)
```
Errors red, warnings amber, passes green. Always visible, auto-updating as spec changes.

**Formula preview card:**
```
aki ~ hypotension + age + asa_class + baseline_cr
```
`tags$code` styled block. Always visible, updates live.

**R code preview** — collapsible `bslib::accordion(open = FALSE)`:
Full executable R script. `tags$pre` / `tags$code` block. Copyable. Updates live with spec changes.

**Post-fit summary card** — `renderUI`, appears only after successful model run:
```
── Model Result ─────────────────────────────────────
Model:      Logistic regression
N analyzed: 387  (13 excluded — missing data)
Exposure:   hypotension
  OR: 2.34  (95% CI: 1.21 – 4.52)  p = 0.011
─────────────────────────────────────────────────────
⚠  Events per variable borderline — interpret cautiously
```

**Pulse animation implementation:**
```r
observeEvent(input$run_model_btn, {
  # fires when button is clicked in disabled state
  shinyjs::addClass(id = "preflight_card",
                    class = "preflight-pulse")
  shinyjs::delay(1000,
    shinyjs::removeClass(id = "preflight_card",
                         class = "preflight-pulse"))
})
```

CSS added to app header:
```css
@keyframes preflight-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(220, 53, 69, 0.6); }
  70%  { box-shadow: 0 0 0 10px rgba(220, 53, 69, 0); }
  100% { box-shadow: 0 0 0 0 rgba(220, 53, 69, 0); }
}
.preflight-pulse {
  animation: preflight-pulse 1s ease-out;
  border-color: #dc3545 !important;
}
```

**Step complete when:** model run successfully at least once.

---

## 6.8 Step 6 — Diagnostics

**Module file:** `R/module_analysis_diagnostics.R`

**UI function:** `analysis_diagnostics_ui(id)`

**Server function:** `analysis_diagnostics_server(id, shared_state)`

---

**Layout:** `layout_sidebar(position = "right")`
- **Main panel (left):** Run Diagnostics button + diagnostic output tabs
- **Sidebar (right):** at-a-glance diagnostics summary — read-only

---

**Main panel (left):**

If no model run: placeholder card — *"Run a model in Step 5 to enable diagnostics."* Button disabled.

**"Run Diagnostics"** button at top of panel:
```r
actionButton(ns("run_diagnostics"),
  "Run Diagnostics",
  icon = icon("stethoscope"),
  class = "btn-primary mb-3")
```
Launches blocking modal. Remains visible after run for re-running if model changes.

`navset_card_tab` below button — tabs conditional on model type:

**All models — Sample Accounting tab:**
- Total rows in frozen dataset
- Rows excluded (missing data): count and percentage
- Rows analyzed: count and percentage
- Missingness breakdown table: `DT::datatable` — variable, missing count, missing percentage — for all variables in the model
- Preflight warnings replayed as styled alert cards

**Linear regression — additional tabs:**

*Residuals tab:*
- Residuals vs fitted plot: `renderPlot`; horizontal reference line at zero
- Q-Q plot of standardized residuals: `renderPlot`
- Scale-location plot: `renderPlot`
- Breusch-Pagan test statistic and p-value: value card

*Influence tab:*
- Cook's distance plot: `renderPlot`; threshold line at 4/n
- Leverage vs residuals plot: `renderPlot`
- Top influential observations table: `DT::datatable` — `.edark_row_id`, Cook's distance, leverage, standardized residual; top 10 by Cook's distance

*Collinearity tab:*
- VIF table: `DT::datatable` — variable, VIF, tolerance
- Rows colored amber for VIF 5–10, red for VIF > 10
- Produced via `performance::check_collinearity()`

**Logistic regression — additional tabs:**

*Discrimination tab:*
- ROC curve: `renderPlot`
- AUC displayed as value card
- Optimal threshold table: threshold, sensitivity, specificity, PPV, NPV at Youden index

*Calibration tab:*
- Calibration plot: `renderPlot` — observed vs predicted probabilities in deciles
- Hosmer-Lemeshow test statistic and p-value: value card

*Predicted Probabilities tab:*
- Density plot of predicted probabilities by outcome group: `renderPlot`
- Summary table: mean predicted probability by outcome group

*Influence tab:*
- Cook's distance plot: `renderPlot`
- Top influential observations table: same format as linear regression

*Collinearity tab:*
- VIF table: same format as linear regression

*Separation tab (shown only if separation detected):*
- Plain-language explanation card
- Variable(s) involved
- Suggested actions

**Linear mixed model — additional tabs:**

*Residuals tab:*
- Residuals vs fitted plot: `renderPlot`
- Q-Q plot of residuals: `renderPlot`

*Random Effects tab:*
- Random effects Q-Q plot: `renderPlot`
- ICC value card
- Variance components table: group, variance, standard deviation
- Cluster size distribution: `renderPlot` — histogram of observations per cluster
- Cluster size summary table: min, median, mean, max observations per cluster

*Collinearity tab:*
- VIF table: same format as above

*Convergence tab:*
- Singular fit status: value card
- Convergence status: value card
- Optimizer used: value card
- If warnings present: plain-language explanation + suggested actions (simplify random effects structure, change optimizer)

**Logistic mixed model — additional tabs:**

*Calibration tab:*
- Marginal calibration plot: `renderPlot`
- Marginal AUC value card

*Random Effects tab:*
- Same as linear mixed model random effects tab

*Collinearity tab:*
- VIF table: same format as above

*Convergence tab:*
- Same as linear mixed model convergence tab

---

**Sidebar (right) — at-a-glance diagnostics summary:**

Read-only. Placeholder before run: *"Run diagnostics to see summary."*

After run — raw values only, no interpretive language:

```
── Run Info ──────────────────────────
Diagnostics run:    Nov 14 2024, 14:32
Model:              Logistic regression
N analyzed:         387 / 400

── Sample ────────────────────────────
Total rows:         400
Excluded:           13  (3.3%)
Analyzed:           387  (96.7%)

── Discrimination ────────────────────  [logistic only]
AUC:                0.810

── Calibration ───────────────────────  [logistic only]
Hosmer-Lemeshow:    χ² = 6.2,  p = 0.310

── Predicted Probabilities ───────────  [logistic only]
Mean (outcome = 0): 0.180
Mean (outcome = 1): 0.540

── Collinearity ──────────────────────
Max VIF:            2.3
Mean VIF:           1.8
Variables VIF > 5:  0
Variables VIF > 10: 0

── Influence ─────────────────────────
Max Cook's D:       0.040
Observations > 4/n: 2

── Residuals ─────────────────────────  [linear only]
Residual SD:        1.230
Breusch-Pagan p:    0.410

── Random Effects ────────────────────  [mixed only]
ICC:                0.310
N clusters:         42
Median cluster size: 9
Singular fit:       No
Converged:          Yes
Optimizer:          bobyqa

── Warnings ──────────────────────────
⚠  Events per variable: 12.9
⚠  2 observations exceed Cook's D threshold
```

Warnings section: threshold-based flags only. Values section: raw numbers only. No interpretive language anywhere in the sidebar.

**Step complete when:** diagnostics run at least once.

---

## 6.9 Step 7 — Results

**Module file:** `R/module_analysis_results.R`

**UI function:** `analysis_results_ui(id)`

**Server function:** `analysis_results_server(id, shared_state)`

---

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** output object selection and generate button
- **Main panel (right):** generated output objects — `navset_card_tab`

---

**Sidebar (left):**

```
[Section: Output Objects]
uiOutput — conditional checkbox list
  rendered based on fitted model type

  ☑ Summary                      [always checked;
                                   not unchecable;
                                   auto-generated on
                                   model run]

  ☑ Results table
    └── ☑ Combined univariable + multivariable
            [sub-checkbox, indented;
             enabled only when results table checked;
             checked by default]

  ☑ Fit statistics
  ☐ Forest plot
  ☐ Methods paragraph

[hr]

actionButton — "Generate Selected Outputs"
  class = "btn-primary w-100"
  icon = icon("wand-magic-sparkles")
  launches blocking modal
  disabled if no model has been run
```

If no model run: placeholder card — *"Run a model in Step 5 to enable results."* Button disabled.

**Note on decimal places:** all numeric values displayed to maximum 3 decimal places. Values < 0.001 shown as *"< 0.001"*. Dynamic rounding is a planned future improvement (§12).

---

**Main panel (right) — `navset_card_tab`:**

Message area at top of each tab. Stale banner on all tabs if model rerun since last generation. Placeholder card for any unselected output.

---

**Summary tab — always present, auto-generated on model run:**

`bslib::card` — two sections:

*Primary result card:*
```
── Model Result ──────────────────────────────────────
Model:           Logistic regression
Outcome:         aki
Exposure:        hypotension
N analyzed:      387  (13 excluded — missing data)
──────────────────────────────────────────────────────
Primary estimate:
  hypotension    OR 2.34  (95% CI: 1.21 – 4.52)
                 p = 0.011
──────────────────────────────────────────────────────
⚠  Events per variable: 12.9 — borderline
```

Exposure row always shown prominently. Warning flags from preflight and fitting replayed. Facts and values only — no interpretive language.

---

**Results Table tab:**

Two display modes controlled by combined table sub-checkbox.

**Mode 1 — Combined univariable + multivariable (default):**

`gtsummary::tbl_merge()` output.

| Variable | Unadjusted OR (95% CI) | p | Adjusted OR (95% CI) | p |
|---|---|---|---|---|
| hypotension | 2.11 (1.14 – 3.91) | 0.017 | 2.34 (1.21 – 4.52) | 0.011 |
| age | 1.03 (1.01 – 1.06) | 0.004 | 1.02 (0.99 – 1.05) | 0.091 |
| asa_class | | | | |
| — II vs I | 1.84 (0.92 – 3.71) | 0.086 | 1.71 (0.84 – 3.49) | 0.139 |
| — III vs I | 3.21 (1.54 – 6.68) | 0.002 | 2.98 (1.41 – 6.32) | 0.004 |
| baseline_cr | 2.87 (1.93 – 4.27) | < 0.001 | 2.64 (1.74 – 4.01) | < 0.001 |
| bmi | 1.02 (0.98 – 1.06) | 0.341 | — | — |

Variables in univariable screen but excluded from multivariable model: unadjusted estimate shown, "—" in adjusted columns.
Footnote: *"— Variable considered but not included in the final multivariable model."*

Exposure variable row bolded. Factor variables show reference level in italics below variable name.

**Mode 2 — Separate tables:**
Two sequential tables in same tab — unadjusted then adjusted.

**Table footnotes — logistic regression:**
- *"OR = odds ratio; CI = confidence interval"*
- *"P-values are Wald z-tests"*
- *"Complete-case analysis. N = [X] of [Y] observations included."*
- *"Reference levels: [variable] = [level], ..."*

**Table footnotes — logistic mixed model:**
- *"OR = odds ratio; CI = confidence interval"*
- *"P-values derived from likelihood ratio tests. Confidence intervals are Wald-based."*
- *"Complete-case analysis. N = [X] observations from [Y] clusters included."*
- *"Reference levels: [variable] = [level], ..."*

**Table footnotes — linear regression:**
- *"β = unstandardized regression coefficient; CI = confidence interval"*
- *"P-values are t-tests"*
- *"Complete-case analysis. N = [X] of [Y] observations included."*
- *"Reference levels: [variable] = [level], ..."*

**Mixed model tables — random effects summary appended below fixed effects:**

Linear mixed model:
```
Random Effects
  Random intercept SD:    0.840
  Residual SD:            1.120
  ICC:                    0.310
  N observations:         1842
  N clusters:             42
```

Logistic mixed model:
```
Random Effects
  Random intercept variance:  0.710
  ICC:                        0.180
  N observations:             1842
  N clusters:                 42
```

---

**Fit Statistics tab:**

`DT::datatable` — metric name, value. Maximum 3 decimal places.

Linear regression: N analyzed, R², Adjusted R², RMSE, Residual SD, F-statistic, AIC, BIC.

Logistic regression: N analyzed, N events, Event rate, Pseudo R² (McFadden), Pseudo R² (Nagelkerke), AUC, AIC, BIC, Log-likelihood.

Linear mixed model: N observations, N clusters, Marginal R², Conditional R², ICC, AIC, BIC, Log-likelihood, Random intercept SD, Residual SD.

Logistic mixed model: N observations, N clusters, N events, Event rate, Marginal AUC, AIC, BIC, Log-likelihood, Random intercept variance, ICC.

---

**Forest Plot tab:**

`ggplot2` horizontal coefficient forest plot.

- One row per model term: exposure + covariates; intercept excluded; factor variables show one row per non-reference level
- Point estimate: filled circle, fixed size
- Horizontal error bars: 95% CI
- Vertical reference line at null effect: 0 for linear; 1 for logistic on log scale
- Exposure variable row: primary blue `#2c7be5`; all other rows: grey
- Variable labels on y-axis; factor levels in parentheses
- X-axis label: *"β (95% CI)"* for linear; *"OR (95% CI)"* for logistic
- Mixed models: fixed effects only; note below — *"Random effects not shown"*

Placeholder if not selected.

---

**Methods tab:**

Selectable plain text inside `bslib::card`. `tags$p` rendered text — not a plot, not an image. Directly copyable from UI.

Auto-generated from `analysis_spec`. Example for logistic regression:

```
Statistical Methods

Multivariable logistic regression was used to assess the association
between hypotension (exposure) and AKI (outcome), adjusting for age,
ASA class, and baseline creatinine. The odds ratio (OR) and 95%
confidence interval (CI) were reported as the measure of association.
P-values were derived from Wald z-tests. Complete-case analysis was
used; 387 of 400 observations were included (13 excluded due to
missing data). Statistical analyses were performed in R (version
X.X.X) using the following packages: stats, gtsummary, ggplot2.
```

Example for logistic mixed model:

```
Statistical Methods

A generalized linear mixed-effects model with a logistic link function
was used to assess the association between hypotension (exposure) and
AKI (outcome), adjusting for age, ASA class, and baseline creatinine.
A random intercept for patient_id was included to account for
clustering. Fixed effects are reported as odds ratios (OR) with 95%
confidence intervals (CI). P-values were derived from likelihood ratio
tests. Confidence intervals are Wald-based. Complete-case analysis was
used; 1842 observations from 42 clusters were included. Statistical
analyses were performed in R (version X.X.X) using the following
packages: lme4, lmerTest, gtsummary, ggplot2.
```

Also exported as:
- Text section in Word and HTML report
- Standalone `methods.txt` in `tables/results/` folder of zip

---

**Key behaviors:**
- Summary tab auto-generated on model run — visible immediately without clicking generate
- All other outputs require explicit generate click
- Combined vs separate table mode requires regeneration on change
- Variables excluded from multivariable shown in combined table with "—" in adjusted columns
- If univariable screen not run in Step 3 and results table selected, univariable models run as part of generation — progress modal reflects this
- Methods text generated from `analysis_spec` — not a static template

**Step complete when:** outputs generated at least once.

---

## 6.10 Step 8 — Export

**Module file:** `R/module_analysis_export.R`

**UI function:** `analysis_export_ui(id)`

**Server function:** `analysis_export_server(id, shared_state)`

---

**Layout:** full-width — `layout_columns(col_widths = c(6, 6))`. No sidebar.

---

**Left column — export configuration:**

```
[Section: Presets]
radioGroupButtons — Export preset
  choices:
    "Custom Export"         ← default selected
    "Analysis Package"
    "Manuscript Items"
    "Report Only"
    "Everything"

  Selecting a preset pre-checks relevant items.
  Modifying any item after selecting a preset
  automatically reverts to "Custom Export".

─────────────────────────────────────────────────────

[Section: Tables]
  [Select all]  [Deselect all]

  Setup
    ☐ Dataset summary

  Table 1
    ☐ Table 1 — Overall
    ☐ Table 1 — By exposure      (greyed + tooltip if not generated)
    ☐ Table 1 — By outcome       (greyed + tooltip if not generated)

  Variable Investigation
    ☐ Univariable screen table
    ☐ Stepwise selection log     (greyed if stepwise not run)

  Results
    ☐ Multivariable results table  (greyed if not generated)
    ☐ Univariable results table    (greyed if not generated)
    ☐ Fit statistics               (greyed if not generated)
    ☐ Methods paragraph            (greyed if not generated)

  Diagnostics
    ☐ Diagnostic summary table     (greyed if not generated)
    ☐ VIF table                    (greyed if not generated)
    ☐ Sample accounting table      (greyed if not generated)

─────────────────────────────────────────────────────

[Section: Figures]
  [Select all]  [Deselect all]

  Variable Investigation
    ☐ Collinearity heatmap         (greyed if not generated)
    ☐ Cramér's V matrix            (greyed if not generated;
                                    categorical candidates only)
    ☐ LASSO coefficient path       (greyed if not run)
    ☐ LASSO cross-validation plot  (greyed if not run)

  Diagnostics
    ☐ ROC curve                    (logistic only;
                                    greyed if not generated)
    ☐ Calibration plot             (greyed if not generated)
    ☐ Predicted probabilities plot (logistic only;
                                    greyed if not generated)
    ☐ Residuals vs fitted          (greyed if not generated)
    ☐ Q-Q plot                     (greyed if not generated)
    ☐ Scale-location plot          (linear only;
                                    greyed if not generated)
    ☐ Influence plot               (greyed if not generated)
    ☐ Random effects Q-Q plot      (mixed only;
                                    greyed if not generated)
    ☐ Cluster size distribution    (mixed only;
                                    greyed if not generated)

  Results
    ☐ Forest plot                  (greyed if not generated)

─────────────────────────────────────────────────────

[Section: Report]
  ☐ Analysis report
    radioGroupButtons — Format
      choices: "Word (.docx)"  "HTML"
      selected: "Word (.docx)"
      shown only when report checkbox checked

  Report contents (fixed in v1):
    · Analysis specification summary
    · Methods paragraph
    · Table 1 (all generated stratifications)
    · Results tables
    · Figures (forest plot, ROC, calibration
               if generated)
    · Diagnostics summary
    · Appendix: R script + analysis specification

─────────────────────────────────────────────────────

[Section: Reproducibility]
  [Select all]  [Deselect all]

  ☐ R script
      disabled + tooltip when self-contained
      package checked:
      "Included inside the self-contained package.
       Uncheck package to export separately."

  ☐ Analysis specification (JSON)
      disabled + tooltip when self-contained
      package checked (same as above)

  ☐ Self-contained analysis package
      When checked:
        → R script: unchecked + disabled
        → Analysis specification: unchecked + disabled
        → Data export master checkbox: checked + greyed
      note: "Includes frozen dataset, analysis
             specification, R script, and manifest.
             Data sensitivity is the user's
             responsibility."

  ── Data export ─────────────────────────────────
  ☐ Include data export              ← master checkbox
                                       checked + greyed
                                       when self-contained
                                       package checked

  └── [shown when master checkbox checked]
        ☐ RDS                        ← default when
                                       package forces open
        ☐ CSV
        ☐ SPSS .sav
        ☐ Stata .dta
        ☐ Excel .xlsx

        [validation: master checked but no format
         selected → red border on format group]

─────────────────────────────────────────────────────

[Section: Full Result Object]
  ☐ Full analysis result (RDS)
      note: "Contains all fitted model objects,
             tables, and plots as R objects.
             For use in R. File may be large."

─────────────────────────────────────────────────────

[Validation message area]
  uiOutput — inline red text above download button
  shown only when validation issues exist:
  · "Select at least one data format."
  · "No items selected."

actionButton — "Download (X items selected)"
  class = "btn-primary w-100"
  icon = icon("download")
  label updates reactively with item count
  disabled when nothing selected
  validation fires before modal on click
  launches blocking modal when valid
```

---

**Preset bundle contents:**

| Item | Analysis Package | Manuscript Items | Report Only | Everything |
|---|---|---|---|---|
| **Tables** | | | | |
| Dataset summary | | | | ✓ |
| Table 1 — Overall | | ✓ | | ✓ |
| Table 1 — By exposure | | ✓ | | ✓ |
| Table 1 — By outcome | | ✓ | | ✓ |
| Univariable screen table | | | | ✓ |
| Stepwise selection log | | | | ✓ |
| Multivariable results table | | ✓ | | ✓ |
| Univariable results table | | ✓ | | ✓ |
| Fit statistics | | | | ✓ |
| Methods paragraph | | ✓ | | ✓ |
| Diagnostic summary table | | | | ✓ |
| VIF table | | | | ✓ |
| Sample accounting table | | | | ✓ |
| **Figures** | | | | |
| Collinearity heatmap | | | | ✓ |
| Cramér's V matrix | | | | ✓ |
| LASSO coefficient path | | | | ✓ |
| LASSO cross-validation | | | | ✓ |
| ROC curve | | ✓ | | ✓ |
| Calibration plot | | ✓ | | ✓ |
| Predicted probabilities | | | | ✓ |
| Residuals vs fitted | | | | ✓ |
| Q-Q plot | | | | ✓ |
| Scale-location plot | | | | ✓ |
| Influence plot | | | | ✓ |
| Random effects Q-Q | | | | ✓ |
| Cluster size distribution | | | | ✓ |
| Forest plot | | ✓ | | ✓ |
| **Report** | | | | |
| Analysis report | | | ✓ | ✓ |
| **Reproducibility** | | | | |
| Data — RDS | ✓ | | | ✓ |
| Data — CSV | | | | ✓ |
| Data — SPSS .sav | | | | ✓ |
| Data — Stata .dta | | | | ✓ |
| Data — Excel .xlsx | | | | ✓ |
| R script | | | | ✓ |
| Analysis specification JSON | | | | ✓ |
| Self-contained package | ✓ | | | ✓ |
| **Full Result Object** | | | | |
| Full analysis result RDS | | | | ✓ |

---

**Right column — live zip preview:**

`renderUI` updating reactively. Selected items `✓` green, unselected muted `—`.

```
analysis_2024-11-14_143022/
│
├── tables/
│   ├── table1/
│   │   ├── table1_overall.docx              ✓
│   │   ├── table1_by_exposure.docx          ✓
│   │   └── table1_by_outcome.docx           —
│   ├── variable_investigation/
│   │   ├── univariable_screen.docx          —
│   │   └── stepwise_selection_log.docx      —
│   ├── results/
│   │   ├── multivariable_results.docx       ✓
│   │   ├── univariable_results.docx         ✓
│   │   ├── fit_statistics.docx              ✓
│   │   └── methods.txt                      ✓
│   └── diagnostics/
│       ├── diagnostic_summary.docx          —
│       ├── vif_table.docx                   —
│       └── sample_accounting.docx           —
│
├── figures/
│   ├── variable_investigation/
│   │   ├── collinearity_heatmap.png         —
│   │   ├── cramers_v_matrix.png             —
│   │   ├── lasso_coefficient_path.png       —
│   │   └── lasso_cross_validation.png       —
│   ├── diagnostics/
│   │   ├── roc_curve.png                    ✓
│   │   ├── calibration_plot.png             ✓
│   │   ├── predicted_probabilities.png      —
│   │   ├── residuals_vs_fitted.png          —
│   │   ├── qq_plot.png                      —
│   │   ├── scale_location.png               —
│   │   ├── influence_plot.png               —
│   │   ├── random_effects_qq.png            —
│   │   └── cluster_size_distribution.png    —
│   └── results/
│       └── forest_plot.png                  ✓
│
├── report/
│   └── analysis_report.docx                 —
│
├── reproducibility/
│   ├── data/
│   │   ├── analysis_dataset.rds             —
│   │   ├── analysis_dataset.csv             —
│   │   ├── analysis_dataset.sav             —
│   │   ├── analysis_dataset.dta             —
│   │   └── analysis_dataset.xlsx            —
│   ├── analysis_script.R                    —
│   ├── analysis_specification.json          —
│   └── package/
│       ├── analysis_dataset.rds             —
│       ├── analysis_specification.json      —
│       ├── analysis_script.R                —
│       └── manifest.json                    —
│
└── objects/
    └── analysis_result.rds                  —
```

Compact summary card above preview:
```
Selected:         8 items
Estimated size:   ~2.4 MB
```

---

**Blocking modal during download:**

```
Assembling export...
✓  Validating selections
✓  Collecting tables
⟳  Rendering figures...
○  Packaging dataset
○  Writing R script
○  Building zip archive
○  Finalising
```

On completion: modal closes, browser download initiates, success notification shown.
On error: failed step shown in red, plain-language message, Close button appears.

**Step complete when:** download initiated at least once.
