# EDARK Analysis Module — PRD Section 10
## Export and Output Specification (Revised)

---

## 10.1 Overview

The export system assembles selected outputs into a timestamped zip file. It reads exclusively from cached objects in `analysis_result` — no model refitting, recomputation, or code generation occurs during export. All exportable objects (tables, figures, R script, spec) are generated and cached at their respective workflow steps. The export system retrieves and writes them to files.

The export item checklist repopulates on Step 8 tab entry. Items generated since the last visit to Step 8 become available (un-greyed) dynamically.

The export pipeline is triggered by the Download button in Step 8 and runs inside the blocking modal with per-step progress updates.

The export UI specification (checklist layout, preset bundles, zip preview) is defined in §6.10. The R code generator specification is defined in §7.9. This section specifies the file generation mechanics, report structure, and folder structure.

---

## 10.2 Export Folder Structure

All exports are assembled into a timestamped root directory and zipped. The structure follows a manuscript-oriented organization: methods (how it was done), results (what was produced), diagnostics (model checks).

The `methods/` folder always contains individually selected components — data files, R script, spec files — whenever those items are checked in the export checklist.

The self-contained analysis package is a separate export option that produces a single `.zip` file in the root directory. It is intentionally redundant with the individual files in `methods/` — it exists for a specific purpose (v1.5 EDARK import) and is placed in the root for easy discovery.

**Full folder structure (all items selected):**

```
analysis_[YYYY-MM-DD_HHMMSS]/
│
├── methods/
│   ├── methods.docx                        ← methods paragraph
│   ├── analysis_script.R                   ← generated R code
│   ├── analysis_specification.json         ← spec (human-readable)
│   ├── analysis_specification.rds          ← spec (for programmatic use)
│   └── data/
│       ├── analysis_dataset.rds
│       ├── analysis_dataset.csv
│       ├── analysis_dataset.sav
│       ├── analysis_dataset.dta
│       └── analysis_dataset.xlsx
│
├── results/
│   ├── tables/
│   │   ├── table1_overall.docx
│   │   ├── table1_by_exposure.docx
│   │   ├── table1_by_outcome.docx
│   │   ├── multivariable_results.docx
│   │   ├── univariable_results.docx
│   │   └── fit_statistics.docx
│   └── figures/
│       └── forest_plot.png
│
├── diagnostics/
│   ├── tables/
│   │   ├── diagnostic_summary.docx
│   │   ├── vif_table.docx
│   │   ├── sample_accounting.docx
│   │   ├── univariable_screen.docx
│   │   └── stepwise_selection_log.docx
│   └── figures/
│       ├── residuals_vs_fitted.png
│       ├── qq_plot.png
│       ├── scale_location.png
│       ├── influence_plot.png
│       ├── random_effects_qq.png
│       ├── cluster_size_distribution.png
│       ├── collinearity_heatmap.png
│       ├── cramers_v_matrix.png
│       ├── lasso_coefficient_path.png
│       ├── lasso_cross_validation.png
│       ├── roc_curve.png
│       ├── calibration_plot.png
│       └── predicted_probabilities.png
│
├── analysis_report.docx                    ← report in root
├── analysis_result.rds                     ← full R object in root
└── analysis_package_[HHMMSS].zip           ← self-contained package in root
```

Only files that are selected in the export checklist and have been generated are included. Empty folders are not created. The zip preview in Step 8 reflects the actual contents.

**Note:** this folder structure supersedes the preliminary structure defined in §3.8, which should be considered replaced by this section.

---

## 10.3 Export Assembly Pipeline

When the user clicks Download, the following sequence executes inside the blocking modal:

```
✓  Validating selections
✓  Creating folder structure
⟳  Writing tables...
○  Writing figures
○  Writing methods files
○  Writing data files
○  Generating report
○  Building analysis package
○  Assembling zip
○  Finalizing
```

Each step updates the modal. On error at any step: the modal shows the failed step in red with a plain-language message and a Close button. Partial outputs are not delivered — the zip is only produced on full success.

**Step details:**

1. **Validate selections:** confirm at least one item is selected; if data export is enabled, confirm at least one format is selected.
2. **Create folder structure:** create the timestamped root directory and all required subdirectories in `tempdir()`.
3. **Write tables:** for each selected table, write the DOCX file from the cached gtsummary/flextable object.
4. **Write figures:** for each selected figure, write PNG from the cached ggplot object.
5. **Write methods files:** write methods.docx, R script, and analysis spec files to `methods/` from cached objects in `analysis_result`.
6. **Write data files:** for each selected data format, write the frozen dataset to `methods/data/`.
7. **Generate report:** assemble the Word or HTML report (see §10.7).
8. **Build analysis package:** if selected, assemble the self-contained zip (see §10.9).
9. **Assemble zip:** zip the entire temp directory via `zip::zip()`.
10. **Finalize:** trigger browser download, show success notification.

---

## 10.4 Table File Generation

All tables are written as DOCX files via `flextable::save_as_docx()`. The `gtsummary` objects stored in `analysis_result$result_tables` are converted to flextable via `gtsummary::as_flex_table()` before writing.

| Table | Source in `analysis_result` | Filename | Folder |
|---|---|---|---|
| Table 1 — Overall | `result_tables$table1_overall` | `table1_overall.docx` | `results/tables/` |
| Table 1 — By exposure | `result_tables$table1_by_exposure` | `table1_by_exposure.docx` | `results/tables/` |
| Table 1 — By outcome | `result_tables$table1_by_outcome` | `table1_by_outcome.docx` | `results/tables/` |
| Multivariable results | `result_tables$main_results` | `multivariable_results.docx` | `results/tables/` |
| Univariable results | `result_tables$univariable_screen` | `univariable_results.docx` | `results/tables/` |
| Fit statistics | `inference_summary$fit_statistics` | `fit_statistics.docx` | `results/tables/` |
| Diagnostic summary | `result_tables$diagnostic_summary` | `diagnostic_summary.docx` | `diagnostics/tables/` |
| VIF table | From diagnostics computation | `vif_table.docx` | `diagnostics/tables/` |
| Sample accounting | From diagnostics computation | `sample_accounting.docx` | `diagnostics/tables/` |
| Univariable screen | `variable_investigation$univariable$full_output$results_table` | `univariable_screen.docx` | `diagnostics/tables/` |
| Stepwise selection log | `variable_investigation$stepwise$full_output$selection_path` | `stepwise_selection_log.docx` | `diagnostics/tables/` |
| Dataset summary | Generated from `analysis_data` metadata | `dataset_summary.docx` | `diagnostics/tables/` |

The methods paragraph is written as a DOCX file: `methods.docx` in the `methods/` folder. Generated from the same text displayed in Step 7's Methods tab, formatted as a paragraph via flextable.

For tables stored as tibbles (fit statistics, univariable screen, stepwise log, diagnostic summary): a flextable is constructed directly:

```r
flextable::flextable(tibble) %>%
  flextable::autofit() %>%
  flextable::save_as_docx(path = output_path)
```

---

## 10.5 Figure File Generation

All figures are written as PNG files via `ggplot2::ggsave()`. Default dimensions: width = 8 inches, height = 6 inches, dpi = 300. These produce publication-quality figures at standard journal dimensions.

| Figure | Source in `analysis_result` | Filename | Folder |
|---|---|---|---|
| Forest plot | `result_plots$coefficient_plot` | `forest_plot.png` | `results/figures/` |
| Residuals vs fitted | `result_plots$diagnostic_plots$residuals_vs_fitted` | `residuals_vs_fitted.png` | `diagnostics/figures/` |
| Q-Q plot | `result_plots$diagnostic_plots$qq_plot` | `qq_plot.png` | `diagnostics/figures/` |
| Scale-location | `result_plots$diagnostic_plots$scale_location` | `scale_location.png` | `diagnostics/figures/` |
| Influence plot | `result_plots$diagnostic_plots$influence_plot` | `influence_plot.png` | `diagnostics/figures/` |
| Random effects Q-Q | `result_plots$diagnostic_plots$random_effects_qq` | `random_effects_qq.png` | `diagnostics/figures/` |
| Cluster size distribution | `result_plots$diagnostic_plots$cluster_size_plot` | `cluster_size_distribution.png` | `diagnostics/figures/` |
| ROC curve | `result_plots$diagnostic_plots$roc_curve` | `roc_curve.png` | `diagnostics/figures/` |
| Calibration plot | `result_plots$diagnostic_plots$calibration_plot` | `calibration_plot.png` | `diagnostics/figures/` |
| Predicted probabilities | `result_plots$diagnostic_plots$predicted_probs` | `predicted_probabilities.png` | `diagnostics/figures/` |
| Collinearity heatmap | `result_plots$collinearity_plots$correlation_heatmap` | `collinearity_heatmap.png` | `diagnostics/figures/` |
| Cramér's V matrix | `result_plots$collinearity_plots$cramers_v_matrix` | `cramers_v_matrix.png` | `diagnostics/figures/` |
| LASSO coefficient path | `result_plots$lasso_plots$coefficient_path` | `lasso_coefficient_path.png` | `diagnostics/figures/` |
| LASSO cross-validation | `result_plots$lasso_plots$cross_validation` | `lasso_cross_validation.png` | `diagnostics/figures/` |

All ggplot objects are stored in `analysis_result` at computation time. At export, `ggsave()` writes from the cached object — no recomputation.

---

## 10.6 Data File Generation

The frozen analysis dataset is written from `shared_state$analysis_data` in each selected format. The `.edark_row_id` column is excluded from all exports — it is an internal identifier not meaningful outside the app.

| Format | Package | Call | Filename |
|---|---|---|---|
| RDS | base R | `saveRDS(data, path)` | `analysis_dataset.rds` |
| CSV | base R | `write.csv(data, path, row.names = FALSE)` | `analysis_dataset.csv` |
| SPSS .sav | `haven` | `haven::write_sav(data, path)` | `analysis_dataset.sav` |
| Stata .dta | `haven` | `haven::write_dta(data, path)` | `analysis_dataset.dta` |
| Excel .xlsx | `writexl` | `writexl::write_xlsx(data, path)` | `analysis_dataset.xlsx` |

All formats preserve factor levels and labels where the format supports it (RDS fully preserves R objects; SPSS and Stata preserve labeled values via haven; Excel and CSV write factor levels as character strings).

Data files are written to `methods/data/` in the export structure.

---

## 10.7 Analysis Report Generation

The report is a narrative document assembling analysis outputs into a single Word (.docx) or HTML file. The report structure is fixed in v1 (customizable report builder deferred to v1.5 per §12). The report is intended for researchers — it presents results in manuscript-adjacent format.

### Generation Method

**Word output:** assembled programmatically via `officer::read_docx()` and `officer::body_add_*()` calls — adding headings, paragraphs, tables (as flextables), and figures (as image files) sequentially. No intermediate Rmd template. Built entirely in R code via officer.

**HTML output:** a minimal `.Rmd` template rendered with analysis outputs injected as parameters. The Rmd template lives in the package at `inst/report_template.Rmd`.

### Report Sections (fixed order in v1)

**1. Title and metadata:**
```
EDARK Analysis Report
Generated: [timestamp]
Study type: [study type label]
```

**2. Analysis specification summary:**
- Outcome variable and type
- Exposure variable (if assigned)
- Covariates (final model covariates with reference levels)
- Model type
- Data structure (cross-sectional or repeated measures)
- Subject ID / clusters (if applicable)
- Complete cases: N of total (excluded count)

**3. Statistical methods paragraph:**
The auto-generated methods text from Step 7, inserted verbatim.

**4. Table 1:**
All generated Table 1 stratifications included. Each as a flextable embedded in the document. Headers: "Table 1a — Overall", "Table 1b — By Exposure", "Table 1c — By Outcome" as applicable.

**5. Results:**
- Multivariable results table (flextable)
- Univariable results table if generated (flextable)
- Combined table if generated
- Fit statistics table (flextable)
- Forest plot (embedded image)

**6. Appendix A — Variable Selection:**
Results of variable selection methods that were performed:
- Univariable screen table (if run) — with parameters noted: "p-value threshold: 0.2"
- Stepwise selection log and selected variables (if run) — with parameters: "backward, BIC"
- LASSO suggested variables and lambda used (if run) — with parameters: "lambda.1se (λ = 0.032)"
- If no methods were run: *"No formal variable selection was performed. Covariates were selected based on clinical judgment."*

**7. Appendix B — Diagnostics:**
- Sample accounting table
- VIF table
- Diagnostic plots that were generated (embedded images)
- For logistic models with prediction diagnostics: ROC curve, calibration plot
- Convergence and singular fit warnings if applicable (text paragraphs)

Only sections with actual content are included — if Table 1 was not generated, section 4 is omitted. If prediction diagnostics were not run, those figures are omitted from Appendix B.

---

## 10.8 Analysis Specification Export

`analysis_spec` is exported in two formats:

**JSON** — human-readable, for analysts who want to inspect the spec in a text editor:
```r
jsonlite::toJSON(analysis_spec, pretty = TRUE, auto_unbox = TRUE) %>%
  writeLines(con = json_path)
```

**RDS** — machine-readable, preserves R types exactly, used for v1.5 analysis package import:
```r
saveRDS(analysis_spec, file = rds_path)
```

Both written to `methods/` when individually selected. Both also included in the self-contained analysis package when that option is selected.

---

## 10.9 Self-Contained Analysis Package

The analysis package is a portable zip file designed for reproducibility and sharing. It contains everything needed to reproduce the analysis in EDARK. Exported as `analysis_package_[HHMMSS].zip` in the root of the export directory — standard zip format, placed at root for easy discovery.

The package is a **separate export option** from the individual methods files. Both can be selected simultaneously. Redundancy between the package contents and the individual files in `methods/` is intentional — the package exists for a specific purpose (v1.5 EDARK import) while the individual files serve direct access.

### Package Contents

| File | Purpose |
|---|---|
| `analysis_dataset.rds` | Frozen dataset (always RDS regardless of other data format selections) |
| `analysis_specification.rds` | Full spec for programmatic import |
| `analysis_specification.json` | Full spec in human-readable format |
| `analysis_script.R` | Generated R script |
| `manifest.json` | Package metadata for validation on import |

### Manifest File

```json
{
  "package_version": "1.0",
  "created_at": "2024-11-14T14:30:22",
  "edark_version": "0.1.0",
  "r_version": "4.3.2",
  "study_type": "exposure_outcome",
  "model_type": "logistic_regression",
  "dataset_signature": {
    "columns": ["aki", "hypotension", "age", "asa_class", "baseline_cr"],
    "column_classes": ["factor", "factor", "numeric", "factor", "numeric"],
    "factor_levels": {
      "aki": ["0", "1"],
      "hypotension": ["0", "1"],
      "asa_class": ["I", "II", "III"]
    },
    "row_count": 400
  },
  "data_format": "rds",
  "import_compatible": true
}
```

The manifest enables v1.5 package import to validate compatibility: check dataset signature against the current working dataset, verify EDARK version, and load the spec via `readRDS()`.

### Import Workflow (v1.5 — documented now, implemented later)

1. User uploads `.zip` package file
2. App unzips to temp directory
3. Read `manifest.json` — validate `package_version`, check `edark_version` compatibility
4. Read `analysis_specification.rds` — restore `analysis_spec`
5. Validate `dataset_signature` against current `shared_state$analysis_data`:
   - Exact match → proceed silently
   - Row count differs → soft warning
   - Factor levels differ → hard warning
   - Column structure differs → blocking error
6. If valid: populate `analysis_spec` from the loaded RDS, navigate user to Step 1 with roles pre-populated
7. User reviews, modifies if needed, and proceeds through the workflow

---

## 10.10 Full Analysis Result Object

The complete `analysis_result` list (as defined in §3.6) is serialized via `saveRDS()` and written to `analysis_result.rds` at the root of the export directory.

This file contains everything: raw fitted model objects, all gtsummary table objects, all ggplot plot objects, all tidy tibbles, all warnings and messages. It may be large — potentially tens of MB depending on dataset size and model complexity.

This is for Archetype C who wants to do post-hoc work in their own R session: additional contrasts, custom plots, extracting specific values, rerunning diagnostics with different settings. Loading this file gives them the complete fitted analysis without needing to rerun anything.

The export checklist labels this item: *"Full analysis result (RDS) — Contains all fitted model objects, tables, and plots as R objects. For use in R. File may be large."*

---

## 10.11 Diagnostic Summary Table Contents

The diagnostic summary table (`diagnostic_summary.docx`) is a compact reference table containing all numeric diagnostic values that were computed. One row per metric. Only includes metrics from diagnostics that were actually run.

**Contents for linear regression:**

| Metric | Value |
|---|---|
| Max VIF | 2.300 |
| Mean VIF | 1.800 |
| Variables with VIF > 5 | 0 |
| Variables with VIF > 10 | 0 |
| Max Cook's D | 0.040 |
| Observations exceeding 4/n threshold | 2 |
| Breusch-Pagan statistic | 1.230 |
| Breusch-Pagan p-value | 0.410 |

**Additional rows for logistic regression:**

| Metric | Value |
|---|---|
| Separation detected | No |
| AUC (if prediction diagnostics run) | 0.810 |
| AUC 95% CI (if prediction diagnostics run) | 0.760 – 0.860 |

**Additional rows for mixed models:**

| Metric | Value |
|---|---|
| ICC | 0.310 |
| N clusters | 42 |
| Median cluster size | 9 |
| Min cluster size | 3 |
| Max cluster size | 28 |
| Singular fit | No |
| Converged | Yes |
| Optimizer | bobyqa |

---

## 10.12 Methods Files Summary

The `methods/` folder contains the analytical reproducibility artifacts:

| File | Source | Notes |
|---|---|---|
| `methods.docx` | Methods paragraph from Step 7 Methods tab | Retrieved from cache |
| `analysis_script.R` | R code generator output from Step 5 | Retrieved from `analysis_result`; generator spec in §7.9 |
| `analysis_specification.json` | `analysis_spec` serialized to JSON | Serialized at export time |
| `analysis_specification.rds` | `analysis_spec` serialized to RDS | Serialized at export time |
| `data/analysis_dataset.*` | `shared_state$analysis_data` in selected formats | Written at export time; `.edark_row_id` excluded |

The R script is generated at model specification time (Step 5) and cached in `analysis_result`. The export system retrieves it — it does not regenerate it.

The methods paragraph is generated at results generation time (Step 7) and cached. Same retrieval pattern.

The analysis spec is serialized fresh at export time to capture any post-fit state. Data files are written at export time from the frozen dataset.
