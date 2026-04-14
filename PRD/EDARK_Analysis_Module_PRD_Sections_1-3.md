# EDARK Analysis Module — Product Requirements Document
## Sections 1–3 (Frozen — Revised)

> **REMINDER: BEFORE IMPLEMENTING THE ANALYSIS MODULE, REFACTOR THE EXISTING `withProgress` TOAST PATTERN IN `module_report.R` TO USE A BLOCKING MODAL WITH STEP-LIST PROGRESS DISPLAY. THE ANALYSIS MODULE MUST USE THIS SAME MODAL PROGRESS PATTERN FROM DAY ONE. DO NOT IMPLEMENT ANALYSIS MODULE PROGRESS USING `withProgress` TOAST.**

---

## Section 1 — Overview and Scope

### 1.1 Purpose

The Analysis module extends EDARK with a structured, guided workflow for fitting and reporting statistical models appropriate for clinical observational research. It takes the working dataset produced by the Prepare stage and guides the user from study framing through model specification, diagnostics, results, and export — producing outputs suitable for direct use in academic manuscripts.

### 1.2 Relationship to Existing App

The Analysis module is Tab 4 (`4 · Analyze`) in the existing `page_navbar` structure. It receives `shared_state$dataset_working` as its input. It does not modify the working dataset, does not write back to any Prepare or Explore state, and has no upstream dependencies beyond the frozen dataset snapshot it takes at entry. It is a consumer, not a participant, in the upstream reactive graph.

### 1.3 Target User

Three archetypes, in ascending statistical fluency:

**Archetype A — The Clinician.** Understands the clinical question deeply. Has limited statistical vocabulary. Needs the app to frame decisions in clinical language, prevent obvious errors silently, and surface non-obvious errors explicitly. Will follow guided steps if they feel logical. Will abandon the workflow if it feels like a stats course.

**Archetype B — The Clinician-Researcher.** Runs studies regularly. Knows what a confounder is, has heard of mixed models, has used SPSS or basic R. Wants sensible defaults with the ability to override. Reads model output tables fluently. Will notice if something looks wrong.

**Archetype C — The Biostatistician.** Knows exactly what they want. Uses the app for speed and reproducibility, not guidance. Needs full access to model options, raw result objects, and exportable R code that they can audit and extend. Will distrust the app if it hides things or makes silent decisions.

The UI must serve all three without patronizing C or losing A.

### 1.4 Study Type Framing — The Central Design Principle

Every downstream decision in the analysis workflow — Table 1 stratification, appropriate model family, variable selection framing, output labeling — flows from one early question: **what kind of study is this?**

Rather than asking users to answer this abstractly, the app infers study type from role assignments and surfaces it as a soft label that guides subsequent steps. Study type is derived as follows:

| Exposure assigned | Outcome assigned | Study type |
|---|---|---|
| Yes | Yes | Exposure-outcome association study |
| No | Yes | Risk factor / descriptive association study |
| Yes | No | Descriptive (exposure distribution) |
| No | No | Descriptive cohort |

If exposure is assigned but no outcome is assigned, a soft nudge is shown: *"You have assigned an exposure but no outcome — most analyses require an outcome variable. Continue for descriptive summaries only."*

Study type is displayed persistently as a labeled badge throughout the workflow. It drives soft nudges and hard constraints. The exposure variable is structurally enforced as a single-select — it is impossible to assign more than one variable as exposure. Help text reads: *"One primary exposure or treatment variable — additional variables of interest are covariates."*

Study type framing drives:
- **Exposure-outcome study:** Table 1 stratified by exposure; model selection centers on the exposure-outcome relationship; covariate selection framed as confounder identification
- **Risk factor / descriptive association study:** Table 1 stratified by outcome; model selection centers on variable associations with the outcome; covariate selection framed as candidate predictor screening
- **Purely descriptive:** Table 1 unstratified; no inferential modeling expected

### 1.5 Scope Boundary

The module is deliberately bounded. It is a structured analysis assistant for common clinical observational study designs, not a general statistical computing environment.

**In scope for v1:** descriptive summaries, unadjusted comparisons, linear regression, logistic regression, linear mixed models, logistic mixed models, variable selection helpers, manuscript-ready outputs, reproducible R code export.

**Planned for future versions:** propensity score matching, inverse probability treatment weighting, propensity score-adjusted regression, generalized estimating equations, multinomial logistic regression, ordinal logistic regression, Poisson and negative binomial regression, marginal effects and predicted value plots, analysis package import.

**Out of scope:** survival and time-to-event models, Bayesian models, machine learning classifiers, mediation and structural equation modeling, multiple imputation, automated model selection, arbitrary R code execution.

---

## Section 2 — User Stories

### 2.1 Archetype A — The Clinician

**Background:** Cardiac surgery fellow. Collected a retrospective dataset of 400 patients. Wants to know if intraoperative hypotension is associated with postoperative AKI. Has never run a regression outside of GraphPad Prism.

**Story:**

> I've cleaned my data in the Prepare tab. I go to Analyze. The app asks me to identify my outcome and my exposure. I pick AKI (binary) and hypotension (binary). The app tells me this looks like an exposure-outcome association study and shows me a Table 1 split by hypotension. It looks right. I move to variable selection. The app shows me a table of unadjusted associations between each candidate variable and AKI — odds ratios with confidence intervals for each one. Age, ASA class, and baseline creatinine have the strongest associations. I include them because they also make clinical sense to me. The app shows logistic regression as the appropriate model for a binary outcome — other options are visible but clearly secondary. I click Run. I get an odds ratio table that looks like something I've seen in a paper. I download the zip folder and send it to my supervisor.

**What the app must do for this user:**
- Never require statistical vocabulary to complete the workflow
- Make the right model family obvious without hiding alternatives
- Flag problems in plain language ("only 12 patients had the outcome — your model may be unreliable")
- Present unadjusted outcome-regressed associations clearly so the user can make their own covariate decisions
- Produce output that looks like a published paper, not an R console

### 2.2 Archetype B — The Clinician-Researcher

**Background:** Hepatology attending. Runs 3-4 studies per year. Comfortable with multivariable regression, knows what a confounder is, has collaborated with biostatisticians. Working on a longitudinal dataset of liver transplant recipients with repeated creatinine measurements.

**Story:**

> I've got a working dataset with one row per visit per patient. I go to Analyze. I assign creatinine as my continuous outcome, time-since-transplant as my exposure, and patient ID as my clustering variable. I also assign a broad candidate pool — age, donor type, rejection episodes, tacrolimus level, bilirubin, albumin, and a few others I want to consider. The app recognizes the repeated measures structure and nudges me toward a linear mixed model. I confirm. I move to variable selection. The app shows me univariable linear regression results for each candidate against creatinine. I also run the LASSO helper on the candidate pool — it corroborates that bilirubin and albumin are strong contributors. I make my final covariate list based on those results plus clinical judgment. I check the VIF table — everything looks fine. I run the model. I review the fixed effects table and the residual plots. I notice a convergence warning — the app explains what it means and suggests simplifying the random effects structure. I adjust and re-run. Clean results. I export the full zip with the report, figures, and R script and send the script to my statistician collaborator to verify.

**What the app must do for this user:**
- Recognize data structure and suggest appropriate model family without forcing it
- Make the two-stage variable workflow clear: broad candidate assignment first, then selection refinement using outcome-regressed univariable models
- Surface model warnings with enough context to act on them, not just flag them
- Produce an exportable R script that a statistician can read and audit

### 2.3 Archetype C — The Biostatistician

**Background:** Supports a clinical research group. Uses R daily. Being asked to use EDARK because the clinical team wants a reproducible, documented workflow. Skeptical of GUI tools that make silent decisions.

**Story:**

> A fellow on the team has done the data cleaning in Prepare. I take over at Analyze. I assign variable roles and override the suggested study type label — this is a risk factor screen, not a clean exposure-outcome study. I assign a broad candidate pool deliberately. I move to variable selection. The univariable screen shows me unadjusted linear regression results for each candidate against the outcome. I run backward stepwise with BIC rather than the default AIC. I review the suggested covariate list and override two inclusions based on clinical reasoning. I specify a logistic mixed model with a random intercept for site. I expand the advanced options panel and verify the optimizer setting. I review the generated R code before running — it matches exactly what I configured, no surprises. I run the model, check the Wald CIs, review the calibration plot. I download the full zip. I also download the RDS file with the fitted object for post-hoc contrasts in my own R session, and export the frozen analysis dataset as a Stata `.dta` file for a collaborator.

**What the app must do for this user:**
- Expose all configuration options, collapsed by default but always accessible
- Never make a silent decision — every default must be visible and overridable
- Generate R code that is clean, auditable, and matches the fitted model exactly
- Provide raw fitted object as RDS for downstream use outside the app
- Export the frozen analysis dataset in multiple formats: CSV, RDS, SPSS `.sav`, Stata `.dta`, Excel `.xlsx`
- Allow override of soft nudges without friction

---

## Section 3 — Data Contract

### 3.1 What Enters the Analysis Module

The analysis module receives two objects from the upstream app: `shared_state$dataset_working` — the fully prepared, filtered, and transformed dataset produced by the Prepare stage — and `shared_state$column_types`, the named vector of detected column types produced by `detect_column_types()`. The module uses `column_types` to pre-populate variable type information at role assignment without re-detecting from scratch.

The module reads from `shared_state` but never writes back to any Prepare or Explore fields. It only writes to its own three designated fields defined in Section 3.3.

### 3.2 Dataset Signature

When the analysis module freezes the working dataset, it computes and stores a **dataset signature** — a compact structural fingerprint used for cache invalidation, EDA config matching, and analysis package validation.

The signature captures:
- Column names and their order
- Column classes (numeric, factor, character, POSIXct, etc.)
- Factor levels per factor column, in order
- Row count

This is intentionally more than `str()` output but less than a full data hash. It detects: column additions and removals, type changes, factor level additions or removals caused by filtering, and meaningful row count shifts. It does not detect silent value edits within rows, which is an acceptable tradeoff.

**Signature validity rules when loading a saved config or analysis package:**
- Exact match → proceed silently
- Row count differs, all else matches → soft warning: *"Row count has changed since this analysis was configured. Results may differ."*
- Factor levels differ → hard warning: *"One or more factor variables have different levels than when this analysis was configured. Review role assignments before proceeding."*
- Column names, classes, or structure differ → blocking error: *"Dataset structure has changed. This analysis configuration is not compatible with the current working dataset."*

This signature also serves the EDA config save/load feature: a saved Prepare-stage configuration is valid only if the signature of the incoming dataset is compatible with the signature recorded when the config was saved.

### 3.3 Fields Added to `shared_state`

Three fields are added to `shared_state` at app launch, initialized as `NULL`. These are the only fields the analysis module writes to:

```r
# Analysis module fields — added to shared_state initialisation in edark.R
analysis_data    = NULL,  # frozen data.frame with .edark_row_id column
analysis_spec    = NULL,  # named list: full declarative analysis specification
analysis_result  = NULL   # named list: fitted objects, tables, plots, summaries
```

### 3.4 Dataset Freeze Behavior

When the user clicks **"Start Analysis"**, the module copies `shared_state$dataset_working` into `shared_state$analysis_data`, appends a row-level internal identifier column (`.edark_row_id`), and computes the dataset signature. This frozen copy is what all downstream analysis operates on exclusively.

The frozen dataset does not update if the user returns to Prepare and modifies the working dataset. A persistent banner in the Analysis module detects signature mismatch and displays: *"Your working dataset has changed since this analysis was started. Restart analysis to use the updated data."* with a **Restart Analysis** button.

Restarting clears `analysis_spec`, `analysis_result`, and all analysis UI state. It does not affect anything in Prepare or Explore.

### 3.5 The `analysis_spec` Object

The spec is a nested named list built incrementally as the user progresses through the workflow steps. It is the single source of truth for model fitting, code generation, caching, and export. It is fully serializable to JSON for export and for the analysis package feature.

```r
analysis_spec <- list(

  specification_metadata = list(
    study_type         = "exposure_outcome",
                         # "exposure_outcome" | "risk_factor" |
                         # "descriptive_exposure" | "descriptive"
    created_at         = Sys.time(),
    dataset_signature  = list()   # full signature object from §3.2
  ),

  variable_roles = list(
    outcome_variable        = NULL,  # single character; required for modeling
    exposure_variable       = NULL,  # single character or NULL
    candidate_covariates    = NULL,  # character vector; broad initial pool
    table1_variables        = NULL,  # character vector; exposure + outcome +
                                     # all candidates in role assignment order
    univariable_test_pool   = NULL,  # character vector; all candidates;
                                     # not user-adjustable
    final_model_covariates  = NULL,  # character vector; confirmed in Step 4
    subject_id_variable     = NULL,  # for mixed models; single character or NULL
    cluster_variable        = NULL,  # if different from subject ID; or NULL
    time_variable           = NULL,  # for longitudinal models; or NULL
    reference_levels        = list() # named list: variable_name -> reference level
                                     # e.g. list(asa_class = "I", sex = "Male")
                                     # set at candidate assignment; R factor
                                     # level order; overridable in Step 4
  ),

  table1_specification = list(
    stratify_by_exposure     = TRUE,  # checkbox; default per study type
    stratify_by_outcome      = FALSE, # checkbox; default per study type
    include_pvalues_exposure = FALSE, # off by default for exposure stratification
    include_pvalues_outcome  = TRUE,  # on by default for outcome stratification
    include_standardized_mean_difference = TRUE  # on by default
  ),

  variable_selection_specification = list(
    method                 = "univariable",
                             # "univariable" | "stepwise" | "lasso" | "manual"
    stepwise_direction     = "backward",   # "backward" | "forward"
    stepwise_criterion     = "BIC",        # "AIC" | "BIC"
    lasso_lambda           = "lambda.1se", # "lambda.min" | "lambda.1se"
    selected_variables     = NULL          # final confirmed list; always
                                           # analyst-confirmed before proceeding
  ),

  model_design = list(
    model_type                 = NULL,
                                 # "linear_regression" | "logistic_regression" |
                                 # "linear_mixed" | "logistic_mixed"
    random_intercept_variable  = NULL,  # character or NULL; mixed models only
    random_slope_variable      = NULL,  # character or NULL; mixed models only
    confidence_interval_level  = 0.95,  # hardcoded; not exposed in UI
    optimizer                  = "bobyqa",  # mixed models only
    linked_model_specification = NULL   # reserved for PS two-stage spec (v1.5)
  ),

  analysis_options = list(
    missing_data_handling  = "complete_case",  # complete case only in v1
    interaction_terms      = list()            # stubbed; unused in v1
  )
)
```

### 3.6 The `analysis_result` Object

Populated after **Run Model** completes. The UI reads exclusively from this object — it never inspects the raw fitted model directly.

```r
analysis_result <- list(

  specification_snapshot = analysis_spec,
  # Snapshot of the spec at time of fitting. Stored so the result is
  # fully self-describing and the exported RDS is auditable without
  # needing the live app state.

  run_status = list(
    status       = "success",   # "success" | "warning" | "error"
    fitted_at    = Sys.time(),
    run_messages = tibble::tibble(
      level   = character(),   # "error" | "warning" | "note"
      stage   = character(),   # "preflight" | "fitting" | "diagnostics"
      message = character()
    )
  ),

  fitted_models = list(
    primary_model      = NULL,  # raw R model object: lm, glm, lmerMod, glmerMod
    univariable_models = list() # named list: one lm or glm per candidate variable
                                # names correspond to variable names
  ),

  result_tables = list(
    table1_overall      = NULL,  # gt/flextable; always produced
    table1_by_exposure  = NULL,  # gt/flextable; NULL if exposure not assigned
                                 # or stratification not selected
    table1_by_outcome   = NULL,  # gt/flextable; NULL if outcome not assigned
                                 # or stratification not selected
    univariable_screen  = NULL,  # tibble: variable, estimate, CI, p-value
    main_results        = NULL,  # publication-style coefficient/OR table
    diagnostic_summary  = NULL   # VIF, fit statistics, assumption checks
  ),

  result_plots = list(
    coefficient_plot    = NULL,
    diagnostic_plots    = list(
      residuals_vs_fitted = NULL,
      qq_plot             = NULL,
      scale_location      = NULL,    # linear regression only
      influence_plot      = NULL,
      random_effects_qq   = NULL,    # mixed models only
      cluster_size_plot   = NULL,    # mixed models only
      roc_curve           = NULL,    # logistic models only (prediction perf)
      calibration_plot    = NULL,    # logistic models only (prediction perf)
      predicted_probs     = NULL     # logistic models only (prediction perf)
    ),
    collinearity_plots  = list(
      correlation_heatmap = NULL,
      cramers_v_matrix    = NULL,
      flagged_pairs_table = NULL
    ),
    lasso_plots = list(
      coefficient_path    = NULL,
      cross_validation    = NULL
    ),
    balance_plots         = NULL     # reserved for PS methods (v1.5)
  ),

  inference_summary = list(
    coefficients       = NULL,  # tibble: term, estimate, std_error, ci_lower,
                                # ci_upper, p_value, or_estimate for logistic
    fit_statistics     = NULL,  # tibble: metric, value
    predicted_values   = NULL,  # tibble: .edark_row_id, fitted_value, residual
    influence_measures = NULL   # tibble: .edark_row_id, cooks_distance, leverage
  ),

  linked_model_result  = NULL   # reserved for PS two-stage result (v1.5)
)
```

### 3.7 Table 1 Behavior by Study Type

| Study type | Default stratification | Default p-values |
|---|---|---|
| Exposure-outcome | By exposure | Off |
| Risk factor / descriptive association | By outcome | On |
| Descriptive exposure | By exposure | Off |
| Descriptive cohort | None (overall only) | Off |

When both exposure and outcome are assigned, both Table 1 versions are produced and presented as sub-tabs alongside the overall tab. Both are available for independent export.

P-value tooltip: *"These p-values describe distributional differences between groups. They are not used for variable selection. For outcome-regressed associations, see the Variable Selection step."*

### 3.8 What the Module Produces for Export

All export items are individually selectable. Four preset bundles plus custom export are available as quick-select options:

| Bundle | Contents |
|---|---|
| Custom Export | Nothing pre-selected; user builds manually |
| Analysis Package | Frozen dataset (RDS) + `analysis_spec` JSON + R script + self-contained package |
| Manuscript Items | Table 1 variants + results tables + key figures |
| Report Only | Analysis report (Word or HTML) |
| Everything | All items |

**Analysis package** (v1 export only; import functionality in v1.5): a self-contained zip containing the frozen dataset in RDS format, the full `analysis_spec` as JSON, the dataset signature, R script, and a manifest file. The dataset is included in full — data sensitivity is the user's responsibility.

**Zip folder structure:**

```
analysis_[YYYY-MM-DD_HHMMSS]/
├── tables/
│   ├── table1/
│   │   ├── table1_overall.docx
│   │   ├── table1_by_exposure.docx
│   │   └── table1_by_outcome.docx
│   ├── variable_investigation/
│   │   ├── univariable_screen.docx
│   │   └── stepwise_selection_log.docx
│   ├── results/
│   │   ├── multivariable_results.docx
│   │   ├── univariable_results.docx
│   │   ├── fit_statistics.docx
│   │   └── methods.txt
│   └── diagnostics/
│       ├── diagnostic_summary.docx
│       ├── vif_table.docx
│       └── sample_accounting.docx
├── figures/
│   ├── variable_investigation/
│   │   ├── collinearity_heatmap.png
│   │   ├── cramers_v_matrix.png
│   │   ├── lasso_coefficient_path.png
│   │   └── lasso_cross_validation.png
│   ├── diagnostics/
│   │   ├── residuals_vs_fitted.png
│   │   ├── qq_plot.png
│   │   ├── scale_location.png
│   │   ├── influence_plot.png
│   │   ├── random_effects_qq.png
│   │   ├── cluster_size_distribution.png
│   │   ├── roc_curve.png
│   │   ├── calibration_plot.png
│   │   └── predicted_probabilities.png
│   └── results/
│       └── forest_plot.png
├── report/
│   └── analysis_report.docx
├── reproducibility/
│   ├── data/
│   │   ├── analysis_dataset.rds
│   │   ├── analysis_dataset.csv
│   │   ├── analysis_dataset.sav
│   │   ├── analysis_dataset.dta
│   │   └── analysis_dataset.xlsx
│   ├── analysis_script.R
│   ├── analysis_specification.json
│   └── package/
│       ├── analysis_dataset.rds
│       ├── analysis_specification.json
│       ├── analysis_script.R
│       └── manifest.json
└── objects/
    └── analysis_result.rds
```
