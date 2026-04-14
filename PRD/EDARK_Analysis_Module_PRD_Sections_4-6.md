# EDARK Analysis Module — PRD Sections 4–6
## (Frozen — Revised)

---

## Section 4 — Analytic Scope

> **REMINDER: BEFORE IMPLEMENTING THE ANALYSIS MODULE, REFACTOR THE EXISTING `withProgress` TOAST PATTERN IN `module_report.R` TO USE A BLOCKING MODAL WITH STEP-LIST PROGRESS DISPLAY. THE ANALYSIS MODULE MUST USE THIS SAME MODAL PROGRESS PATTERN FROM DAY ONE. DO NOT IMPLEMENT ANALYSIS MODULE PROGRESS USING `withProgress` TOAST.**

### 4.1 Model and Method Inventory

All analytical methods available in v1. Linear regression and logistic regression serve dual roles — both as the univariable outcome regression screen during variable selection and as the final multivariable model.

| Method | Purpose | Outcome type | Data structure | Clustered | Primary package | P-value method |
|---|---|---|---|---|---|---|
| Descriptive summary / Table 1 | Population description; baseline characteristics by group | Any | Any | Any | `gtsummary` | Optional group comparison tests via `stats`; see §3.7 |
| Linear regression | Univariable outcome screen; multivariable adjusted model | Continuous | One row per subject | No | `stats::lm` | Native t-tests via `summary()` |
| Logistic regression | Univariable outcome screen; multivariable adjusted model | Binary (2-level factor) | One row per subject | No | `stats::glm` | Wald z-tests via `summary()` |
| Linear mixed model | Multivariable model for repeated measures or clustered continuous outcomes | Continuous | Multiple rows per subject | Yes | `lme4` + `lmerTest` | Satterthwaite approximated degrees of freedom via `lmerTest` |
| Logistic mixed model | Multivariable model for repeated measures or clustered binary outcomes | Binary (2-level factor) | Multiple rows per subject | Yes | `lme4::glmer` | Wald z-tests via `summary()`. Interpret with caution in small samples or with rare outcomes. |
| Stepwise selection | Variable selection helper; advisory only | Continuous or binary | One row per subject | No | `stats::step` | From final selected `lm` or `glm` object |
| LASSO penalized regression | Variable selection helper; advisory only | Continuous or binary | One row per subject | No | `glmnet` | None by design — no inference table produced |
| Collinearity summary | Pre-fit pairwise correlation screen; post-fit formal VIF | Continuous candidates | Any | Any | `performance`, `correlation` | Not applicable |

### 4.2 P-value and Confidence Interval Methods

All confidence intervals throughout the module are **Wald-based**. This applies to all model types without exception. Wald CIs are instantaneous, never fail, and are the standard in clinical research reporting. Profile likelihood CIs are deferred to v1.5 as an advanced option.

| Method | P-value approach | Confidence intervals | Notes |
|---|---|---|---|
| Linear regression | t-tests, native from `summary()` | Wald-based via `confint.default()` | Standard OLS assumptions apply |
| Logistic regression | Wald z-tests, native from `summary()` | Wald-based via `confint.default()` | Acceptable for adequate sample sizes |
| Linear mixed model | Satterthwaite approximated degrees of freedom via `lmerTest` | Wald-based via `confint.default()` | Satterthwaite is the standard accepted approach in clinical research |
| Logistic mixed model | Wald z-tests, native from `summary()` | Wald-based via `confint.default()` | Interpret with caution in small samples, sparse data, or near-boundary random effects. Preflight validation flags inadequate event counts. |
| Stepwise | From final `lm` or `glm` object | From final model object | Inference on stepwise-selected model labeled advisory |
| LASSO | None | None | Explicitly exploratory; coefficient path and selected variable list only |

**Publication table footnotes:** All tables include "Wald-based confidence intervals." Linear regression footnotes: "P-values from t-tests." Logistic regression footnotes: "P-values from Wald z-tests." Linear mixed model footnotes: "P-values from Satterthwaite approximated degrees of freedom." Logistic mixed model footnotes: "P-values from Wald z-tests. Interpret with caution in small samples or with rare outcomes."

### 4.3 Full Package Dependencies

| Function | Packages |
|---|---|
| Modeling | `stats` (base R), `lme4`, `lmerTest`, `glmnet` |
| Tidy extraction | `broom`, `broom.mixed` |
| Parameter tables and inference | `parameters` |
| Diagnostics | `performance`, `insight` |
| Correlation and collinearity | `correlation` |
| Heteroskedasticity testing | `lmtest` |
| ROC / AUC | `pROC` |
| Separation detection | `detectseparation` |
| Publication tables | `gtsummary`, `flextable`, `gt` |
| Plots | `ggplot2`, `patchwork` |
| Dataset export | `haven`, `writexl` |
| Report generation | `officer`, `rmarkdown` |
| Serialization and packaging | `jsonlite`, `zip`, `digest` |
| Utilities | `dplyr`, `tidyr`, `tibble` |

### 4.4 Hard Constraints — Model Availability

Unavailable models are visibly disabled in the UI with a plain-language explanation. Never silently hidden.

| Outcome type | Subject ID assigned | Available models | Disabled — reason shown |
|---|---|---|---|
| Continuous | No | Linear regression | Logistic models: *"Outcome is continuous"*; Mixed models: *"No subject ID assigned"* |
| Continuous | Yes | Linear regression, Linear mixed model | Logistic models: *"Outcome is continuous"* |
| Binary | No | Logistic regression | Linear models: *"Outcome is binary"*; Mixed models: *"No subject ID assigned"* |
| Binary | Yes | Logistic regression, Logistic mixed model | Linear models: *"Outcome is binary"* |
| Unrecognized / unassigned | Any | None | All: *"Assign and confirm an outcome variable before selecting a model"* |

**Note on propensity score methods for v1.5:** PSM, IPTW, and PS-adjusted regression are not implemented in v1. When added they will require a binary exposure variable and will function as a two-stage design-then-analysis workflow. Their addition does not require changes to the constraint logic above.

### 4.5 Soft Nudges — Contextual Guidance

Surfaced as dismissible banners at the relevant workflow step. Never blocking unless stated.

| Condition | Message | Stage |
|---|---|---|
| Multiple rows per subject detected, no subject ID assigned | "Your data may have repeated measures. Consider assigning a subject ID variable and using a mixed model." | Role assignment |
| Single row per subject confirmed | "Data appears cross-sectional. Standard regression is appropriate." | Role assignment |
| Any missing data in selected variables | "X rows contain missing values across selected variables. Complete-case analysis will exclude these. Missing data volume should be reported in your methods." | Preflight |
| Complete-case reduction > 20% | "Complete-case analysis will exclude more than 20% of your dataset. Review missingness carefully before proceeding." | Preflight |
| Events per candidate variable < 10 (logistic models) | "Fewer than 10 outcome events per candidate variable. Reduce your covariate list to avoid overfitting." | Preflight |
| Pairwise candidate correlation > 0.7 (pre-fit screen) | "High correlation detected between some candidate variables. Review the collinearity summary before finalizing your covariate list." | Variable selection |
| Post-fit VIF 5–10 | "Moderate variance inflation detected. Review the VIF table in diagnostics and interpret affected estimates cautiously." | Diagnostics |
| Post-fit VIF > 10 | "High variance inflation detected. One or more predictors may be redundant. Review the VIF table." | Diagnostics |
| Singular fit warning from mixed model | "The mixed model produced a singular fit. The random effects structure may be too complex for your data. Consider simplifying." | Diagnostics |
| Convergence warning from mixed model | "The mixed model did not converge. Consider simplifying the random effects structure or changing the optimizer." | Diagnostics |
| Rare factor level (< 5 observations in any level) | "Variable X has a factor level with fewer than 5 observations. This may cause model instability or separation." | Preflight |

**Note on VIF timing:** pre-fit, the app screens for high pairwise correlation among candidates as an early soft advisory. Formal VIF via `performance::check_collinearity()` requires a fitted model object and is computed post-fit in the diagnostics stage. Post-fit VIF is a transparency and reporting tool — the app does not prompt the user to remove variables and refit.

### 4.6 Computational Batching — Independent Run Buttons

Each computationally meaningful step has its own explicit run button. No step silently triggers another. Each button launches the blocking modal progress display with a step-list and per-step status icons.

| Step | Button label | Notes |
|---|---|---|
| Table 1 generation | "Generate Table 1" | `gtsummary` can be slow on wide datasets |
| Univariable outcome screen | "Run Univariable Screen" | One `lm` or `glm` fit per candidate variable |
| Stepwise selection | "Run Stepwise Selection" | Iterative refitting |
| LASSO | "Run LASSO" | Single cross-validated fit |
| Main model fit | "Run Model" | Fast for `lm`/`glm`; moderate for mixed models |
| Diagnostics | "Run Diagnostics" | Post-fit extraction |
| Generate results objects | "Generate Selected Outputs" | Dependent on objects selected |

### 4.7 Deferred to Future Versions

**Planned for future versions:**
- Propensity score matching
- Inverse probability treatment weighting
- Propensity score-adjusted regression
- Generalized estimating equations
- Multinomial logistic regression
- Ordinal logistic regression
- Poisson and negative binomial regression
- Marginal effects and predicted value plots
- Analysis package import
- Likelihood ratio test p-values for logistic mixed models (v1.5 advanced option)
- Profile likelihood confidence intervals for logistic regression (v1.5 advanced option)

**Out of scope:**
- Survival and time-to-event models
- Bayesian models
- Machine learning classifiers
- Mediation and structural equation modeling
- Multiple imputation
- Arbitrary R code execution

---

## Section 5 — Workflow and Sequencing

### 5.1 Overview

The analysis module is Tab 4 in the main `page_navbar`, labelled **Analyze**. Within the tab, the eight steps are rendered as a `bslib::navset_pill` — horizontal pills consistent with existing app navigation patterns. Each pill is a `bslib::nav_panel` containing its own `bslib::layout_sidebar`. The sidebar position (left or right) is determined by whether the step is config-heavy or output-heavy:

- **Sidebar left:** main panel is the primary output area; sidebar contains controls that drive what is shown
- **Sidebar right:** main panel is the primary action area; sidebar summarizes committed decisions
- **No sidebar:** Steps 4 and 8 use full-width layouts

When a step produces more than one output object, the main panel contains a `bslib::navset_card_tab` with one tab per output, consistent with the existing Prepare tab pattern.

```
Tab 4: Analyze
└── navset_pill (8 steps, horizontal)
    ├── Step 1: Setup                  layout_sidebar(position = "right")
    ├── Step 2: Table 1                layout_sidebar(position = "left")
    ├── Step 3: Variable Investigation full-width, internal vertical navset_pill
    ├── Step 4: Covariate Confirmation full-width
    ├── Step 5: Model Specification    layout_sidebar(position = "left")
    ├── Step 6: Diagnostics            layout_sidebar(position = "right")
    ├── Step 7: Results                layout_sidebar(position = "left")
    └── Step 8: Export                 full-width, layout_columns(col_widths = c(6,6))
```

The step rail is non-blocking — the user can navigate to any step at any time. The single hard constraint is that the **Run Model** button in Step 5 is disabled until: Step 1 has a minimum valid spec (outcome assigned, at least one exposure or candidate covariate assigned), and Step 4 covariate confirmation has no pending unconfirmed changes.

Each pill label includes a status indicator updated dynamically:
- **Not started** — muted, no icon
- **In progress** — blue, partial config present
- **Complete** — green check icon
- **Stale** — amber warning icon

### 5.2 Global UI Principles

These apply across all eight steps without exception.

**Run / generate buttons always live in the config panel.** Regardless of sidebar position, any button that triggers computation is in the config area — never in the output area.

**No per-object download buttons in output panels.** All downloads are handled exclusively in Step 8 Export.

**Every output panel has a consistent message area at the top.** Status messages, warnings, and placeholder text appear in a fixed message card at the top of the main panel before any output objects. This is present on every step, every time.

**Placeholder objects for ungenerated outputs.** If an output has not been generated or was not selected, a placeholder card appears in its position with a message explaining why it is empty. No blank spaces.

**Blocking modal with step-list progress display for all time-consuming operations.** Any operation that may take more than approximately two seconds launches a blocking modal showing a step list with per-step status icons (pending: grey circle, running: blue spinner, complete: green check, error: red x). The user cannot interact with the app while the modal is open. Operations requiring this treatment:
- Generate Table 1
- Run Univariable Screen
- Run Stepwise
- Run LASSO
- Run Model
- Run Diagnostics
- Generate Selected Outputs (Step 7)
- Assemble and download export zip (Step 8)

**Inline spinner only** for operations expected to complete in under two seconds.

**Run Model disabled state has two distinct visual treatments:**
- *Greyed — spec incomplete:* standard disabled appearance
- *Greyed — preflight errors or pending unconfirmed covariate changes:* disabled with persistent red inline message below button; clicking triggers a one-second pulse animation on the preflight card via `shinyjs`

### 5.3 Step-by-Step Specification

#### Step 1 — Setup

**Layout:** `layout_sidebar(position = "right")`
- **Main panel (left):** role assignment table
- **Sidebar (right):** role summary — read-only

**Entry state:** before "Start Analysis" is clicked, the main panel shows only a **"Start Analysis"** button and a compact summary of the working dataset dimensions. Clicking freezes `shared_state$dataset_working` into `shared_state$analysis_data`, appends `.edark_row_id`, computes the dataset signature, and initializes `analysis_spec`.

**Main panel — role assignment table:**

One row per variable. Search and filter input above table.

| Column | Input type | Notes |
|---|---|---|
| Variable name | Static text | Sortable; filterable |
| Detected type | Static badge | Numeric, factor, character, datetime |
| Outcome | Radio button | Single select across all rows |
| Exposure | Radio button | Single select across all rows |
| Candidate covariate | Checkbox | Multiple selections allowed |
| Subject ID | Radio button | Single select across all rows |
| Cluster | Radio button | Single select across all rows |
| Time | Radio button | Single select across all rows |
| Reference level | Single select dropdown | Factor variables only; R factor level order; "—" for non-factor |

Radio button columns (outcome, exposure, subject ID, cluster, time) each have a **"Clear"** button in the column header.

Mutual exclusivity enforced reactively:
- Assigning outcome or exposure automatically unchecks candidate covariate for that variable
- Assigning subject ID, cluster, or time automatically unchecks candidate covariate for that variable
- Checking candidate covariate clears outcome, exposure, and structural role assignments for that variable

**Sidebar (right) — read-only role summary:**

```
Study type:     Exposure-outcome association
Outcome:        aki (binary)
Exposure:       hypotension (binary)
Covariates:     age, asa_class, baseline_cr  (3)
Subject ID:     patient_id
Cluster:        —
Time:           —
─────────────────────────────────────────────
Dataset:        400 rows · 14 variables
Complete cases: 387 / 400 across selected variables
```

Study type derives from role assignments per §1.4 and updates live. Unassigned roles show as muted "— not assigned".

**Defaults written to `analysis_spec` from Step 1:**

| Field | Default |
|---|---|
| `table1_variables` | Exposure + outcome + full candidate pool in role assignment order |
| `univariable_test_pool` | Full candidate pool |
| `final_model_covariates` | Full candidate pool |

**Step complete when:** outcome variable is assigned.

---

#### Step 2 — Table 1

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** configuration and generate button
- **Main panel (right):** generated table output

**Sidebar (left):**
- Stratification checkboxes: `☐ By Exposure` and `☐ By Outcome` independently checkable; defaults per §3.7 study type rules
- P-value toggle: off by default for exposure stratification; on by default for outcome stratification; tooltip explaining purpose
- Standardized Mean Difference toggle: on by default
- **"Generate Table 1"** button — launches blocking modal

**Main panel (right) — `navset_card_tab`:**
- **Overall** tab — always present; unstratified Table 1
- **By Exposure** tab — present only if exposure assigned and stratification checkbox checked
- **By Outcome** tab — present only if outcome assigned and stratification checkbox checked

Table column structure when stratified: Overall column first, then stratification level columns, p-values between stratified levels (if enabled).

Variables included: exposure first, then outcome, then all candidate covariates in role assignment order. No user selection of which variables to include.

Placeholder cards for tabs that exist but weren't generated. No tab rendered for structurally impossible stratifications.

**Step complete when:** Table 1 has been generated at least once.

---

#### Step 3 — Variable Investigation

**Layout:** full-width. A `navset_pill` with `nav_stacked = TRUE` (vertical pills) on the left. Three tools:

```
● Univariable Screen
  Collinearity
  Stepwise / LASSO
```

Each pill renders a `layout_sidebar(position = "left")` to its right.

**Univariable Screen pill:**
- Sidebar: **"Run Univariable Screen"** button; launches blocking modal
- Main panel: results table — variable, estimate (β or OR), 95% CI, p-value, sorted by p-value ascending; model family noted below table
- Model automatically selected: `lm` for continuous outcome, `glm(family = binomial)` for binary outcome; always standard (non-mixed) regardless of clustering; note shown: *"Unadjusted associations. Clustering not accounted for in screening models."*
- Always runs on all Step 1 candidate covariates — no pool selector

**Collinearity pill:**
- Sidebar: descriptive text only; soft warning flags listed if any pairs exceed threshold; no run button — computed automatically from candidate pool on tab entry
- Main panel `navset_card_tab`:
  - **Correlation Heatmap** tab: numeric candidates; clustered by hierarchical ordering for large variable sets; scrollable; note if > 30 variables: *"Showing top 30 variables. Full matrix available in export."*
  - **Cramér's V** tab: categorical candidates; shown only if categorical candidates exist
  - **Flagged Pairs** tab: always shown; variable pair, correlation value, warning level; amber > 0.7, red > 0.9

**Stepwise / LASSO pill:**
- Sidebar: `radioGroupButtons` toggle — `[ Stepwise ] [ LASSO ]`
  - Stepwise config: direction (backward default / forward), criterion (BIC default / AIC), **"Run Stepwise"** button
  - LASSO config: lambda (lambda.1se default / lambda.min), **"Run LASSO"** button
- Main panel: mirrors sidebar toggle selection; state preserved for both methods when toggling
  - Stepwise output: selected formula, selection path log table, suggested variable list
  - LASSO output: coefficient path plot, cross-validation plot, suggested variable list
  - Advisory banner: *"These results are advisory only. Confirm your final covariate selection in Step 4."*

**Step complete when:** at least one investigation tool has been run.

---

#### Step 4 — Covariate Confirmation

**Layout:** full-width — no sidebar.

**Top — summary card:** study type, outcome, exposure, candidate pool count, subject ID. Read-only.

**Import buttons row:**
- **"Import Stepwise Selection"** — unchecks variables not selected by stepwise; confirmation prompt; disabled if stepwise not run
- **"Import LASSO Selection"** — same for LASSO
- Advisory text: *"Importing unchecks variables not selected by the method. Review and re-check any you wish to include."*

**Confirmation table:** one row per candidate covariate.

| Column | Input type | Notes |
|---|---|---|
| Variable name | Static text | Sortable; filterable |
| Detected type | Static badge | |
| Include in model | Checkbox | All pre-checked by default |
| Stepwise suggestion | Static icon | ✓ selected, — not selected, — if not run |
| LASSO suggestion | Static icon | ✓ selected, — not selected, — if not run |
| Reference level | Single select dropdown | Factor variables only; R factor level order |

**"Confirm Covariate Selection"** button below table — writes `final_model_covariates` and reference levels to `analysis_spec`.

**Pending state:** if table modified after confirmation → step status amber "Pending — unconfirmed changes" → confirm button reappears → Step 5 Run Model disabled → preflight shows blocking error.

**Step complete when:** covariate selection confirmed with no pending changes.

---

#### Step 5 — Model Specification

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** model config and run button
- **Main panel (right):** preflight results, formula preview, R code preview, post-fit summary

**Sidebar (left):**
- Model selector — single dropdown:
  ```
  Linear regression
  Logistic regression
  Linear mixed model      (disabled if no subject ID)
  Logistic mixed model    (disabled if no subject ID)
  ```
- Mixed model options (visible only when mixed model selected):
  - Random intercept variable selector
  - Random slope variable selector (optional)
- Advanced options — collapsible accordion, mixed models only:
  - Optimizer selector: bobyqa (default), Nelder_Mead, nlminbwrap
- Preflight error inline message (red, persistent, shown only when errors exist or pending covariate changes)
- **"Run Model"** button — launches blocking modal; two disabled states per §5.2

**Main panel (right):**
- Preflight card (id target for pulse animation): errors red, warnings amber, passes green; always visible, auto-updating
- Formula preview: `tags$code` block, always visible, updates live
- R code preview: collapsible accordion, collapsed by default, full executable script, copyable
- Post-fit summary card: appears after successful run — model, N, primary estimate, CI, p-value, fitting warnings

**Pulse animation:** `shinyjs::addClass` / `shinyjs::removeClass` on preflight card; CSS `box-shadow` keyframe animation, 1 second, fires on disabled button click.

**Step complete when:** model run successfully at least once.

---

#### Step 6 — Diagnostics

**Layout:** `layout_sidebar(position = "right")`
- **Main panel (left):** Run Diagnostics button + diagnostic output tabs
- **Sidebar (right):** at-a-glance diagnostics summary — read-only

**Main panel (left):**

If no model run: placeholder card — *"Run a model in Step 5 to enable diagnostics."* Button disabled.

**Sidebar (left — config area within the main panel):**

Diagnostics are organized into two categories. Each category has Select all / Deselect all controls.

```
[Model Assumptions]
  [Select all]  [Deselect all]
  ☑ Sample accounting
  ☑ Residuals            (linear models only)
  ☑ Influence
  ☑ Collinearity (VIF)
  ☑ Separation           (logistic models only)
  ☑ Random effects       (mixed models only)
  ☑ Convergence          (mixed models only)

[Prediction Performance]
  Supplementary — not required for association studies
  [Select all]  [Deselect all]
  ☐ Discrimination (ROC / AUC)     (logistic models only)
  ☐ Calibration                    (logistic models only)
  ☐ Predicted probabilities        (logistic models only)
```

Model Assumptions: all checked by default.
Prediction Performance: all unchecked by default. All checkboxes always interactive — nothing greyed out.

**"Run Diagnostics"** button below categories — launches blocking modal.

**Main panel — `navset_card_tab` below button:**

Tabs are conditional on model type and on which categories are checked. Message area at top of each tab.

**All models — Sample Accounting tab:**
- Total rows in frozen dataset
- Rows excluded (missing data): count and percentage
- Rows analyzed: count and percentage
- Missingness breakdown table: variable, missing count, missing percentage
- Preflight warnings replayed as styled alert cards

**Linear regression — Model Assumptions tabs:**

*Residuals tab:*
- Residuals vs fitted plot; horizontal reference line at zero
- Q-Q plot of standardized residuals
- Scale-location plot
- Breusch-Pagan test statistic and p-value: value card

*Influence tab:*
- Cook's distance plot; threshold line at 4/n
- Leverage vs residuals plot
- Top influential observations table: `.edark_row_id`, Cook's distance, leverage, standardized residual; top 10 by Cook's distance

*Collinearity tab:*
- VIF table: variable, VIF, tolerance; rows colored amber (VIF 5–10), red (VIF > 10)
- Produced via `performance::check_collinearity()`

**Logistic regression — Model Assumptions tabs:**

*Influence tab:*
- Cook's distance plot
- Top influential observations table (same format as linear)

*Collinearity tab:*
- VIF table (same format as linear)

*Separation tab (shown only if separation detected):*
- Plain-language explanation card
- Variable(s) involved
- Suggested actions

**Logistic regression — Prediction Performance tabs (shown only if checked):**

*Discrimination tab:*
- ROC curve plot
- AUC with 95% CI displayed as value card

*Calibration tab:*
- Calibration plot: observed vs predicted probabilities in deciles

*Predicted Probabilities tab:*
- Density plot of predicted probabilities by outcome group
- Summary table: mean predicted probability by outcome group

**Linear mixed model — Model Assumptions tabs:**

*Residuals tab:*
- Residuals vs fitted plot (conditional residuals)
- Q-Q plot of residuals (conditional residuals)

*Random Effects tab:*
- Random effects Q-Q plot
- ICC value card
- Variance components table: group, variance, standard deviation
- Cluster size distribution histogram
- Cluster size summary: min, median, mean, max observations per cluster

*Collinearity tab:*
- VIF table (same format as above)

*Convergence tab:*
- Singular fit status: value card
- Convergence status: value card
- Optimizer used: value card
- If warnings present: plain-language explanation + suggested actions

**Logistic mixed model — Model Assumptions tabs:**

*Random Effects tab:*
- Same as linear mixed model random effects tab

*Collinearity tab:*
- VIF table (same format as above)

*Convergence tab:*
- Same as linear mixed model convergence tab

**Logistic mixed model — Prediction Performance tabs (shown only if checked):**

All prediction diagnostics use **marginal** predicted probabilities via `predict(model, type = "response", re.form = NA)`. Marginal predictions reflect fixed effects only — the clinically generalizable quantity.

*Discrimination tab:*
- ROC curve from marginal predictions
- Marginal AUC with 95% CI as value card

*Calibration tab:*
- Calibration plot from marginal predicted probabilities

*Predicted Probabilities tab:*
- Density plot of marginal predicted probabilities by outcome group

---

**Sidebar (right) — at-a-glance diagnostics summary:**

Read-only. Placeholder before run: *"Run diagnostics to see summary."*

After run — raw values only, no interpretive language. Sections conditional on what was computed:

```
── Run Info ──────────────────────────
Diagnostics run:    Nov 14 2024, 14:32
Model:              Logistic regression
N analyzed:         387 / 400

── Sample ────────────────────────────
Total rows:         400
Excluded:           13  (3.3%)
Analyzed:           387  (96.7%)

── Collinearity ──────────────────────
Max VIF:            2.300
Mean VIF:           1.800
Variables VIF > 5:  0
Variables VIF > 10: 0

── Influence ─────────────────────────
Max Cook's D:       0.040
Observations > 4/n: 2

── Separation ────────────────────────  [logistic only]
Detected:           No

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

── Prediction Performance ────────────  [if computed]
AUC:                0.810
AUC 95% CI:         0.760 – 0.860
Mean pred (outcome=0): 0.180
Mean pred (outcome=1): 0.540

── Warnings ──────────────────────────
⚠  Events per variable: 12.9
⚠  2 observations exceed Cook's D threshold
```

Warnings section: threshold-based flags only. Values section: raw numbers only. Prediction Performance section appears only if prediction diagnostics were checked and run.

**Step complete when:** diagnostics run at least once.

---

#### Step 7 — Results

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** output object selection and generate button
- **Main panel (right):** generated outputs — `navset_card_tab`

**Sidebar (left):**

```
[Section: Output Objects]
  ☑ Summary                      [always checked; not unchecable;
                                   auto-generated on model run]

  ☑ Results table
    └── ☑ Combined univariable + multivariable
            [sub-checkbox; checked by default]

  ☑ Fit statistics
  ☐ Forest plot
  ☐ Methods paragraph

[hr]

actionButton — "Generate Selected Outputs"
  launches blocking modal
  disabled if no model has been run
```

If no model run: placeholder card. Button disabled.

**Note on decimal places:** all numeric values displayed to maximum 3 decimal places. Values < 0.001 shown as *"< 0.001"*. Dynamic rounding is a planned future improvement (§12).

**Main panel (right) — `navset_card_tab`:**

**Summary tab — always present, auto-generated on model run:**

Primary result card showing: model type, outcome, exposure, N analyzed, primary estimate with CI and p-value, warning flags. Facts and values only — no interpretive language.

**Results Table tab:**

Two display modes controlled by combined table sub-checkbox.

*Mode 1 — Combined univariable + multivariable (default):* `gtsummary::tbl_merge()` output. Variables in univariable screen but excluded from multivariable model show unadjusted estimate with "—" in adjusted columns. Footnote: *"— Variable considered but not included in the final multivariable model."* Exposure variable row bolded. Factor variables show reference level in italics.

*Mode 2 — Separate tables:* Two sequential tables in same tab.

**Table footnotes — logistic regression:**
- *"OR = odds ratio; CI = confidence interval"*
- *"P-values from Wald z-tests"*
- *"Wald-based confidence intervals"*
- *"Complete-case analysis. N = [X] of [Y] observations included."*
- *"Reference levels: [variable] = [level], ..."*

**Table footnotes — logistic mixed model:**
- *"OR = odds ratio; CI = confidence interval"*
- *"P-values from Wald z-tests. Interpret with caution in small samples or with rare outcomes."*
- *"Wald-based confidence intervals"*
- *"Complete-case analysis. N = [X] observations from [Y] clusters included."*
- *"Reference levels: [variable] = [level], ..."*

**Table footnotes — linear regression:**
- *"β = unstandardized regression coefficient; CI = confidence interval"*
- *"P-values from t-tests"*
- *"Wald-based confidence intervals"*
- *"Complete-case analysis. N = [X] of [Y] observations included."*
- *"Reference levels: [variable] = [level], ..."*

**Table footnotes — linear mixed model:**
- *"β = unstandardized regression coefficient; CI = confidence interval"*
- *"P-values from Satterthwaite approximated degrees of freedom"*
- *"Wald-based confidence intervals"*
- *"Complete-case analysis. N = [X] observations from [Y] clusters included."*
- *"Reference levels: [variable] = [level], ..."*

**Mixed model tables — random effects summary appended below fixed effects.**

**Fit Statistics tab:** metric + value table per model type (see §7 for complete metric lists).

**Forest Plot tab:** coefficient forest plot; exposure row highlighted primary blue; null reference line; fixed effects only for mixed models.

**Methods tab:** selectable plain text inside `bslib::card`. Auto-generated from `analysis_spec`. Directly copyable. Also exported as text section in report and standalone `methods.txt`.

Example methods text for logistic regression:
```
Statistical Methods

Multivariable logistic regression was used to assess the association
between hypotension (exposure) and AKI (outcome), adjusting for age,
ASA class, and baseline creatinine. The odds ratio (OR) and 95%
confidence interval (CI) were reported as the measure of association.
P-values were derived from Wald z-tests. Confidence intervals are
Wald-based. Complete-case analysis was used; 387 of 400 observations
were included (13 excluded due to missing data). Statistical analyses
were performed in R (version X.X.X) using the following packages:
stats, gtsummary, ggplot2.
```

Example for logistic mixed model:
```
Statistical Methods

A generalized linear mixed-effects model with a logistic link function
was used to assess the association between hypotension (exposure) and
AKI (outcome), adjusting for age, ASA class, and baseline creatinine.
A random intercept for patient_id was included to account for
clustering. Fixed effects are reported as odds ratios (OR) with 95%
confidence intervals (CI). P-values were derived from Wald z-tests.
Confidence intervals are Wald-based. Interpret with caution in small
samples or with rare outcomes. Complete-case analysis was used; 1842
observations from 42 clusters were included. Statistical analyses were
performed in R (version X.X.X) using the following packages: lme4,
gtsummary, ggplot2.
```

**Step complete when:** outputs generated at least once.

---

#### Step 8 — Export

**Layout:** full-width — `layout_columns(col_widths = c(6, 6))`.

**Left column:** preset bundle selector (radio buttons: Custom Export, Analysis Package, Manuscript Items, Report Only, Everything); individual item checklists organized by output type with step-of-origin subheadings within each section; Tables and Figures sections have Select all / Deselect all controls; Reproducibility section with data export, R script, analysis spec, self-contained package; Report section with format selector; Full Result Object section; validation message area; Download button with reactive item count.

**Preset behavior:** Custom Export selected by default. Selecting a preset pre-checks relevant items. Modifying any item after selecting a preset reverts to Custom Export.

**Self-contained package behavior:** when checked, R script and Analysis spec checkboxes are unchecked and disabled (included inside package); Data export master checkbox is checked and greyed (cannot be unchecked); at least one data format must be selected (validated on download).

**Right column:** live zip folder preview updating reactively; selected items shown with ✓ in green, unselected muted with —; compact summary card showing item count and estimated size.

**Step complete when:** download initiated at least once.

### 5.4 Stale State Propagation

| Change made at | Marks stale |
|---|---|
| Step 1 — any role assignment change | Table 1, univariable screen, collinearity, stepwise, LASSO, covariate confirmation, model, diagnostics, results |
| Step 2 — Table 1 stratification or options change | Table 1 only |
| Step 3 — any investigation tool rerun | Covariate confirmation pending indicator updated |
| Step 4 — covariate confirmation change | Model, diagnostics, results |
| Step 5 — any model spec change | Model, diagnostics, results |
| Step 6 — diagnostics rerun | Nothing downstream |
| Step 7 — display config change | Results display only — no refitting |
| Dataset restart | Everything |

### 5.5 Default Spec Population on Skip

If the user navigates directly from Step 1 to Step 5 without visiting Steps 2, 3, or 4:

| Spec field | Default | Warning shown |
|---|---|---|
| `table1_variables` | Exposure + outcome + full candidate pool | None — Table 1 is optional |
| `univariable_test_pool` | Full candidate pool | None — univariable screen is optional |
| `final_model_covariates` | Full candidate pool | Step 5: *"No variable selection was performed — all candidate covariates will enter the model"* |
| `model_type` | Not set | Run Model button disabled |

---

## Section 6 — Screen-by-Screen UI Specification

### 6.1 Purpose of This Section

Section 5 defined the workflow and sequencing. This section specifies the precise UI components, input types, and rendering behavior for each screen. This is the section Claude Code reads to build each step. It should be unambiguous enough that no UI decisions need to be made during implementation.

### 6.2 Global UI Component Conventions

These apply to every screen in the analysis module without exception. Behavioral principles (buttons in config panel, no per-object downloads, message areas, placeholders) are defined in §5.2 and are not repeated here. This section covers component-level conventions only.

**Component library:** `bslib` for layout, `shinyWidgets` for enhanced inputs, `shiny` native for standard inputs. Consistent with existing app.

**Spacing and typography:** inherit from existing `bs_theme` — flatly bootswatch, Bootstrap 5, primary `#2c7be5`. No new theme variables introduced in the analysis module.

**Input widths:** all inputs in sidebar panels are full width (`width = "100%"`). No half-width inputs in sidebars.

**Section labels within sidebars:** use `tags$p(class = "mt-2 mb-1 fw-semibold", ...)` consistent with existing `prepare_confirm_ui` pattern.

**Horizontal rules between sidebar sections:** `hr(class = "my-2")` consistent with existing pattern.

**Icons:** `shiny::icon()` throughout. No raw Font Awesome strings.

**Notifications:** `shiny::showNotification()` with `type = "message"` for success, `type = "warning"` for warnings, `type = "error"` for errors. Duration 4 seconds for success, 8 seconds for errors.

**Blocking modal progress display:** every time-consuming operation launches a modal via `shiny::showModal()` with `easyClose = FALSE`. The modal contains a step list with per-step status icons and a progress bar. No `withProgress` toast for any operation in the analysis module.

**Message area:** every output panel begins with a `uiOutput` message card. Default state is empty. Uses `bslib::card` with appropriate border color class.

**Placeholder cards:** `bslib::card` with muted border and centered italic text. Never a blank space.

**Stale indicators:** amber warning icon on tab labels; banner: *"This output may be out of date. Rerun to refresh."*

**Numeric display:** all numeric values displayed to a maximum of 3 decimal places globally. Values < 0.001 displayed as *"< 0.001"*. Dynamic significant-figure-based rounding is a planned future improvement (see §12).

### 6.3 Step 1 — Setup

**Module file:** `R/module_analysis_setup.R`

**UI function:** `analysis_setup_ui(id)`

**Server function:** `analysis_setup_server(id, shared_state)`

**Layout:** `layout_sidebar(position = "right")`

**Pre-start state:** centered card with dataset summary and **"Start Analysis"** button (`class = "btn-primary"`).

**Post-start main panel — role assignment table:**

`DT::datatable` with custom column renderers.

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

Above table: `shinyWidgets::searchInput` for filtering.

Column header **"Clear"** buttons for radio columns — `actionButton` with `icon("xmark")`.

Reference levels: factor variables only, R factor order (not alphabetical), defaults to first level in R factor order.

**Sidebar (right):** study type badge (color-coded), role assignment summary, dataset snapshot (rows, columns, complete cases). All `renderUI`, updates reactively.

**Reactive behavior:** `analysis_spec$variable_roles` updated reactively — no confirm button. Downstream steps marked stale per §5.4.

**Step complete when:** outcome variable assigned.

### 6.4 Step 2 — Table 1

**Module file:** `R/module_analysis_table1.R`

Sidebar (left): stratification checkboxes, p-value toggle with tooltip, SMD toggle, generate button.

Main panel (right): `navset_card_tab` — Overall (always), By Exposure (conditional), By Outcome (conditional). Variables: exposure + outcome + all candidates, fixed order. Placeholders for ungenerated tabs.

### 6.5 Step 3 — Variable Investigation

**Module file:** `R/module_analysis_varinvestigation.R`

Full-width. Vertical `navset_pill` — three pills (Univariable Screen, Collinearity, Stepwise/LASSO). Each pill renders `layout_sidebar(position = "left")`.

**Univariable Screen:** run button only; always runs all candidates; `lm` or `glm` auto-selected by outcome type; non-mixed regardless of clustering.

**Collinearity:** auto-computed; heatmap, Cramér's V, flagged pairs tabs; no run button.

**Stepwise/LASSO:** `radioGroupButtons` toggle; state preserved when switching; advisory banner.

### 6.6 Step 4 — Covariate Confirmation

**Module file:** `R/module_analysis_covariate_confirm.R`

Full-width. Summary card, import buttons, confirmation table (all candidates pre-checked), confirm button. Pending state blocks Step 5.

### 6.7 Step 5 — Model Specification

**Module file:** `R/module_analysis_modelspec.R`

Sidebar (left): model dropdown, mixed model options, advanced options accordion, preflight inline message, run button.

Main panel (right): preflight card with pulse animation, formula preview, R code preview accordion, post-fit summary card.

### 6.8 Step 6 — Diagnostics

**Module file:** `R/module_analysis_diagnostics.R`

**Layout:** `layout_sidebar(position = "right")`
- **Main panel (left):** diagnostic category checkboxes, run button, diagnostic output tabs
- **Sidebar (right):** at-a-glance diagnostics summary — read-only

**Main panel diagnostic categories and run button:**

Two categories with select all / deselect all per category, followed by the run button. Model Assumptions all checked by default. Prediction Performance all unchecked by default with label *"Supplementary — not required for association studies."* Prediction Performance items only shown for logistic models.

Diagnostic tabs conditional on model type and checked categories. See §5.3 Step 6 for complete tab inventory per model type.

**Sidebar (right):** at-a-glance summary — raw values only, sections conditional on what was computed. Prediction Performance section appears only if those diagnostics were run.

### 6.9 Step 7 — Results

**Module file:** `R/module_analysis_results.R`

Sidebar (left): output checkboxes (Summary always checked, Results table with combined sub-checkbox, Fit statistics, Forest plot, Methods paragraph), generate button.

Main panel (right): `navset_card_tab` — Summary (auto-generated), Results Table, Fit Statistics, Forest Plot, Methods. See §5.3 Step 7 and §7 for complete specifications.

### 6.10 Step 8 — Export

**Module file:** `R/module_analysis_export.R`

Full-width two-column layout. Left: preset selector, item checklists by type with step-of-origin subheadings, reproducibility section with data/script/spec/package, report section, full result object, validation, download button. Right: live zip preview with reactive updates.

See §5.3 Step 8 for complete export checklist, preset bundle contents table, zip folder structure, validation rules, and blocking modal specification.
