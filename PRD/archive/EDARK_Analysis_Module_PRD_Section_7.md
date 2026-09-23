# EDARK Analysis Module — PRD Section 7
## Statistical Specification per Model

---

## 7.1 General Principles Applied to All Models

**Formula assembly:** the formula is constructed from `analysis_spec$variable_roles` at fit time. The pattern is `outcome ~ exposure + covariate_1 + covariate_2 + ...`. If no exposure is assigned (risk factor study), the formula is `outcome ~ covariate_1 + covariate_2 + ...`. For mixed models, the random effects term is appended: `+ (1 | subject_id)` or `+ (1 + slope_var | subject_id)`.

**Reference levels:** before fitting, all factor variables in the model are releveled using `forcats::fct_relevel()` or base `relevel()` according to `analysis_spec$variable_roles$reference_levels`. This happens once, on the frozen analysis dataset, before any model is fit. The releveled dataset is used for all fits including univariable models.

**Complete cases:** all models use `na.action = na.omit` (the default). The number of rows excluded is computed before fitting by checking for NAs across all variables in the formula. This count is stored in `run_status$run_messages` as a note and displayed in the sample accounting diagnostic.

**Confidence intervals:** Wald-based for all models via `confint.default()`. 95% level, hardcoded. Footnote in all publication tables: *"Wald-based confidence intervals."*

**P-values:** method varies by model type as specified per model below. All p-values displayed to 3 decimal places maximum; values < 0.001 displayed as *"< 0.001"*.

**Warning capture:** all model fitting is wrapped in `withCallingHandlers()` to capture warnings (convergence, singular fit, etc.) without stopping execution. Warnings are stored as rows in `run_status$run_messages` with `level = "warning"` and `stage = "fitting"`.

**gtsummary integration:** publication tables for all models are generated via `gtsummary::tbl_regression()` which handles factor variable formatting, reference level display, footnotes, and the combined univariable + multivariable merge via `tbl_merge()`. The raw tidy tibble goes into `inference_summary$coefficients` for programmatic access. The gtsummary object goes into `result_tables$main_results` for display and export.

---

## 7.2 Linear Regression

**Fitting call:**
```r
model <- lm(formula, data = analysis_data_complete)
```

**Extraction pipeline:**

| Extract | Call | Stored in |
|---|---|---|
| Coefficients | `broom::tidy(model, conf.int = TRUE, conf.level = 0.95)` | `inference_summary$coefficients` |
| Fit statistics | `broom::glance(model)` | `inference_summary$fit_statistics` |
| Fitted values, residuals, Cook's D, leverage | `broom::augment(model)` | `inference_summary$predicted_values`, `inference_summary$influence_measures` |
| Publication table | `gtsummary::tbl_regression(model, exponentiate = FALSE)` | `result_tables$main_results` |
| VIF | `performance::check_collinearity(model)` | `result_tables$diagnostic_summary` |

**P-value method:** native t-tests from `summary(model)`. Extracted automatically by `broom::tidy()`. Footnote: *"P-values from t-tests."*

**Fit statistics extracted from `glance()`:**

| Metric | Source |
|---|---|
| N analyzed | `nobs(model)` |
| R² | `glance$r.squared` |
| Adjusted R² | `glance$adj.r.squared` |
| RMSE | `sigma(model)` |
| F-statistic | `glance$statistic` |
| AIC | `glance$AIC` |
| BIC | `glance$BIC` |

**Diagnostics — Model Assumptions:**

| Diagnostic | Implementation | Output type |
|---|---|---|
| Residuals vs fitted | `ggplot(augmented, aes(.fitted, .resid)) + geom_point() + geom_hline(yintercept = 0) + geom_smooth(se = FALSE)` | ggplot |
| Q-Q plot | `ggplot(augmented, aes(sample = .std.resid)) + stat_qq() + stat_qq_line()` | ggplot |
| Scale-location | `ggplot(augmented, aes(.fitted, sqrt(abs(.std.resid)))) + geom_point() + geom_smooth(se = FALSE)` | ggplot |
| Breusch-Pagan test | `lmtest::bptest(model)` — extract statistic and p-value | Value card: statistic, p-value |
| Cook's distance | `ggplot(augmented, aes(seq_along(.cooksd), .cooksd)) + geom_col() + geom_hline(yintercept = 4/nobs(model))` | ggplot |
| Leverage vs residuals | `ggplot(augmented, aes(.hat, .std.resid)) + geom_point()` | ggplot |
| Top influential observations | Filter augmented to top 10 by Cook's D; display `.edark_row_id`, Cook's D, leverage, standardized residual | DT::datatable |
| VIF table | `performance::check_collinearity(model)` — variable, VIF, tolerance; amber rows VIF 5–10, red rows VIF > 10 | DT::datatable |

**Diagnostics — Prediction Performance:** not applicable to linear regression (continuous outcome).

---

## 7.3 Logistic Regression

**Fitting call:**
```r
model <- glm(formula, data = analysis_data_complete, family = binomial)
```

**Extraction pipeline:**

| Extract | Call | Stored in |
|---|---|---|
| Coefficients (OR scale) | `broom::tidy(model, conf.int = TRUE, conf.level = 0.95, exponentiate = TRUE)` | `inference_summary$coefficients` |
| Coefficients (log-odds, for forest plot) | `broom::tidy(model, conf.int = TRUE, conf.level = 0.95, exponentiate = FALSE)` | Internal use only — forest plot on log scale |
| Fit statistics | `broom::glance(model)` | `inference_summary$fit_statistics` |
| Fitted values (predicted probabilities) | `broom::augment(model, type.predict = "response")` | `inference_summary$predicted_values` |
| Influence measures | `broom::augment(model)` — Cook's D, leverage | `inference_summary$influence_measures` |
| Publication table | `gtsummary::tbl_regression(model, exponentiate = TRUE)` | `result_tables$main_results` |
| VIF | `performance::check_collinearity(model)` | `result_tables$diagnostic_summary` |
| Separation check | `detectseparation::detect_separation(model)` | `run_status$run_messages` if detected |

**P-value method:** Wald z-tests from `summary(model)`. Extracted automatically by `broom::tidy()`. Footnote: *"P-values from Wald z-tests."*

**Confidence intervals:** Wald-based. `broom::tidy(conf.int = TRUE)` calls `confint.default()` internally. Footnote: *"Wald-based confidence intervals."*

**Fit statistics:**

| Metric | Source |
|---|---|
| N analyzed | `nobs(model)` |
| N events | `sum(model$y)` |
| Event rate | `mean(model$y) * 100` (displayed as %) |
| Pseudo R² (McFadden) | `1 - (model$deviance / model$null.deviance)` |
| Pseudo R² (Nagelkerke) | `performance::r2_nagelkerke(model)` |
| AIC | `glance$AIC` |
| BIC | `glance$BIC` |
| Log-likelihood | `logLik(model)` |

**Diagnostics — Model Assumptions:**

| Diagnostic | Implementation | Output type |
|---|---|---|
| Cook's distance | Same approach as linear regression using augmented data | ggplot |
| Top influential observations | Same as linear regression — top 10 by Cook's D | DT::datatable |
| VIF table | `performance::check_collinearity(model)` — same format as linear | DT::datatable |
| Separation | `detectseparation::detect_separation(model)` — if separation detected: warning card listing involved variable(s), plain-language explanation, suggested actions (remove variable, collapse factor levels, consider exact logistic) | Warning card or confirmation card |

**Diagnostics — Prediction Performance (supplementary — not required for association studies):**

| Diagnostic | Implementation | Output type |
|---|---|---|
| ROC curve with AUC | `roc_obj <- pROC::roc(response = model$y, predictor = fitted(model))` ; AUC via `pROC::auc(roc_obj)` with CI via `pROC::ci.auc(roc_obj)` ; plot via `pROC::ggroc(roc_obj)` | ggplot + value card (AUC with 95% CI) |
| Calibration plot | Bin predicted probabilities into deciles; compute observed event rate per decile; `ggplot(aes(x = mean_predicted, y = observed_rate)) + geom_point() + geom_abline(intercept = 0, slope = 1)` | ggplot |
| Predicted probability distribution | `ggplot(augmented, aes(x = .fitted, fill = factor(outcome))) + geom_density(alpha = 0.5)` | ggplot |

---

## 7.4 Linear Mixed Model

**Fitting call:**
```r
model <- lmerTest::lmer(formula, data = analysis_data_complete,
                        control = lme4::lmerControl(optimizer = optimizer_choice))
```

Where `optimizer_choice` is from `analysis_spec$model_design$optimizer` (default: `"bobyqa"`).

**Formula construction:**

Random intercept only:
```r
outcome ~ exposure + cov1 + cov2 + (1 | subject_id)
```

Random intercept + random slope:
```r
outcome ~ exposure + cov1 + cov2 + (1 + slope_var | subject_id)
```

**Extraction pipeline:**

| Extract | Call | Stored in |
|---|---|---|
| Fixed effects coefficients | `broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, conf.level = 0.95)` | `inference_summary$coefficients` |
| Random effects variance components | `broom.mixed::tidy(model, effects = "ran_pars")` | Appended to `inference_summary$fit_statistics` |
| Fit statistics | `broom.mixed::glance(model)` | `inference_summary$fit_statistics` |
| Fitted values and residuals | `broom.mixed::augment(model)` — conditional (includes random effects) | `inference_summary$predicted_values` |
| Publication table | `gtsummary::tbl_regression(model, exponentiate = FALSE)` | `result_tables$main_results` |
| VIF | `performance::check_collinearity(model)` | `result_tables$diagnostic_summary` |
| Marginal and conditional R² | `performance::r2_nakagawa(model)` | `inference_summary$fit_statistics` |
| ICC | `performance::icc(model)` | `inference_summary$fit_statistics` |

**P-value method:** Satterthwaite approximated degrees of freedom via `lmerTest`. Present automatically in the tidy output when fitted with `lmerTest::lmer()`. Footnote: *"P-values from Satterthwaite approximated degrees of freedom."*

**Fit statistics:**

| Metric | Source |
|---|---|
| N observations | `nobs(model)` |
| N clusters | `length(unique(analysis_data_complete[[subject_id_var]]))` |
| Marginal R² | `performance::r2_nakagawa(model)$R2_marginal` |
| Conditional R² | `performance::r2_nakagawa(model)$R2_conditional` |
| ICC | `performance::icc(model)$ICC_adjusted` |
| AIC | `glance$AIC` |
| BIC | `glance$BIC` |
| Log-likelihood | `glance$logLik` |
| Random intercept SD | from `tidy(effects = "ran_pars")` |
| Residual SD | from `tidy(effects = "ran_pars")` |

**Diagnostics — Model Assumptions:**

| Diagnostic | Implementation | Output type |
|---|---|---|
| Residuals vs fitted | `ggplot(augmented, aes(.fitted, .resid)) + geom_point() + geom_hline(yintercept = 0) + geom_smooth(se = FALSE)` — conditional residuals | ggplot |
| Q-Q plot of residuals | `ggplot(augmented, aes(sample = .resid)) + stat_qq() + stat_qq_line()` — conditional residuals | ggplot |
| Random effects Q-Q plot | Extract BLUPs via `ranef(model)[[1]]`; Q-Q plot of random intercepts against theoretical normal quantiles | ggplot |
| ICC value card | `performance::icc(model)` | Value card |
| Cluster size distribution | Histogram of observations per cluster: `ggplot(cluster_counts, aes(x = n)) + geom_histogram()` | ggplot |
| Cluster size summary | Min, median, mean, max observations per cluster | Table card |
| VIF table | `performance::check_collinearity(model)` | DT::datatable |
| Singular fit check | Captured from fitting warnings; `isSingular(model)` as confirmation | Warning card or confirmation card |
| Convergence check | Captured from fitting warnings; check `model@optinfo$conv$lme4` | Warning card with optimizer suggestion or confirmation card |

**Diagnostics — Prediction Performance:** not applicable to continuous outcome models.

---

## 7.5 Logistic Mixed Model

**Fitting call:**
```r
model <- lme4::glmer(formula, data = analysis_data_complete,
                     family = binomial,
                     control = lme4::glmerControl(optimizer = optimizer_choice))
```

**Formula construction:** same pattern as linear mixed model with random effects terms.

**Extraction pipeline:**

| Extract | Call | Stored in |
|---|---|---|
| Fixed effects coefficients (OR scale) | `broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, conf.level = 0.95, exponentiate = TRUE)` | `inference_summary$coefficients` |
| Fixed effects (log-odds, for forest plot) | `broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, conf.level = 0.95, exponentiate = FALSE)` | Internal use only |
| Random effects variance components | `broom.mixed::tidy(model, effects = "ran_pars")` | Appended to `inference_summary$fit_statistics` |
| Fit statistics | `broom.mixed::glance(model)` | `inference_summary$fit_statistics` |
| Marginal predicted probabilities | `predict(model, type = "response", re.form = NA)` — `re.form = NA` gives marginal (fixed effects only) | `inference_summary$predicted_values` |
| Publication table | `gtsummary::tbl_regression(model, exponentiate = TRUE)` | `result_tables$main_results` |
| VIF | `performance::check_collinearity(model)` | `result_tables$diagnostic_summary` |
| ICC | `performance::icc(model)` | `inference_summary$fit_statistics` |

**P-value method:** Wald z-tests from `summary(model)`. Extracted automatically by `broom.mixed::tidy()`. Footnote: *"P-values from Wald z-tests. Interpret with caution in small samples or with rare outcomes."*

**Confidence intervals:** Wald-based via `confint.default(model)`. Footnote: *"Wald-based confidence intervals."*

**Fit statistics:**

| Metric | Source |
|---|---|
| N observations | `nobs(model)` |
| N clusters | `length(unique(analysis_data_complete[[subject_id_var]]))` |
| N events | `sum(model@resp$y)` |
| Event rate | `mean(model@resp$y) * 100` (displayed as %) |
| Marginal AUC | Computed from marginal predicted probabilities via `pROC::roc()` — only if prediction diagnostics are checked |
| AIC | `glance$AIC` |
| BIC | `glance$BIC` |
| Log-likelihood | `glance$logLik` |
| Random intercept variance | from `tidy(effects = "ran_pars")` |
| ICC | `performance::icc(model)$ICC_adjusted` |

**Diagnostics — Model Assumptions:**

| Diagnostic | Implementation | Output type |
|---|---|---|
| Random effects Q-Q plot | Extract BLUPs via `ranef(model)[[1]]`; Q-Q plot against theoretical normal quantiles | ggplot |
| ICC value card | `performance::icc(model)` | Value card |
| Cluster size distribution | Same as linear mixed model | ggplot |
| Cluster size summary | Same as linear mixed model | Table card |
| VIF table | `performance::check_collinearity(model)` | DT::datatable |
| Singular fit check | `isSingular(model)` | Warning card or confirmation card |
| Convergence check | Captured from fitting warnings; check `model@optinfo$conv$lme4` | Warning card with optimizer suggestion or confirmation card |

**Diagnostics — Prediction Performance (supplementary — not required for association studies):**

All prediction diagnostics use **marginal** predicted probabilities via `predict(model, type = "response", re.form = NA)`. Marginal predictions reflect fixed effects only — the clinically generalizable quantity. Conditional predictions (including random effects) are specific to clusters in the dataset and do not generalize.

| Diagnostic | Implementation | Output type |
|---|---|---|
| ROC curve with AUC | `roc_obj <- pROC::roc(response = model@resp$y, predictor = marginal_preds)` ; AUC and CI via `pROC::auc()` and `pROC::ci.auc()` ; plot via `pROC::ggroc(roc_obj)` | ggplot + value card |
| Calibration plot | Bin marginal predicted probabilities into deciles; observed event rate per decile; same ggplot approach as standard logistic | ggplot |
| Predicted probability distribution | `ggplot(aes(x = marginal_preds, fill = factor(outcome))) + geom_density(alpha = 0.5)` | ggplot |

---

## 7.6 Univariable Regression Screen

The univariable screen is not a separate model type but a batch execution of the linear or logistic regression engine. It runs one model per candidate covariate in the univariable test pool.

**Fitting:** for each candidate variable `x_i`:
- Continuous outcome: `lm(outcome ~ x_i, data = analysis_data_complete)`
- Binary outcome: `glm(outcome ~ x_i, data = analysis_data_complete, family = binomial)`

Always standard regression regardless of whether subject ID or cluster is assigned. Note shown: *"Unadjusted associations. Clustering not accounted for in screening models."*

**Extraction per model:**
```r
broom::tidy(model_i, conf.int = TRUE, conf.level = 0.95,
            exponentiate = (outcome_type == "binary"))
```

Extract only the row for `x_i` (not the intercept).

**Output:** a single tibble combining all univariable results:

| Column | Content |
|---|---|
| variable | Variable name |
| estimate | β (continuous outcome) or OR (binary outcome) |
| conf_lower | Lower 95% CI |
| conf_upper | Upper 95% CI |
| p_value | P-value |

Sorted by p-value ascending by default.

Stored in `result_tables$univariable_screen` and individual model objects stored in `fitted_models$univariable_models` as a named list.

**Combined table:** when the combined univariable + multivariable table is requested in Step 7, `gtsummary::tbl_uvmultivariable()` or `tbl_merge()` is used to produce a side-by-side table. Variables present in the univariable screen but excluded from the multivariable model show their unadjusted estimate with "—" in the adjusted columns. Footnote: *"— Variable considered but not included in the final multivariable model."*

---

## 7.7 Stepwise Selection

**Fitting:** starts from a full model (all candidates) or null model (intercept only) depending on direction.

```r
# Backward (default)
full_model <- lm(outcome ~ all_candidates, data = analysis_data_complete)
# or glm(..., family = binomial) for binary outcome
step_result <- stats::step(full_model,
                           direction = "backward",
                           k = if (criterion == "BIC") log(nobs(full_model)) else 2,
                           trace = 0)
```

```r
# Forward
null_model <- lm(outcome ~ 1, data = analysis_data_complete)
full_scope <- formula(lm(outcome ~ all_candidates, data = analysis_data_complete))
step_result <- stats::step(null_model,
                           scope = list(lower = ~1, upper = full_scope),
                           direction = "forward",
                           k = if (criterion == "BIC") log(nobs(null_model)) else 2,
                           trace = 0)
```

Note: `k = log(n)` gives BIC criterion; `k = 2` gives AIC. This is the standard `stats::step()` parameterization.

**Output:**
- Selected model formula
- Selection path: captured by running `step()` with `trace = 1` into a text connection and parsing the output, or by comparing nested models at each step. Stored as a tibble: step number, action (added/removed), variable, criterion value at that step.
- Suggested variable list: extracted from the final model formula via `all.vars(formula(step_result))`, removing the outcome.

Stored in `analysis_result` under a variable investigation results section. Not in `fitted_models` — stepwise is advisory, not a final model.

---

## 7.8 LASSO Penalized Regression

**Fitting:**
```r
x_matrix <- model.matrix(~ all_candidates, data = analysis_data_complete)[, -1]
y_vector <- analysis_data_complete[[outcome_var]]

cv_fit <- glmnet::cv.glmnet(
  x = x_matrix,
  y = y_vector,
  family = if (outcome_type == "binary") "binomial" else "gaussian",
  alpha = 1,  # LASSO (not ridge or elastic net)
  nfolds = 10
)
```

**Lambda selection:** user chooses `lambda.1se` (default — more parsimonious) or `lambda.min` (best cross-validated performance). Stored in `analysis_spec$variable_selection_specification$lasso_lambda`.

**Output:**
- Coefficient path plot: `plot(glmnet::glmnet(x_matrix, y_vector, family = ..., alpha = 1))` converted to ggplot2 via manual extraction of the path matrix. Each line is one variable's coefficient trajectory across lambda values.
- Cross-validation plot: `plot(cv_fit)` converted to ggplot2 — mean cross-validated error vs log(lambda) with error bars and vertical lines at `lambda.min` and `lambda.1se`.
- Suggested variable list: variables with non-zero coefficients at the chosen lambda. Extracted via `coef(cv_fit, s = chosen_lambda)` and filtering for non-zero entries (excluding intercept).

Stored in `analysis_result` under variable investigation results. No inference produced — explicitly advisory.

**Note on factor variables:** `model.matrix()` dummy-codes factor variables. LASSO may select some levels of a factor but not others. The suggested variable list reports the original factor variable name if any of its dummy levels have non-zero coefficients — LASSO does not split factors.

---

## 7.9 R Code Generation

Every model fit has a corresponding R script generated from `analysis_spec`. The script is a complete, standalone, executable R file that reproduces the analysis outside the app. It is generated at fit time and stored in `analysis_result` for export.

**Script structure:**
```r
# ============================================================
# EDARK Analysis — Generated R Script
# Generated: [timestamp]
# ============================================================

# --- Packages -----------------------------------------------
library(lme4)        # if mixed model
library(lmerTest)    # if linear mixed model
library(gtsummary)
library(broom)       # or broom.mixed for mixed models
library(performance)
library(ggplot2)

# --- Data ---------------------------------------------------
# Load the frozen analysis dataset
analysis_data <- readRDS("analysis_dataset.rds")

# Reference levels
analysis_data$asa_class <- relevel(analysis_data$asa_class, ref = "I")
analysis_data$sex <- relevel(analysis_data$sex, ref = "Male")

# Complete cases
analysis_data_complete <- analysis_data[complete.cases(
  analysis_data[, c("aki", "hypotension", "age", "asa_class", "baseline_cr")]
), ]

cat("N complete cases:", nrow(analysis_data_complete),
    "of", nrow(analysis_data), "\n")

# --- Model --------------------------------------------------
model <- glm(
  aki ~ hypotension + age + asa_class + baseline_cr,
  data = analysis_data_complete,
  family = binomial
)

# --- Results ------------------------------------------------
# Coefficients (odds ratios)
tidy_results <- broom::tidy(model, conf.int = TRUE,
                            conf.level = 0.95, exponentiate = TRUE)
print(tidy_results)

# Fit statistics
broom::glance(model)

# Publication table
gtsummary::tbl_regression(model, exponentiate = TRUE)

# --- Diagnostics --------------------------------------------
# VIF
performance::check_collinearity(model)

# Separation check
detectseparation::detect_separation(model)

# Influence
augmented <- broom::augment(model)
# [Cook's distance plot code]
# [Influential observations code]
```

The script is **dynamically assembled** via `paste0` / `glue` from the `analysis_spec`. No templates are stored. The spec contains everything needed — outcome variable name, exposure name, covariate names, reference levels, model type — and the code generator reads the spec and writes R code as a character string line by line.

The script includes only packages and code relevant to the fitted model type. Mixed model scripts include `lme4`/`lmerTest`, random effects extraction, ICC computation, convergence checks. The script matches the analysis exactly — same formula, same reference levels, same data preparation. **If the generated code and the app produce different results, the app has a bug.** Full code generation specification is in §10.

---

## 7.10 Summary of Dependencies by Model Type

| Package | Linear | Logistic | Linear Mixed | Logistic Mixed | Stepwise | LASSO |
|---|---|---|---|---|---|---|
| `stats` | ✓ | ✓ | | | ✓ | |
| `lme4` | | | ✓ | ✓ | | |
| `lmerTest` | | | ✓ | | | |
| `glmnet` | | | | | | ✓ |
| `broom` | ✓ | ✓ | | | | |
| `broom.mixed` | | | ✓ | ✓ | | |
| `gtsummary` | ✓ | ✓ | ✓ | ✓ | | |
| `performance` | ✓ | ✓ | ✓ | ✓ | | |
| `lmtest` | ✓ | | | | | |
| `pROC` | | ✓ | | ✓ | | |
| `detectseparation` | | ✓ | | | | |
| `ggplot2` | ✓ | ✓ | ✓ | ✓ | | ✓ |
