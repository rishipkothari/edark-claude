# EDARK Analysis Module — Product Requirements Document
## Sections 1–5 (Frozen)

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
    decimal_places             = 2,
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
      influence_plot      = NULL,
      roc_curve           = NULL,      # logistic models only
      calibration_plot    = NULL,      # logistic models only
      random_effects_qq   = NULL,      # mixed models only
      cluster_size_plot   = NULL       # mixed models only
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
    balance_plots         = NULL       # reserved for PS methods (v1.5)
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

All export items are individually selectable. Four preset bundles are available as quick-select options:

| Bundle | Contents |
|---|---|
| Analysis package | Frozen dataset (all formats) + `analysis_spec` JSON + R script |
| Manuscript items | Publication tables (DOCX) + figures (PNG, SVG) |
| Full report | Word or HTML narrative report |
| Everything | All items |

**Analysis package** (v1 export only; import functionality in v1.5): a self-contained zip containing the frozen dataset in RDS format, the full `analysis_spec` as JSON, the dataset signature, and a manifest file. The dataset is included in full — data sensitivity is the user's responsibility.

**Zip folder structure:**

```
analysis_[YYYY-MM-DD_HHMMSS]/
├── report/
│   ├── analysis_report.docx
│   └── analysis_report.html
├── tables/
│   ├── table1_overall.docx
│   ├── table1_by_exposure.docx
│   ├── table1_by_outcome.docx
│   ├── univariable_results.docx
│   ├── main_results.docx
│   └── diagnostic_summary.docx
├── figures/
│   ├── coefficient_plot.png
│   ├── coefficient_plot.svg
│   └── [other figures]
├── diagnostics/
│   ├── residuals_vs_fitted.png
│   ├── qq_plot.png
│   ├── influence_plot.png
│   ├── roc_curve.png
│   └── calibration_plot.png
├── data/
│   ├── analysis_dataset.csv
│   ├── analysis_dataset.rds
│   ├── analysis_dataset.sav
│   ├── analysis_dataset.dta
│   └── analysis_dataset.xlsx
└── package/
    ├── analysis_spec.json
    ├── analysis_dataset.rds
    ├── dataset_signature.json
    ├── analysis_script.R
    └── manifest.json
```

---

## Section 4 — Analytic Scope

> **REMINDER: BEFORE IMPLEMENTING THE ANALYSIS MODULE, REFACTOR THE EXISTING `withProgress` TOAST PATTERN IN `module_report.R` TO USE A BLOCKING MODAL WITH STEP-LIST PROGRESS DISPLAY. THE ANALYSIS MODULE MUST USE THIS SAME MODAL PROGRESS PATTERN FROM DAY ONE. DO NOT IMPLEMENT ANALYSIS MODULE PROGRESS USING `withProgress` TOAST.**

### 4.1 Model and Method Inventory

All analytical methods available in v1. Linear regression and logistic regression serve dual roles — both as the univariable outcome regression screen during variable selection and as the final multivariable model.

| Method | Purpose | Outcome type | Data structure | Clustered | Primary package | P-value method |
|---|---|---|---|---|---|---|
| Descriptive summary / Table 1 | Population description; baseline characteristics by group | Any | Any | Any | `gtsummary` | Optional group comparison tests via `stats`; see §3.7 |
| Linear regression | Univariable outcome screen; multivariable adjusted model | Continuous | One row per subject | No | `stats::lm` | Native t-tests via `summary()` |
| Logistic regression | Univariable outcome screen; multivariable adjusted model | Binary (2-level factor) | One row per subject | No | `stats::glm` | Wald z-tests via `summary()`; acceptable for adequate sample sizes |
| Linear mixed model | Multivariable model for repeated measures or clustered continuous outcomes | Continuous | Multiple rows per subject | Yes | `lme4` + `lmerTest` | Satterthwaite approximated degrees of freedom via `lmerTest` |
| Logistic mixed model | Multivariable model for repeated measures or clustered binary outcomes | Binary (2-level factor) | Multiple rows per subject | Yes | `lme4::glmer` | Likelihood ratio tests via `anova()` for all fixed effects; see §4.2 |
| Stepwise selection | Variable selection helper; advisory only | Continuous or binary | One row per subject | No | `stats::step` | From final selected `lm` or `glm` object |
| LASSO penalized regression | Variable selection helper; advisory only | Continuous or binary | One row per subject | No | `glmnet` | None by design — no inference table produced |
| Collinearity summary | Pre-fit pairwise correlation screen; post-fit formal VIF | Continuous candidates | Any | Any | `performance`, `correlation` | Not applicable |

### 4.2 P-value and Confidence Interval Methods

| Method | P-value approach | Confidence intervals | Notes |
|---|---|---|---|
| Linear regression | t-tests, native from `summary()` | `confint()` — exact | Standard OLS assumptions apply |
| Logistic regression | Wald z-tests, native from `summary()` | `confint()` — profile likelihood by default | Wald acceptable at adequate sample size |
| Linear mixed model | Satterthwaite approximated degrees of freedom via `lmerTest` | Wald-based via `confint()` | Profile CIs more accurate but slow; Wald used by default with footnote |
| Logistic mixed model | **Likelihood ratio tests via `anova()`** for all fixed effects | Wald-based via `confint()` | Wald z-tests unreliable for `glmer` with small samples, sparse data, near-boundary random effects, or singular fit — LRT is correct and used exclusively |
| Stepwise | From final `lm` or `glm` object | From final model object | Inference on stepwise-selected model labeled advisory |
| LASSO | None | None | Explicitly exploratory; coefficient path and selected variable list only |

**Implementation note for logistic mixed model LRT:** fitting LRT p-values requires fitting a reduced model for each fixed effect term — k+1 model fits total for a model with k fixed effects. The progress modal reflects this with per-term step updates. Publication tables display LRT χ² statistics and p-values. Footnote reads: *"P-values derived from likelihood ratio tests. Confidence intervals are Wald-based."*

### 4.3 Full Package Dependencies

| Function | Packages |
|---|---|
| Modeling | `stats` (base R), `lme4`, `lmerTest`, `glmnet` |
| Tidy extraction | `broom`, `broom.mixed` |
| Parameter tables and inference | `parameters` |
| Diagnostics | `performance`, `insight` |
| Correlation and collinearity | `correlation` |
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
| Main model fit | "Run Model" | Fast for `lm`/`glm`; slower for mixed models with LRT p-values |
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
    ├── Step 6: Diagnostics            layout_sidebar(position = "left")
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
- Decimal places: numeric input, default 2
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

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** diagnostic toggles and run button
- **Main panel (right):** diagnostic outputs — `navset_card_tab`

**Sidebar:** checkbox list of diagnostic sections (conditional on model type, all checked by default); **"Run Diagnostics"** button; disabled message if no model run.

**Main panel tabs — conditional on model type:**

All models: Sample Accounting tab.

Linear regression: Residuals, Influence, Collinearity tabs.

Logistic regression: Discrimination (ROC/AUC), Calibration, Predicted Probabilities, Influence, Collinearity, Separation (if detected) tabs.

Linear mixed model: Residuals, Random Effects (ICC, cluster size), Collinearity, Convergence tabs.

Logistic mixed model: Calibration, Random Effects, Collinearity, Convergence tabs.

VIF shown as transparency tool only — no prompt to refit. Post-fit VIF nudges: amber for VIF 5–10, orange for VIF > 10.

**Step complete when:** diagnostics run at least once.

---

#### Step 7 — Results

**Layout:** `layout_sidebar(position = "left")`
- **Sidebar (left):** output object selection and generate button
- **Main panel (right):** generated outputs — `navset_card_tab`

**Sidebar:** checkbox list of output objects with defaults by model type:

| Output object | Default |
|---|---|
| Multivariable results table | Checked |
| Univariable results table | Checked |
| Fit statistics table | Checked |
| Forest plot | Unchecked |

Decimal places selector (carries from Step 5). **"Generate Selected Outputs"** button — launches blocking modal. Disabled if no model run.

**Main panel tabs:**
- **Multivariable Results Table:** publication-style table; OR (95% CI) for logistic; β (95% CI) for linear; footnotes: p-value method, reference levels, CI method, N
- **Univariable Results Table:** unadjusted associations; runs univariable screen if not already run in Step 3
- **Fit Statistics:** metric + value table per model type
- **Forest Plot:** coefficient forest plot; exposure row highlighted; null reference line

Placeholder cards for unselected outputs.

**Step complete when:** outputs generated at least once.

---

#### Step 8 — Export

**Layout:** full-width — `layout_columns(col_widths = c(6, 6))`.

**Left column:** preset bundle selector (radio buttons: Analysis Package, Manuscript Items, Full Report, Everything); individual item checklist by category (Tables, Figures, Data, Code and Spec, Report, Full Result Object, Analysis Package); report format selector; **"Download"** button — launches blocking modal. Greyed items for outputs not yet generated with tooltip.

**Right column:** live zip folder preview updating reactively; selected items shown with ✓ in green, unselected muted with —.

**Step complete when:** download initiated at least once.

---

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
