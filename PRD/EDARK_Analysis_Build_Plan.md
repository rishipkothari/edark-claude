# EDARK Analysis Module — Phased Build Plan
## Implementation Sequence for Claude Code

**Reference document:** `EDARK_Analysis_Module_PRD.md` (the PRD). All section references (§) refer to the PRD.

**Project context files:** `CLAUDE.md`, `UI_principles.md` in project root.

**Critical rule for all phases:** use `magrittr` `%>%` exclusively. No base R pipe `|>`.

---

## Phase 0 — Infrastructure and Scaffold

### What to build
1. Add all packages from the PRD Global Mandates table to the DESCRIPTION file under `Imports:`
2. Create all file stubs listed in §12.1 — empty module shells (`ui` + `server` functions that return placeholder UI) and empty service files with roxygen headers
3. Create `module_analysis_main.R` — the orchestrator:
   - `analysis_main_ui(id)`: returns `bslib::navset_pill` with 8 `nav_panel` stubs, each rendering a placeholder card with the step name
   - `analysis_main_server(id, shared_state)`: initializes `shared_state$analysis_data`, `shared_state$analysis_spec`, `shared_state$analysis_result` as NULL; calls each step module's server function
4. Wire `module_analysis_main` into `edark.R` as Tab 4 ("Analyze") in the `page_navbar`
5. Create `analysis_utils.R` with three functions:
   - `build_analysis_formula(spec)` — assembles formula string from `analysis_spec$variable_roles`
   - `apply_reference_levels(data, reference_levels)` — applies `relevel()` per spec
   - `compute_complete_cases(data, variables)` — returns filtered data + exclusion count
6. Create `service_analysis_pipeline.R` with:
   - `reset_analysis_pipeline(shared_state, from_step)` — clears downstream fields per §8.6
7. Create `service_analysis_validation.R` with:
   - `validate_analysis(spec, data, tier = "full", verbose = FALSE)` — implements all checks from §8.2, both tiers

### What NOT to touch
- Any existing module files (module_prepare_*, module_explore_*, module_report.R)
- Any existing service files
- The existing `shared_state` fields — only ADD the three new analysis fields

### Acceptance criteria
- `devtools::check()` passes with 0 errors, 0 warnings
- App launches, Tab 4 appears with 8 labeled placeholder pills
- `shared_state$analysis_data`, `analysis_spec`, `analysis_result` are initialized as NULL
- `build_analysis_formula()` produces correct formula strings for all model types (test with mock spec)
- `validate_analysis()` correctly returns errors, warnings, notes for each check (test with mock data)
- `reset_analysis_pipeline()` correctly nulls downstream fields (test with mock shared_state)

### PRD references
- §3.3 (shared_state fields), §3.5 (analysis_spec structure), §3.6 (analysis_result structure)
- §5.1 (layout overview), §12.1 (file structure)
- §7.1 (formula assembly, reference levels, complete cases)
- §8.1–8.2 (validator architecture and checks)
- §8.6 (reset_analysis_pipeline)
- Global Mandates (DESCRIPTION Imports)

---

## Phase 1 — Step 1: Setup

### What to build
- `module_analysis_setup.R` — full implementation per §5.3 Step 1 and §6.3
- "Start Analysis" button → dataset freeze → `.edark_row_id` → signature computation
- Role assignment table (DT::datatable with custom renderers)
- Column header Clear buttons for radio columns
- Mutual exclusivity enforcement
- Sidebar role summary with study type badge
- Reactive spec population (no confirm button — live updates)
- Integration with `reset_analysis_pipeline()` — role changes with downstream results trigger confirmation modal

### What NOT to touch
- Steps 2–8 module files (leave as placeholders)
- Service files other than `analysis_utils.R` and `service_analysis_pipeline.R`

### Acceptance criteria
- "Start Analysis" freezes dataset correctly with `.edark_row_id`
- All role columns work: outcome, exposure, candidate, subject ID, cluster, time
- Clear buttons deselect radio columns
- Mutual exclusivity: assigning outcome unchecks candidate, etc.
- Reference level dropdowns populate with R factor levels in correct order
- Sidebar updates reactively showing roles and study type
- Study type badge derives correctly from all four combinations (§1.4)
- `analysis_spec$variable_roles` populates correctly
- Navigating to Step 2+ shows placeholder pills

### PRD references
- §1.4 (study type), §3.4 (freeze behavior), §3.5 (spec structure)
- §5.3 Step 1, §6.3

---

## Phase 2 — Step 2: Table 1

### What to build
- `module_analysis_table1.R` — full implementation per §5.3 Step 2 and §6.4
- `service_analysis_tables.R` — Table 1 generation via `gtsummary::tbl_summary()`
- Stratification checkboxes (By Exposure, By Outcome) with defaults per §3.7
- P-value toggle, SMD toggle
- Overall + conditional tabs in `navset_card_tab`
- Blocking modal progress on generate
- Results cached in `analysis_result$result_tables$table1_*`

### What NOT to touch
- Steps 3–8 module files
- Any service file other than `service_analysis_tables.R`

### Acceptance criteria
- Table 1 generates for all stratification combinations
- Overall tab always present
- By Exposure / By Outcome tabs appear/disappear based on checkboxes and role assignments
- P-value toggle works; SMD toggle works
- Table renders as `gtsummary` object in main panel
- Blocking modal shows during generation
- Cached correctly in `analysis_result`

### PRD references
- §3.7 (Table 1 behavior by study type), §5.3 Step 2, §6.4

---

## Phase 3 — Step 3: Variable Investigation

### What to build
- `module_analysis_varinvestigation.R` — full implementation per §5.3 Step 3 and §6.5
- `service_analysis_variable_selection.R` — all three methods per §7.6–7.8 and §9.4
- Vertical `navset_pill` with three pills
- Univariable Screen: p-threshold input + run button + results table + Tier 1 banner
- Collinearity: auto-computed heatmap + Cramér's V + flagged pairs
- Stepwise/LASSO: toggle + configs + run buttons + outputs
- Results stored in `analysis_result$variable_investigation`

### What NOT to touch
- Steps 4–8 module files
- Service files other than `service_analysis_variable_selection.R`

### Acceptance criteria
- Univariable screen runs lm for continuous outcome, glm for binary
- Results table: variable, estimate, CI, p-value, sorted by p-value
- P-value threshold filters suggested list correctly
- Collinearity heatmap renders on pill entry without button click
- Flagged pairs correctly identified at > 0.7 threshold
- Stepwise runs with backward/forward and BIC/AIC
- LASSO runs with lambda.1se/lambda.min; handles factor variables correctly
- Toggle preserves state between Stepwise and LASSO
- All results stored in `analysis_result$variable_investigation`
- Tier 1 validation banner shows errors when applicable
- Blocking modals for all run buttons

### PRD references
- §5.3 Step 3, §6.5, §7.6–7.8, §9.1–9.6, §8.5

---

## Phase 4 — Step 4: Covariate Confirmation

### What to build
- `module_analysis_covariate_confirm.R` — full implementation per §5.3 Step 4 and §6.6
- Summary card at top
- Confirmation table with: Variable, Type, Include checkbox, Univariable/Stepwise/LASSO suggestion columns, Reference level
- Import buttons in column headers with parameter tooltips
- Cell highlighting (green/pink/grey) per §9.7
- Confirm button writing to `analysis_spec$variable_roles$final_model_covariates`
- Pending state: modifications after confirmation → amber → blocks Step 5

### What NOT to touch
- Steps 5–8 module files
- Service files

### Acceptance criteria
- All candidates pre-checked by default
- Suggestion columns correctly show ✓/— based on method results
- Import buttons disabled if method not run; enabled if run
- Import unchecks variables not selected; confirmation modal fires first
- Cell highlighting: green for suggested, pink for not suggested, grey for not run
- Column header tooltips show correct parameters
- Confirm button writes `final_model_covariates` and `reference_levels` to spec
- Pending state after modification: amber status, confirm reappears
- Step 5 Run Model disabled when pending

### PRD references
- §5.3 Step 4, §6.6, §9.7–9.8

---

## Phase 5 — Step 5: Model Specification + Preflight + Model Fitting

### What to build
- `module_analysis_modelspec.R` — full implementation per §5.3 Step 5, §6.7, §8.4
- `service_analysis_models.R` — all four model fitting engines per §7.2–7.5
- `service_analysis_codegen.R` — R code generator per §7.9
- Sidebar: model dropdown, mixed model options, advanced accordion, run button
- Main panel: stacked accordion layout per §8.4 (Model Summary, Preflight, Formula, Model Results, R Code Preview)
- Preflight integration: Tier 2 validation on tab entry + model type change + Run Preflight button + verbose mode
- Accordion state transitions per §8.4
- Warning modal on Run Model with warnings
- Pulse animation on disabled button click
- R code preview live-updating from spec
- Blocking modal for model fitting

### What NOT to touch
- Steps 6–8 module files
- Service files other than `service_analysis_models.R` and `service_analysis_codegen.R`

### Acceptance criteria
- All four model types fit correctly: lm, glm, lmerTest::lmer, glmer
- Model dropdown disables unavailable types with inline reasons
- Mixed model options appear/hide based on selection
- Preflight runs on tab entry and model type change
- Verbose mode shows all checks including passes
- Run Preflight button triggers full check display
- Preflight errors disable Run Model + show inline message
- Pulse animation fires on disabled button click
- Warning modal shows on Run Model with warnings; Proceed/Cancel work
- Model Results accordion appears on successful fit with primary estimate
- R code preview shows correct script for each model type
- Accordion state transitions: preflight run → Summary+Preflight expanded; fit → +Results expanded
- Generated R code uses `pacman::p_load()`, `%>%`, RSPM repos
- Generated script matches fitted model exactly

### PRD references
- §5.3 Step 5, §6.7, §7.1–7.5, §7.9, §8.1–8.4

---

## Phase 6 — Step 6: Diagnostics

### What to build
- `module_analysis_diagnostics.R` — full implementation per §5.3 Step 6 and §6.8
- `service_analysis_diagnostics.R` — all diagnostic computations per §7.2–7.5
- `service_analysis_plots.R` — all diagnostic plot generation
- Two-category config (Model Assumptions / Prediction Performance)
- Run button + blocking modal
- `navset_card_tab` output tabs conditional on model type and selections
- At-a-glance sidebar summary with conditional sections

### What NOT to touch
- Steps 7–8 module files
- `service_analysis_models.R` (already complete)

### Acceptance criteria
- Model Assumptions all checked by default; Prediction Performance all unchecked
- Prediction Performance only shown for logistic models
- Select all / Deselect all work per category
- All diagnostics per model type compute and render correctly:
  - Linear: residuals, Q-Q, scale-location, Breusch-Pagan, Cook's D, leverage, VIF
  - Logistic: Cook's D, VIF, separation; (if checked) ROC/AUC, calibration, predicted probs
  - Linear mixed: residuals (conditional), Q-Q, random effects Q-Q, ICC, cluster size, VIF, convergence
  - Logistic mixed: random effects Q-Q, ICC, cluster size, VIF, convergence; (if checked) marginal ROC/AUC, marginal calibration, marginal predicted probs
- Sidebar summary populates with raw values, conditional sections
- Prediction Performance section in sidebar only if computed

### PRD references
- §5.3 Step 6, §6.8, §7.2–7.5 (diagnostics sections)

---

## Phase 7 — Step 7: Results

### What to build
- `module_analysis_results.R` — full implementation per §5.3 Step 7 and §6.9
- Extend `service_analysis_tables.R` — results tables, combined table via `tbl_merge()`, methods paragraph generation
- Extend `service_analysis_plots.R` — forest plot
- Sidebar: output checkboxes, generate button
- Summary tab (auto-generated on model run)
- Results Table tab (combined univariable + multivariable default)
- Fit Statistics tab
- Forest Plot tab
- Methods tab (selectable plain text)
- Methods paragraph cached in `analysis_result$methods_paragraph`

### What NOT to touch
- Step 8 module file
- `service_analysis_models.R`, `service_analysis_diagnostics.R`

### Acceptance criteria
- Summary tab appears immediately after model run without clicking generate
- Results table shows combined format with correct footnotes per model type
- Variables excluded from multivariable show "—" in adjusted columns
- Exposure row bolded, factor reference levels in italics
- Fit statistics table correct per model type
- Forest plot renders with exposure highlighted, null reference line
- Methods paragraph text is accurate for each model type
- Methods text uses correct p-value method and CI method language
- All outputs cached in `analysis_result`

### PRD references
- §5.3 Step 7, §6.9, §7.2–7.5 (fit statistics), §7.6 (combined table)

---

## Phase 8 — Step 8: Export

### What to build
- `module_analysis_export.R` — full implementation per §5.3 Step 8 and §6.10
- `service_analysis_export.R` — complete export assembly pipeline per §10.3–10.12
- Preset selector + item checklists with step-of-origin subheadings
- Self-contained analysis package checkbox
- Report generation via `officer` (Word) and `rmarkdown` (HTML) per §10.7
- Live zip preview
- Download button with validation
- Blocking modal with per-step progress

### What NOT to touch
- All other module and service files (complete at this point)

### Acceptance criteria
- Each preset pre-checks correct items
- Custom Export reverts on manual change after preset
- Self-contained package: disables standalone R script/spec checkboxes, forces data export
- All table files open in Word: table1_overall.docx, multivariable_results.docx, etc.
- All figure files render: forest_plot.png, residuals_vs_fitted.png, roc_curve.png, etc.
- All data formats: RDS loads in R, CSV parses, .sav opens in SPSS, .dta opens in Stata, .xlsx opens in Excel
- R script is executable and reproduces analysis
- Analysis spec JSON is valid and readable
- Analysis spec RDS loads correctly
- Report contains correct sections, embedded tables and figures
- Analysis package zip contains all required files with valid manifest.json
- Zip preview updates reactively
- Blocking modal shows per-step progress
- Export folder structure matches §10.2 exactly

### PRD references
- §5.3 Step 8, §6.10, §10.1–10.12

---

## Phase 9 — Integration, Polish, and Testing

### What to build
1. Wire `reset_analysis_pipeline()` with confirmation modals into Steps 1, 4, and 5
2. Implement stale state propagation per §5.4 — step status indicators update correctly
3. Step status indicators in pill labels (not started / in progress / complete / stale)
4. Consistent blocking modal pattern across all run buttons
5. Edge case handling: empty datasets, single variable, single cluster, zero events, all missing
6. Refactor existing `withProgress` toast in `module_report.R` to blocking modal (the global mandate)

### Test datasets

**Dataset 1 — Full-featured clustered dataset** (for testing all model types):
- ~500 observations across ~40 clusters (subject IDs)
- ~8–15 observations per cluster
- Binary outcome (event rate ~15%)
- Continuous outcome (e.g. creatinine)
- Binary exposure
- Mix of numeric covariates (age, BMI, lab values) and factor covariates (ASA class, sex, site)
- Reference levels intentionally non-alphabetical for at least one factor
- ~5% missingness scattered across variables
- At least one factor with a rare level (< 5 observations)
- At least one pair of covariates with correlation > 0.7

**Dataset 2 — Sparse clustering dataset** (for testing mixed model warnings):
- Same structure but most IDs have only 1–2 observations
- < 10 clusters
- Should trigger `PF_FEW_CLUSTERS` warning and near-zero ICC post-fit

Both datasets should be generated as R scripts in `inst/test_data/` and documented.

### Acceptance criteria
- Full end-to-end workflow: Setup → Table 1 → Variable Investigation → Covariate Confirmation → Model Specification → Diagnostics → Results → Export produces correct zip
- All four model types complete the full pipeline
- Role changes in Step 1 trigger reset modal and clear downstream correctly
- Step 4 re-confirmation clears model/diagnostics/results
- Step status indicators update correctly through the workflow
- Stale indicators appear when upstream changes invalidate downstream results
- Dataset 2 triggers appropriate warnings throughout the pipeline
- All blocking modals display correctly and prevent interaction during processing
- `module_report.R` progress bar refactored to blocking modal
- `devtools::check()` passes with 0 errors, 0 warnings

### PRD references
- §5.4 (stale propagation), §8.6 (reset pipeline)
- Global Mandates (withProgress refactor reminder)
- All sections — this is the integration phase
