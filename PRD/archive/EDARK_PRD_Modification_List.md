# EDARK Analysis Module PRD — Required Modifications
## Complete Change List for Final Consolidated Rewrite

---

## Global / New Sections

### New: Code Paradigms Section (PRD top-level, before Section 1)
- **Magrittr pipe exclusively:** use `%>%` in all app code and in the R code generator output. No base R pipe `|>`.
- **Reference to project CLAUDE.md:** the PRD should note that CLAUDE.md and UI_principles.md govern project-level coding and UI conventions.
- **Package DESCRIPTION Imports list:** the PRD must specify every package that needs to be added to the EDARK package's `DESCRIPTION` file under `Imports:`. This is distinct from what the generated R script loads — these are what the app itself needs to run. Belongs in the implementation section or as a standalone reference table.

### Global Mandate: Downstream Reset Behavior
- Changes that trigger `reset_analysis_pipeline()` with confirmation modal: Step 1 role changes, Step 4 re-confirmation, Step 5 model type change.
- Changes that do NOT trigger reset: Table 1 modifications, diagnostic category add/remove, variable investigation reruns, export selections.

---

## Section 3 — Data Contract

### §3.5 — `analysis_spec` object
- **Remove** `decimal_places` from `model_design` (removed from UI; all numeric display hardcoded at 3 decimal places max).
- **Add** `univariable_p_threshold = 0.2` to `variable_selection_specification`.

### §3.6 — `analysis_result` object
- **Add** `variable_investigation` list with three slots: `univariable`, `stepwise`, `lasso` (each NULL or a `variable_selection_result` object per §9.3).
- **Restructure** `result_plots$diagnostic_plots` to explicitly include: `scale_location` (linear only), `predicted_probs` (logistic only), `roc_curve`, `calibration_plot`.
- **Add** `generated_r_script` field — character string cached from Step 5 code generator.
- **Add** `methods_paragraph` field — character string cached from Step 7 methods generation.

### §3.8 — Zip folder structure
- **Remove entirely.** Superseded by §10.2 which defines the authoritative export folder structure.
- Replace with a one-line pointer: *"Export folder structure is defined in §10.2."*

---

## Section 4 — Analytic Scope

### §4.2 — P-value and Confidence Interval Methods
- **Logistic regression CIs:** change from "profile likelihood by default, Wald fallback" → "Wald-based via `confint.default()`". Profile likelihood deferred to v1.5 as advanced option.
- **Logistic mixed model p-values:** change from "Likelihood ratio tests via `anova()` for all fixed effects" → "Wald z-tests via `summary()`". Add note: "Interpret with caution in small samples or with rare outcomes. Preflight validation flags inadequate event counts." LRT deferred to v1.5 as advanced option.
- **Remove** the implementation note about LRT requiring k+1 model fits. No longer applies.
- **Add** note: "All confidence intervals throughout the module are Wald-based. Profile likelihood CIs and likelihood ratio test p-values are deferred to v1.5 as advanced options."

### §4.3 — Package Dependencies
- **Add:** `lmtest` (Breusch-Pagan test for linear regression heteroskedasticity).
- **Add:** `pROC` (ROC curves and AUC for logistic model prediction diagnostics).
- **Add:** `detectseparation` (separation detection for logistic regression).
- **Add:** `pacman` (used in generated R code for robust package loading; not a runtime dependency of the app itself — note this distinction).
- **Remove:** `ResourceSelection` (Hosmer-Lemeshow dropped).

### §4.6 — Computational Batching
- **Remove** the note about mixed models with LRT p-values being slow (no longer applies since LRT is deferred).

---

## Section 5 — Workflow and Sequencing

### §5.1 — Layout Overview
- **Step 6 Diagnostics:** change layout from `layout_sidebar(position = "left")` to `layout_sidebar(position = "right")`.
  - Main panel (left): diagnostic category checkboxes, run button, diagnostic output tabs.
  - Sidebar (right): at-a-glance diagnostics summary — read-only.

### §5.3 Step 5 — Model Specification
- **Replace** tabbed main panel with stacked accordion layout:
  - Model Summary accordion (expanded by default)
  - Preflight accordion (expanded by default) — includes verbose checkbox and Run Preflight button
  - Formula preview (plain `tags$code` line, not an accordion)
  - Model Results accordion (appears only after successful fit, expanded on appear)
  - R Code Preview accordion (collapsed by default)
- **Accordion state transitions** specified per §8.4:
  - On preflight run (including tab entry): Model Summary expanded, Preflight expanded, Model Results collapsed, R Code collapsed.
  - On successful model run: Model Summary expanded, Preflight expanded, Model Results expanded, R Code collapsed.
- **Remove** decimal places selector from sidebar (hardcoded at 3).

### §5.3 Step 6 — Diagnostics
- **Add** two-category config in main panel (above run button):
  - **Model Assumptions:** all checked by default. Includes: sample accounting, residuals (linear only), influence, collinearity/VIF, separation (logistic only), random effects (mixed only), convergence (mixed only).
  - **Prediction Performance:** all unchecked by default. Label: *"Supplementary — not required for association studies."* Includes: discrimination/ROC/AUC (logistic only), calibration (logistic only), predicted probabilities (logistic only).
- Each category has Select all / Deselect all controls.
- All checkboxes always interactive — nothing greyed out.
- **Remove** Hosmer-Lemeshow from all diagnostic inventories.
- **Add** separation detection to logistic model assumptions diagnostics.
- **Specify** that prediction diagnostics for logistic mixed models use **marginal** predicted probabilities via `predict(model, type = "response", re.form = NA)`.

### §5.3 Step 7 — Results
- **Update all table footnotes** for Wald consistency:
  - Logistic regression: "P-values from Wald z-tests" (unchanged).
  - Logistic mixed model: change from "P-values derived from likelihood ratio tests. Confidence intervals are Wald-based." → "P-values from Wald z-tests. Interpret with caution in small samples or with rare outcomes. Wald-based confidence intervals."
  - Linear mixed model: "P-values from Satterthwaite approximated degrees of freedom" (unchanged).
- **Update methods paragraph examples** to reflect Wald everywhere. Remove any mention of LRT in methods text examples.

### §5.3 Step 8 — Export
- **Update** folder structure references to match §10.2 (manuscript-oriented: `methods/`, `results/`, `diagnostics/`).
- **Update** preset bundle contents to reflect new structure.
- **Rename** `reproducibility/` → `methods/`.
- **Report** goes in root of export directory, not in a `report/` subfolder.
- **Self-contained analysis package** as a separate checkbox with description: *"Self-contained analysis package for EDARK import (1 file, contains data, may be large)."* Outputs as `.zip` in root.
- Individual methods items (R script, spec, data) always go in `methods/` when selected. No branching based on whether package is also selected. Redundancy is intentional.

---

## Section 6 — Screen-by-Screen UI Specification

### §6.7 Step 5 — Model Specification UI
- **Replace** tabbed main panel with stacked accordion layout per §8.4.
- **Remove** decimal places `numericInput` from sidebar.
- **Add** verbose checkbox and Run Preflight button inside the Preflight accordion content area.

### §6.8 Step 6 — Diagnostics UI
- **Restructure** main panel to include two diagnostic categories above the run button, each with Select all / Deselect all.
- **Remove** Hosmer-Lemeshow from logistic regression diagnostic tabs.
- **Add** `detectseparation` display to logistic regression model assumptions tabs (Separation tab: shown only if detected, plain-language explanation, variables involved, suggested actions).
- **At-a-glance sidebar:** sections are conditional on what was computed. Remove Hosmer-Lemeshow row. Add separation status row for logistic models. Prediction Performance section appears only if those diagnostics were run.

### §6.9 Step 7 — Results UI
- **Update** all table footnote text for Wald consistency (same changes as §5.3 Step 7).

### §6.10 Step 8 — Export UI
- **Update** checklist to reflect §10.2 folder structure.
- **Update** preset bundle contents table.
- **Self-contained package** as a distinct checkbox with description text.
- **Report** in root, not in subfolder.
- **Analysis package** exports do not suppress individual `methods/` items. Both can be selected simultaneously.

---

## Section 7 — Statistical Specification

### §7.9 — R Code Generation
- **Expand** from concept-level description to full generator specification. This is the authoritative location for code generator logic (moved from §10).
- **Add** `pacman::p_load()` with binary-only options and RSPM/CRAN repos at the top of generated scripts:
  ```r
  options(
    pkgType = "binary",
    repos = c(
      RSPM = "https://packagemanager.posit.co/cran/latest",
      CRAN = "https://cloud.r-project.org"
    )
  )
  ```
- **Use** `magrittr` `%>%` throughout generated code. Include `magrittr` in `pacman::p_load()`.
- **Broader scope for generated code:**
  - Table 1: only include code for stratifications that were actually generated.
  - Variable selection: include code for ALL three methods. Methods that were run use actual parameters. Methods not run are fully commented out with default parameters shown.
  - Model fitting: hardcode the final confirmed covariates in the formula. No dependency on variable selection output.
  - Diagnostics: include ALL diagnostics available for the model type, regardless of which were checked in the app.
  - Results: include all results extraction code.

---

## Section 8 — Preflight Validation Layer

### §8.4 — Step 5 Layout
- Already specified in Section 8 with the stacked accordion layout. **Reconcile** with §5.3 Step 5 and §6.7 Step 5 so all three locations describe the same layout consistently. §8.4 is the authoritative definition; §5.3 and §6.7 should reference it or match it exactly.

---

## Section 10 — Export and Output Specification

### §10.6 — R Code Generator
- **Remove** code generation logic from Section 10. Section 10 only retrieves the cached R script from `analysis_result` and writes it to file.
- **Point to** §7.9 as the authoritative specification for the code generator.

---

## Section 11 — Versioning and Deferral Log (previously Section 12)

- **Renumber** from Section 12 to Section 11.
- **Add** LRT p-values as v1.5 advanced option (already present in current draft).
- **Add** profile likelihood CIs as v1.5 advanced option (already present).
- **Add** prediction modeling infrastructure to v2 (already present).
- **Add** Hosmer-Lemeshow to permanently out of scope (already present).
- **Add** customizable report builder to v1.5 (already present).
- **Add** elastic net (alpha parameter for LASSO) to v1.5 deferred features.

---

## Section 12 — Implementation Architecture (new numbering)

- **Brief section** in the PRD pointing to the external Build Plan document: `EDARK_Analysis_Build_Plan.md`.
- Contains:
  - File structure overview (module files + service files)
  - Package DESCRIPTION Imports list
  - Reference to CLAUDE.md and UI_principles.md for coding conventions
  - Pointer to the Build Plan for phased implementation sequence
- The Build Plan itself is a separate document, not part of the PRD.
