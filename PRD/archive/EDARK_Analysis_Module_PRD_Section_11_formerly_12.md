# EDARK Analysis Module — PRD Section 12
## Versioning and Deferral Log (Revised)

---

## 12.1 Version 1 Scope

Confirmed in scope for v1:

- Descriptive summary and Table 1
- Unadjusted group comparisons
- Linear regression
- Logistic regression
- Linear mixed model
- Logistic mixed model
- Stepwise variable selection (forward/backward, AIC/BIC)
- LASSO variable selection
- Collinearity diagnostics
- Model assumption diagnostics per model type (residuals, influence, VIF, convergence, separation detection)
- Prediction performance diagnostics for logistic models (ROC/AUC, calibration, predicted probabilities) — supplementary, unchecked by default
- Manuscript-ready tables and figures
- Methods paragraph auto-generation
- Export zip with full folder structure
- Self-contained analysis package (export only)
- Reproducible R script generation
- Wald-based confidence intervals and p-values for all model types

---

## 12.2 Deferred Features by Priority

---

### High Priority — v1.5

**Propensity score methods**
- Propensity score matching (PSM)
- Inverse probability treatment weighting (IPTW)
- Propensity score-adjusted regression
- Requires a two-stage design-then-analysis workflow. `analysis_spec` has `linked_model_specification` stubbed as NULL and `analysis_result` has `linked_model_result` stubbed as NULL — both ready to accommodate PS without breaking changes to the shared state structure.
- When implemented: binary exposure variable required; PS methods appear as a separate model family option in the model selector; design stage (PS model specification, overlap check) precedes outcome analysis stage.

**Prepare pipeline session bundle**
- Full session export containing the raw original dataset plus the complete Prepare pipeline configuration (column type overrides, transforms, row filters).
- Allows a collaborator to feed the raw dataset into the app and have the entire Prepare pipeline replay automatically, arriving at an identical working dataset.
- Must be designed and built in the Prepare module first, then optionally bundled into the Analysis package export as an additional component.
- Dataset signature infrastructure in §3.2 is directly relevant to validating these bundles on import.
- Once available, the Analysis package export gains a third data option alongside the frozen RDS: full session bundle.

---

### Mid Priority — v1.5

**Analysis package import**
- v1 exports the self-contained analysis package (frozen dataset + spec JSON + R script + manifest).
- v1.5 implements the import workflow: load package → validate dataset signature → restore `analysis_spec` into analysis module → allow re-run or modification.
- Dataset signature validation rules in §3.2 define the compatibility checking behavior on import.
- Depends on Prepare pipeline session bundle feature being available first for full utility.

**Additional model types**
- Generalized estimating equations (GEE)
- Multinomial logistic regression
- Ordinal logistic regression
- Poisson regression
- Negative binomial regression
- Each requires a new engine implementation conforming to the registry pattern defined in §11. No structural changes to `analysis_spec` or `analysis_result` required — new `model_type` values added to the model selector dropdown and corresponding engine files added to the backend service layer.

**Marginal effects and predicted value plots**
- Average marginal effects for logistic models: change in predicted probability per unit change in predictor.
- More clinically interpretable than ORs for many audiences.
- Implementation via `marginaleffects` package.

**Likelihood ratio test p-values for logistic mixed models**
- v1 uses Wald z-tests for all model types for consistency and computational simplicity.
- LRT via `anova()` is the gold standard for `glmer` fixed effects, particularly in small samples or with rare outcomes where Wald tests can be unreliable.
- v1.5 adds LRT as an advanced option exposed under the mixed model advanced settings panel. Requires k+1 model fits for k fixed effect terms — computationally expensive but more accurate.
- When enabled: progress modal shows per-term fitting steps; publication table footnote updates to reflect LRT p-values.

**Profile likelihood confidence intervals for logistic regression**
- v1 uses Wald-based CIs for all model types for consistency and speed.
- Profile likelihood CIs via `confint()` (not `confint.default()`) are more accurate, particularly for small samples or near-boundary estimates.
- v1.5 adds profile likelihood as an advanced option for standard logistic regression, with a timeout-based fallback to Wald if profile computation exceeds 10 seconds.
- Not applicable to mixed models where profile CIs are prohibitively slow.

**Customizable report builder**
- v1 has a fixed report structure: specification summary, methods paragraph, Table 1, results tables, figures, diagnostics summary, R script appendix, analysis specification appendix.
- v1.5 adds a report configuration UI allowing custom section selection, section ordering, narrative text entry fields, and figure captions.
- Lives as an expanded configuration panel within Step 8 Export, replacing the fixed report contents note.

**Number needed to treat / absolute risk reduction**
- For binary outcomes with binary exposure.
- Computed from model predicted probabilities; requires a reference probability assumption.
- Implementation straightforward once marginal effects are available.

**Dynamic significant-figure-based rounding**
- Currently all numeric values capped at 3 decimal places globally.
- Future: detect appropriate decimal places per column based on significant figures of the data (sig figs + 2 or similar heuristic).
- Low complexity once implemented; deferred because v1 fixed rounding is sufficient for clinical reporting.

---

### Low Priority — v2 or later

**Survival and time-to-event models**
- Cox proportional hazards regression
- Kaplan-Meier curves
- Requires time-to-event outcome type support added throughout: role assignment, preflight validation, model selector, diagnostic suite, results tables.

**Stratified models**
- Running the model separately within subgroups and presenting results side by side.
- Excluded from v1 to preserve the one-analysis-at-a-time principle.
- When implemented: subgroup variable assigned in role assignment; model runs independently per subgroup level; results presented in a side-by-side comparison table.

**Saved runs and model comparison**
- Ability to save multiple named analysis runs within a session and compare results side by side.
- Explicitly excluded from v1 to preserve the one-analysis-at-a-time principle and avoid reactive state complexity.
- If implemented: `analysis_saved_runs` field added to `shared_state`; each saved run is a named `analysis_result` object; comparison view produces side-by-side coefficient tables.

**Async progress bars**
- v1 uses synchronous blocking modals with step-list progress display.
- `future` + `promises` async pattern would allow cancellable operations and non-blocking UI during long computations.
- Evaluate necessity per step based on observed performance before implementing.
- Most likely candidates for async if needed: mixed model fitting, large univariable screens, zip assembly for large exports.

**Prediction modeling infrastructure**
- Full prediction model development and validation workflow:
  - Split-sample validation (train/test splits)
  - K-fold cross-validation
  - Calibration-in-the-large
  - Net reclassification improvement (NRI)
  - Integrated discrimination improvement (IDI)
  - Net benefit / decision curve analysis
  - Optimism-corrected performance via bootstrapping
- This is a fundamentally different analytical workflow from association studies and may warrant its own module rather than extension of the Analysis module.
- v1 includes basic supplementary prediction diagnostics (ROC/AUC, calibration plot, predicted probability distribution) for ad-hoc use. Full prediction infrastructure is v2+.

---

## 12.3 Out of Scope Permanently

These will not be implemented in any version of the Analysis module:

- Bayesian models
- Machine learning classifiers
- Mediation and structural equation modeling
- Multiple imputation
- Automated model selection
- Arbitrary R code execution
- Spline-heavy nonlinear modeling
- Causal forests, TMLE, and doubly robust methods
- Hosmer-Lemeshow test (falling out of favor; calibration plot is the preferred alternative)
