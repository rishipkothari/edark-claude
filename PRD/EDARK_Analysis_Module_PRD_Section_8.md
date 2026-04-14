# EDARK Analysis Module — PRD Section 8
## Preflight Validation Layer

---

## 8.1 Architecture

The preflight validator is a pure function — no side effects, no reactivity, no UI dependencies. It takes the `analysis_spec` and the frozen `analysis_data` as inputs and returns a structured result. The UI renders whatever the validator returns. No validation logic lives in UI code.

```r
validate_analysis <- function(spec, data, tier = "full", verbose = FALSE) {
  messages <- tibble::tibble(
    level   = character(),   # "error" | "warning" | "note" | "pass"
    code    = character(),   # unique check ID e.g. "PF_NO_OUTCOME"
    check   = character(),   # human-readable check name
    message = character()    # detailed message
  )
  
  # ... all checks append rows ...
  
  # Determine validity flag
  validity_flag <- if (any(messages$level == "error")) {
    "invalid"
  } else if (any(messages$level == "warning")) {
    "warnings"
  } else {
    "valid"
  }
  
  # Filter for display
  display_messages <- if (verbose) {
    messages
  } else {
    dplyr::filter(messages, level %in% c("error", "warning"))
  }
  
  list(
    validity_flag    = validity_flag,   # "valid" | "warnings" | "invalid"
    messages         = messages,         # full message set (for programmatic use)
    display_messages = display_messages  # filtered for UI rendering
  )
}
```

The `code` column gives each check a unique identifier so the UI can target specific messages and tests can verify specific checks fire correctly.

When `verbose = TRUE`, pass-level checks are included in `display_messages` with green check icons. When `verbose = FALSE`, only warnings and errors are shown.

---

## 8.2 Validation Tiers

### Tier 1 — Core Data Validity

Runs before any analysis operation: univariable screen, stepwise, LASSO, and multivariable model. Checks fundamental data readiness.

| Code | Level | Check | Condition | Message |
|---|---|---|---|---|
| `PF_NO_OUTCOME` | error | Outcome assigned | `spec$variable_roles$outcome_variable` is NULL | "No outcome variable assigned. Return to Step 1." |
| `PF_ZERO_COMPLETE` | error | Complete cases exist | Zero rows remain after excluding NAs across variables in formula | "No complete cases remain after excluding rows with missing data. Review missingness or reduce variable list." |
| `PF_OUTCOME_NO_VARIANCE_BINARY` | error | Binary outcome has events | Outcome is binary and has zero events (all 0) or all events (all 1) | "Outcome variable has no events (all values identical). A logistic model cannot be fit." |
| `PF_OUTCOME_NO_VARIANCE_CONTINUOUS` | error | Continuous outcome has variance | Outcome is continuous and has only one unique value | "Outcome variable has only one unique value. A linear model cannot be fit." |
| `PF_FACTOR_SINGLE_LEVEL` | error | Factor levels adequate | Any factor variable in the model has only one level remaining after complete-case exclusion | "Variable [X] has only one level remaining after excluding rows with missing data. Remove it or address missingness." |

### Tier 2 — Model Specification Validity

Runs before multivariable model fitting only. Includes all Tier 1 checks plus model-specific checks.

**Errors (block Run Model):**

| Code | Level | Check | Condition | Message |
|---|---|---|---|---|
| `PF_NO_PREDICTORS` | error | Predictors assigned | No exposure and no covariates in final model | "No predictors assigned. Add an exposure variable or covariates before fitting." |
| `PF_OUTCOME_MODEL_MISMATCH` | error | Outcome type matches model | Binary outcome + linear model, or continuous outcome + logistic model | "Outcome type ([type]) is incompatible with [model type]. Select the appropriate model." |
| `PF_MIXED_NO_SUBJECT` | error | Mixed model has subject ID | Mixed model selected but `subject_id_variable` is NULL | "Mixed models require a subject ID variable. Assign one in Step 1 or select a non-mixed model." |
| `PF_MIXED_SINGLE_CLUSTER` | error | Multiple clusters exist | Random intercept variable has only one unique value | "Only one cluster found in [variable]. A mixed model requires multiple clusters." |
| `PF_PENDING_COVARIATES` | error | Covariates confirmed | Step 4 has unconfirmed changes | "Covariate selection has unconfirmed changes. Return to Step 4 and confirm." |

**Warnings (do not block — model can be fit but results may be unreliable):**

| Code | Level | Check | Condition | Message |
|---|---|---|---|---|
| `PF_LOW_EPV_10` | warning | Events per variable ≥ 10 | Logistic model: events / parameters < 10 | "Events per variable: [X]. Fewer than 10 — risk of overfitting. Consider reducing covariates." |
| `PF_LOW_EPV_5` | warning | Events per variable ≥ 5 | Logistic model: events / parameters < 5 | "Events per variable: [X]. Fewer than 5 — high risk of overfitting and unreliable estimates." |
| `PF_MISSING_ANY` | warning | No missing data | Any rows excluded due to NAs | "[X] rows ([Y]%) excluded due to missing data. Report in methods section." |
| `PF_MISSING_GT20` | warning | Missing < 20% | More than 20% of rows excluded | "Complete-case analysis excludes more than 20% of data ([X]%). Review missingness." |
| `PF_MISSING_GT50` | warning | Missing < 50% | More than 50% of rows excluded | "Complete-case analysis excludes more than 50% of data ([X]%). Results may not be representative." |
| `PF_RARE_FACTOR_LEVEL` | warning | Factor levels adequate size | Any factor level has < 5 observations after complete cases | "Variable [X] has a level with fewer than 5 observations. May cause instability." |
| `PF_HIGH_CORRELATION` | warning | Low pairwise correlation | Any covariate pair has Pearson correlation > 0.7 | "High correlation ([r]) between [X] and [Y]. Review collinearity." |
| `PF_FEW_CLUSTERS` | warning | Adequate clusters | Mixed model with fewer than 10 clusters | "Only [N] clusters. Random effects estimation may be unreliable with fewer than 10." |
| `PF_UNBALANCED_CLUSTERS` | warning | Balanced clusters | Largest cluster > 10× smallest cluster | "Highly unbalanced cluster sizes (range: [min]–[max]). May affect mixed model estimation." |
| `PF_RARE_OUTCOME` | warning | Outcome prevalence adequate | Logistic model: event rate < 5% or > 95% | "Outcome prevalence is [X]%. Rare events make Wald inference particularly fragile." |
| `PF_EXPOSURE_NOT_IN_MODEL` | warning | Exposure included | Exposure-outcome study type but exposure not in final covariates | "Exposure variable [X] is not in the final model. This may be unintentional." |

**Notes (informational only):**

| Code | Level | Check | Condition | Message |
|---|---|---|---|---|
| `PF_SINGLE_COVARIATE` | note | Multiple covariates | Only one covariate (non-exposure) in model | "Only one covariate entered. Verify this is intentional." |
| `PF_SAMPLE_SUMMARY` | note | Sample summary | Always | "N = [X] of [Y] rows included ([Z] excluded due to missing data)." |
| `PF_MODEL_SUMMARY` | note | Model summary | Always | "[Model type] with [N] predictors ([exposure] + [N-1] covariates)." |
| `PF_DATA_STRUCTURE` | note | Data structure | Always | "Cross-sectional (one row per subject)" or "Repeated measures ([median] observations per subject, [N] clusters)." |
| `PF_REFERENCE_LEVELS` | note | Reference levels | Any factor with non-default reference | "Reference levels: [variable] = [level], ..." |

---

## 8.3 When Validation Runs

| Trigger | Tier | Verbose available | Display location | Blocks action |
|---|---|---|---|---|
| Step 3 pill entry (Univariable, Stepwise/LASSO) | Tier 1 | No | Small banner at top of pill's main panel | Run button disabled if Tier 1 errors |
| Step 5 tab entry | Tier 2 (full) | Yes (uses current checkbox state) | Preflight accordion in Step 5 main panel | Run Model disabled if errors |
| Model type dropdown change in Step 5 | Tier 2 (full) | Yes (uses current checkbox state) | Preflight accordion in Step 5 main panel | Run Model disabled if errors |
| Run Preflight button click in Step 5 | Tier 2 (full) | Yes (checkbox) | Preflight accordion in Step 5 main panel | No — display only |
| Run Model button click in Step 5 | Tier 2 (full) | No | If invalid: errors shown in preflight card, fitting halted. If warnings: modal with warning list and Proceed/Cancel. If valid: proceed directly to fitting. | Yes — errors halt; warnings show modal |

**Warning modal on Run Model click:**

When `validity_flag == "warnings"` and Run Model is clicked:

```
── Preflight Warnings ──────────────────────────
⚠  Events per variable: 8.2 — risk of overfitting
⚠  13 rows (3.3%) excluded due to missing data
⚠  High correlation (0.78) between age and baseline_cr

Proceed with model fitting?

[ Cancel ]  [ Proceed ]
```

Proceed → fitting begins via blocking modal. Cancel → returns to Step 5, user can address warnings.

When `validity_flag == "valid"`: fitting proceeds directly, no intermediate modal.

When `validity_flag == "invalid"`: errors displayed in preflight accordion, Run Model button remains disabled, no modal.

---

## 8.4 Step 5 Main Panel Layout (Revised)

The Step 5 main panel is a single scrollable stack of `bslib::accordion` panels and a persistent formula line. No tabs.

```
┌─────────────────────────────────────────┐
│  ▼ Model Summary           [expanded]    │
│  Spec status, dataset context            │
├─────────────────────────────────────────┤
│  ▼ Preflight                [expanded]   │
│  [verbose checkbox] [Run Preflight btn]  │
│  Validation check results                │
├─────────────────────────────────────────┤
│  Formula Preview                         │
│  aki ~ hypotension + age + asa_class     │
├─────────────────────────────────────────┤
│  ▼ Model Results            [expanded]   │
│  (appears only after successful fit)     │
│  Primary estimate, CI, p-value           │
├─────────────────────────────────────────┤
│  ▶ R Code Preview           [collapsed]  │
│  Full executable script, copyable        │
└─────────────────────────────────────────┘
```

**Formula Preview** is a plain `tags$code` one-liner — not an accordion. Always visible. Updates live with spec changes. Serves as a visual anchor between validation and results.

**Model Results** accordion is not rendered pre-fit. It materializes after a successful model run via `insertUI` or conditional `renderUI`.

**R Code Preview** is generated live from the spec — does not require a fitted model. Updates whenever the spec changes. Collapsed by default; Archetype C expands it.

### Accordion State Transitions

**On preflight run (including tab entry):**
- Model Summary: expanded
- Preflight: expanded
- Model Results: collapsed (if it exists from a previous run)
- R Code: collapsed

**On successful model run:**
- Model Summary: expanded
- Preflight: expanded
- Model Results: expanded (newly appeared or re-expanded)
- R Code: collapsed

**On failed model run:**
- Model Summary: expanded
- Preflight: expanded (showing errors/warnings from the failed attempt)
- Model Results: collapsed or absent
- R Code: collapsed

User manual expand/collapse is respected until the next state transition event. Auto-expand/collapse fires only on preflight run and model fit triggers, not continuously.

### Model Summary Accordion Content

Always visible. Derived from `analysis_spec`, not from the fitted model.

Pre-model-selection:
```
── Model Specification ──────────────────────────
Model:           — not selected
Outcome:         aki (binary)
Exposure:        hypotension
Covariates:      age, asa_class, baseline_cr (3)
Complete cases:  387 / 400 (13 excluded)

── Dataset Context ──────────────────────────────
Numeric variables:    8
Factor variables:     6
Subject ID:           patient_id
Clusters:             42
```

Post-model-selection:
```
── Model Specification ──────────────────────────
Model:           Logistic regression
Outcome:         aki (binary)
Exposure:        hypotension
Covariates:      age, asa_class, baseline_cr (3)
Complete cases:  387 / 400 (13 excluded)

── Dataset Context ──────────────────────────────
Numeric variables:    8
Factor variables:     6
Subject ID:           patient_id
Clusters:             42
```

### Preflight Accordion Content

Verbose checkbox and Run Preflight button at top of accordion content area.

**Non-verbose mode (default):** shows only warnings and errors. If no warnings or errors: single green line — "All preflight checks passed." (This is the only case where a pass message shows in non-verbose mode.)

**Verbose mode:** shows every check with icons:
- Error: red `circle-xmark` icon, red text
- Warning: amber `triangle-exclamation` icon, amber text
- Note: blue `info-circle` icon, muted text
- Pass: green `circle-check` icon, muted text

### Model Results Accordion Content

Appears only after successful model fit. Shows primary result and key fit information:

```
── Primary Result ───────────────────────────────
Model:           Logistic regression
N analyzed:      387  (13 excluded — missing data)

Exposure:        hypotension
  OR: 2.34  (95% CI: 1.21 – 4.52)  p = 0.011

── Fit Summary ──────────────────────────────────
AIC:             312.4
Pseudo R²:       0.180

── Fitting Notes ────────────────────────────────
⚠  Events per variable: 12.9 — borderline
```

For risk factor studies (no exposure): shows all covariate estimates in a compact summary rather than highlighting a single exposure.

For mixed models: includes cluster summary (N clusters, ICC) in the fit summary section.

Warning flags from preflight and fitting are replayed in the Fitting Notes section.

---

## 8.5 Step 3 Tier 1 Validation Display

Each vertical pill in Step 3 (Univariable Screen, Collinearity, Stepwise/LASSO) has a small `uiOutput` validation banner at the top of its main panel.

**Tier 1 validation runs on pill entry** — when the user clicks the pill tab.

**If Tier 1 has errors:** red text banner with the error message. Run buttons within the pill are disabled.

```
⊘  Cannot run: Outcome variable has no events (all values identical).
```

**If Tier 1 is clean:** nothing visible. No green "ok" banner, no text. The absence of a banner means everything is fine.

**The banner is a single-line `uiOutput`** — not a card, not an accordion. Minimal footprint. Errors only. It exists solely to prevent the user from clicking a run button and waiting for a modal only to learn their data has a fundamental problem.

---

## 8.6 `reset_analysis_pipeline` Function

Called when a confirmed step is re-modified in a way that invalidates downstream results. The function is smart about what invalidates what — it uses the dependency map from §5.4 but instead of marking stale, it nulls out affected `analysis_result` fields and resets relevant UI state.

```r
reset_analysis_pipeline <- function(shared_state, from_step) {
  # from_step = 1 (role assignment change):
  #   clears: table1 results, var investigation results,
  #           covariate confirmation state, model, diagnostics, results
  #
  # from_step = 4 (covariate re-confirmation):
  #   clears: model, diagnostics, results
  #
  # from_step = 5 (model spec change, e.g. model type dropdown):
  #   clears: model, diagnostics, results
}
```

### Changes That Trigger Reset (with confirmation modal)

| Change | From step | Clears | Modal shown |
|---|---|---|---|
| Any role assignment change in Step 1 | 1 | Table 1, var investigation, covariate confirmation, model, diagnostics, results | Yes, if any downstream results exist |
| Covariate re-confirmation (Step 4 confirm clicked again) | 4 | Model, diagnostics, results | Yes, if model has been run |
| Model type change in Step 5 | 5 | Model, diagnostics, results | Yes, if model has been run |

### Changes That Do NOT Trigger Reset

| Change | Reason |
|---|---|
| Table 1 stratification or options | Table 1 is presentational — does not affect modeling |
| Variable investigation reruns (Step 3) | Advisory only — does not commit anything. Marks covariate confirmation as needing review but does not clear it. |
| Diagnostics rerun | Terminal — nothing downstream |
| Results regeneration | Terminal — nothing downstream |
| Export selections | No analytical impact |

### Confirmation Modal

Shown when a reset-triggering change is made and downstream results exist. The modal lists only items that actually exist and will be cleared:

```
This change will reset existing analysis results:

  · Fitted model and coefficients
  · Diagnostic outputs
  · Generated result tables and figures

Proceed?

[ Cancel ]  [ Reset and Continue ]
```

Items listed are conditional — if diagnostics haven't been run, "Diagnostic outputs" is omitted. If the only downstream result is a fitted model, only that is listed.

**Cancel:** the change is reverted. For Step 1 role assignment: the radio/checkbox change is undone. For Step 4: the confirm action is cancelled. For Step 5: the dropdown reverts to previous value.

**Reset and Continue:** `reset_analysis_pipeline()` executes, downstream results are nulled, the change is applied, and the user continues working.
