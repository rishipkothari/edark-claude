# EDARK Analysis Module — PRD Section 9
## Variable Selection Subsystem

---

## 9.1 Purpose and Framing

The variable selection subsystem helps the analyst decide which candidate covariates should enter the final multivariable model. It is explicitly advisory — no method in this subsystem commits covariates to the model. All three methods produce a suggested variable list that the analyst reviews and confirms in Step 4.

The subsystem operates on the candidate covariate pool defined in Step 1. It does not have access to variables outside this pool. The outcome variable and exposure variable (if assigned) are not part of the candidate pool — they are fixed in the model formula regardless of variable selection results. Variable selection determines only which covariates accompany the exposure in the model.

---

## 9.2 Common Input Requirements

All three methods require the same information from `shared_state` and `analysis_spec`:

- **Data:** `shared_state$analysis_data` — the frozen dataset. Complete cases are computed across the outcome variable plus all candidate covariates. All three methods operate on the same complete-case subset so their results are comparable.
- **Outcome variable:** `analysis_spec$variable_roles$outcome_variable`
- **Outcome type:** binary or continuous, derived from `shared_state$column_types`
- **Candidate pool:** `analysis_spec$variable_roles$candidate_covariates`
- **Reference levels:** `analysis_spec$variable_roles$reference_levels` — applied before any method runs. The releveled dataset is shared across all methods.

No literal input data structure is constructed and passed. Each method's engine function reads from `shared_state` and `analysis_spec` directly.

---

## 9.3 Common Output Contract

Every method produces a result conforming to the same structure:

```r
variable_selection_result <- list(
  method              = "univariable",     # "univariable" | "stepwise" | "lasso"
  parameters          = list(),            # method-specific parameters used (see §9.4)
  suggested_variables = character(),       # variable names matching dataset column names
  full_output         = NULL,              # method-specific detailed output (see §9.4)
  timestamp           = Sys.time()
)
```

The `suggested_variables` character vector is what Step 4's import buttons read. All three methods produce this vector in the same format — variable names matching the column names in the frozen dataset. For factor variables, the original variable name is used (not dummy-coded level names).

The `parameters` list records the specific settings used for this run, enabling display in Step 4 column header tooltips and in export metadata.

The `full_output` field holds method-specific details for display in Step 3 pills.

---

## 9.4 Method Specifications

### Univariable Screen

**What it does:** fits one regression model per candidate covariate against the outcome. Identifies variables with statistically notable unadjusted associations.

**Model family:** determined automatically from outcome type. `lm` for continuous, `glm(family = binomial)` for binary. Always standard regression — never mixed, regardless of subject ID assignment. Note displayed: *"Unadjusted associations. Clustering not accounted for in screening models."*

**Configurable parameters (Step 3 Univariable Screen pill sidebar):**

| Parameter | Input type | Default | Range | Tooltip |
|---|---|---|---|---|
| P-value threshold | `numericInput` | 0.2 | 0.01–0.5 | "Variables with unadjusted p-value below this threshold are suggested for inclusion. The default of 0.2 is standard for confounder screening." |

**Suggested variable list:** all candidates with p-value below the configured threshold.

**`parameters` stored:**
```r
parameters = list(p_threshold = 0.2)
```

**`full_output` contents:**

```r
full_output = list(
  results_table = tibble(     # displayed in Step 3 Univariable Screen pill
    variable   = character(), # variable name
    estimate   = numeric(),   # β or OR
    conf_lower = numeric(),   # lower 95% CI
    conf_upper = numeric(),   # upper 95% CI
    p_value    = numeric()    # p-value
  ),
  model_objects = list(),     # named list of individual lm/glm objects
  outcome_type  = "binary",   # for labeling
  model_family  = "glm"       # for labeling
)
```

---

### Stepwise Selection

**What it does:** starts from a full or null model and iteratively adds or removes variables based on AIC or BIC, arriving at a suggested model.

**Model family:** `lm` or `glm` depending on outcome type. Standard regression only, never mixed.

**Configurable parameters (Step 3 Stepwise/LASSO pill sidebar, Stepwise toggle):**

| Parameter | Input type | Default | Options | Tooltip |
|---|---|---|---|---|
| Direction | `radioGroupButtons` | Backward | Backward, Forward | "Backward starts with all candidates and removes; Forward starts empty and adds." |
| Criterion | `radioGroupButtons` | BIC | BIC, AIC | "BIC penalizes complexity more heavily, producing more parsimonious models. AIC favors slightly larger models." |

BIC is the default because it penalizes complexity more heavily and produces more parsimonious models, which is generally preferred for clinical association studies.

**Suggested variable list:** the variables retained in the final stepwise model.

**`parameters` stored:**
```r
parameters = list(direction = "backward", criterion = "BIC")
```

**`full_output` contents:**

```r
full_output = list(
  final_formula       = formula(),    # formula of selected model
  selection_path      = tibble(       # displayed in Step 3
    step              = integer(),    # step number
    action            = character(),  # "removed" | "added"
    variable          = character(),  # variable acted on
    criterion_value   = numeric()     # AIC or BIC at this step
  ),
  suggested_variables = character(),  # variables in final model
  final_model         = NULL,         # the fitted lm/glm from final step
  criterion_used      = "BIC",
  direction_used      = "backward"
)
```

---

### LASSO Penalized Regression

**What it does:** fits an L1-penalized regression across all candidates simultaneously. Shrinks weak coefficients toward zero, effectively performing selection. Cross-validated to choose the regularization strength.

**Model family:** `"gaussian"` for continuous outcome, `"binomial"` for binary outcome.

**Configurable parameters (Step 3 Stepwise/LASSO pill sidebar, LASSO toggle):**

| Parameter | Input type | Default | Options | Tooltip |
|---|---|---|---|---|
| Lambda selection | `radioGroupButtons` | lambda.1se | lambda.1se, lambda.min | "lambda.1se is more parsimonious (recommended). lambda.min gives best cross-validated performance but may overfit." |

Fixed (not configurable in v1):
- Alpha = 1 (pure LASSO, not elastic net). Elastic net (alpha 0–1) is a v1.5 consideration.
- CV folds = 10. Standard, no reason to expose.

**Factor variable handling:** `model.matrix()` dummy-codes factor variables. LASSO penalizes individual dummy levels independently. The suggested variable list reports the **original factor variable name** if any of its dummy levels have non-zero coefficients. LASSO does not split factors at the variable selection level.

**Suggested variable list:** variables with non-zero coefficients at the chosen lambda.

**`parameters` stored:**
```r
parameters = list(lambda = "lambda.1se", lambda_value = 0.032)
```

**`full_output` contents:**

```r
full_output = list(
  cv_fit              = NULL,         # cv.glmnet object
  glmnet_fit          = NULL,         # glmnet object (for path plot)
  lambda_used         = "lambda.1se",
  lambda_value        = numeric(),    # actual lambda value
  suggested_variables = character(),
  coefficient_table   = tibble(       # all variables with their coefficients
    variable    = character(),
    coefficient = numeric(),          # at chosen lambda
    selected    = logical()           # non-zero = TRUE
  ),
  n_folds             = 10
)
```

---

## 9.5 Spec Storage

Variable selection parameters are stored in `analysis_spec$variable_selection_specification`:

```r
variable_selection_specification = list(
  method                  = "univariable",    # last method run, or "manual"
  univariable_p_threshold = 0.2,              # configurable in Step 3 sidebar
  stepwise_direction      = "backward",       # configurable in Step 3 sidebar
  stepwise_criterion      = "BIC",            # configurable in Step 3 sidebar
  lasso_lambda            = "lambda.1se",     # configurable in Step 3 sidebar
  selected_variables      = NULL              # final confirmed list from Step 4
)
```

---

## 9.6 Interaction Between Methods

The three methods are independent — running one does not affect or invalidate another. All three can be run in any order, and their results coexist. Running univariable screen, then LASSO, then stepwise leaves all three results available simultaneously.

If a method is rerun (e.g., stepwise rerun with different direction or criterion), the previous result for that method is replaced. Other methods' results are unaffected.

---

## 9.7 Step 4 Confirmation Table — Integration with Variable Selection Results

The Step 4 confirmation table displays suggestion indicators from all methods that have been run. The table is the central decision-making tool for covariate selection.

**Table structure:**

| Column | Content | Notes |
|---|---|---|
| Variable | Variable name | Sortable, filterable via search above table |
| Type | Static badge | Numeric, factor, character |
| Include | Checkbox | All pre-checked by default |
| Univariable | Suggestion indicator | See below |
| Stepwise | Suggestion indicator | See below |
| LASSO | Suggestion indicator | See below |
| Reference Level | Single select dropdown | Factor variables only; R factor level order |

**Column headers for Univariable, Stepwise, LASSO:**

Each method column header contains two elements stacked vertically within the header cell:

1. **Import button** — small `actionButton` styled as `btn-outline-secondary btn-sm`. Disabled if the method was not run. Clicking triggers confirmation modal (see §9.8).
2. **Method name with tooltip** — e.g. "Univariable (?)" where (?) is an info icon. Hovering shows a tooltip with the parameters used:

Univariable tooltip:
```
Parameters:
· P-value threshold: 0.2
```

Stepwise tooltip:
```
Parameters:
· Direction: backward
· Criterion: BIC
```

LASSO tooltip:
```
Parameters:
· Lambda: lambda.1se (0.032)
```

If the method was not run, the tooltip reads: *"Not run. Return to Step 3 to run this method."*

**Cell content and highlighting:**

| State | Cell content | Background color |
|---|---|---|
| Method run, variable suggested | ✓ (with p-value for univariable, e.g. "✓ p=0.004") | Light green |
| Method run, variable not suggested | — | Light pink |
| Method not run | — | Neutral grey |

This provides an immediate visual heat map of agreement across methods. A variable green across all columns is a strong candidate. A variable pink across all columns is a clear exclusion. Mixed signals require clinical judgment.

---

## 9.8 Import Behavior

Import buttons live in the column headers of the Step 4 confirmation table — one per method column. Each import button unchecks variables not selected by that method. It does not check variables that were unchecked — it only unchecks.

**Flow:**

1. Default state: all candidates pre-checked
2. User clicks "Import" in the Stepwise column header
3. Confirmation modal: *"This will uncheck variables not selected by Stepwise (backward, BIC). Your current selections will be modified. Continue?"*
4. On confirm: variables NOT in stepwise `suggested_variables` are unchecked
5. User reviews, potentially re-checks some variables
6. If user clicks "Import" in the LASSO column header: operates on the current checkbox state, not the default state

Each import operates on the current checkbox state. A confirmation modal fires before each import.

**Special case — method selected no variables:** if a method's `suggested_variables` is empty, the import would uncheck everything. The modal warns: *"Stepwise (backward, BIC) selected no variables. Importing will uncheck all covariates. Continue?"*

---

## 9.9 Edge Cases

**No candidates assigned:** if `candidate_covariates` is empty or NULL, all three methods are disabled in Step 3. Each pill shows a placeholder: *"No candidate covariates assigned. Return to Step 1 to assign covariates."* The Step 4 confirmation table is empty.

**Single candidate:** all methods run normally on one variable. Stepwise will either keep or remove the single variable. LASSO will either shrink it to zero or keep it. Univariable screen produces a one-row table. Valid but unusual — the `PF_SINGLE_COVARIATE` note in preflight flags it.

**All candidates excluded by a method:** possible if LASSO shrinks everything to zero or stepwise removes all variables. The suggested variable list is empty. Import behavior described in §9.8.

**LASSO fails to converge:** `cv.glmnet` can fail if the design matrix is rank-deficient or if all candidates are perfectly collinear. Wrapped in `tryCatch`. On failure: error notification shown in Step 3, LASSO result remains NULL, LASSO output panel shows error message, LASSO import button in Step 4 remains disabled.

**Stepwise fails:** `stats::step` can fail if the full model is rank-deficient. Same `tryCatch` handling, same error display pattern.

**Univariable screen — individual variable fitting failure:** individual model failure (e.g., separation in a single univariable logistic model) is caught per-variable via `tryCatch`. The variable appears in the results table with NA values and a note: *"Model fitting failed for this variable."* Other variables are unaffected. The suggested list excludes failed variables.

---

## 9.10 Variable Selection Results in `analysis_result`

Variable selection results are stored in `analysis_result` for export and for Step 4 consumption:

```r
analysis_result$variable_investigation <- list(
  univariable = NULL,   # variable_selection_result or NULL if not run
  stepwise    = NULL,   # variable_selection_result or NULL if not run
  lasso       = NULL    # variable_selection_result or NULL if not run
)
```

Each slot is either NULL (method not run) or a `variable_selection_result` object per §9.3 containing the `method`, `parameters`, `suggested_variables`, `full_output`, and `timestamp`.

Step 4 reads from these slots to:
- Populate the suggestion indicator columns (✓ or — with highlighting)
- Enable or disable import buttons per method
- Populate column header tooltips with parameters used
- Display p-values in the univariable column cells
