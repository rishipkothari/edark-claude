# CLAUDE.md — EDARK v0.2

EDARK is an R package: an interactive Shiny GUI for preparing, exploring, reporting on and modelling tabular clinical research data. `edark(dataset)` → **1 · Prepare** → **2 · Explore** (Plot + Report) → **3 · Analyze**.

This file is the **index**: where to find things, the rules that must never be broken, current state, and to-dos. Specs and mechanics live in the documents below — read the relevant section before changing code.

---

## Where to Find What

| Document | Prefix | Read it for |
|---|---|---|
| [PRD_0_Master.md](PRD_0_Master.md) | §M | Design and functional principles, app layout, `shared_state` ownership, how stages interact, outputs overview, **session save/load** (§M8), packages, scope |
| [PRD_1_Prepare.md](PRD_1_Prepare.md) | §P | Launch validation and auto-cast, Columns, Transforms, Row Filters, Apply pipeline, Data Preview |
| [PRD_2_Explore.md](PRD_2_Explore.md) | §E | Explore › Plot (Describe, Correlate, Trend, plot types, aesthetics) and Explore › Report (Full / Custom, formats, API) |
| [PRD_3_Analyze.md](PRD_3_Analyze.md) | §A | The 9-step analysis workflow: roles and model purpose, Table 1, variable investigation, covariates, model creation, preflight, diagnostics, performance, results, export |
| [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) | §N | Pitfalls, the **statistical methods registry** (§N2), and as-built mechanics per stage |
| [EDARK_Analysis_Build_Plan.md](EDARK_Analysis_Build_Plan.md) | — | Analyze build phases and acceptance criteria (incl. Phase 5b code generator, Phase 8 export, Phase S sessions) |
| [UI_Redesign_Plan.md](UI_Redesign_Plan.md) | — | **UI assessment and staged redesign** — the tri-pane + step-rail shell, component library, IA restructure. Stage status table at the top; work one stage per session |
| `.claude/UI principles.md` | — | Layout, action placement, visual hierarchy |
| [PRD_section_map.md](PRD_section_map.md) | — | Old → new section numbers (migration aid) |

**Quick lookup**

| Question | Go to |
|---|---|
| Which module owns / may write a `shared_state` field? | §M5.2 |
| Why does this recompute live when everything else waits for a click? | §M2.3 |
| Pipeline order for Apply | §P7.2 |
| Which plot type does a variable pair produce? | §E4, §E8 |
| Where must a p-value or CI be computed? | §N2 (spec §A4.2) |
| What does `reset_analysis_pipeline()` clear? | §A8.6, §N6.13 |
| Preflight check codes | §A8.2; adding a check §N6.12 |
| A reactable table loses its checkbox state | §N1.4 |
| An input still has a value after its UI disappeared | §N1.3 |
| Test dataset features (collinearity, noise, missingness) | §N7 |
| Association vs prediction; validation method (bootstrap / CV / held-out set) | §A1.4a; helpers §N6.2 |

**Precedence:** stage PRD for its stage; Master for anything cross-stage; the PRD wins over code and over §N unless the mismatch is listed under "Doc discrepancies" below.

---

## How to Run

```r
options(pkgType = "binary")  # always set before installing packages
devtools::install_deps()
devtools::load_all()         # load R/ during development (instead of library())
edark(liver_tx)              # launch with the built-in dataset
edark(your_dataframe)

devtools::document()         # rebuild roxygen docs
devtools::check()            # must pass with 0 errors, 0 warnings
```

Browser-side behaviour (reactable patching, JS handlers) can only be tested by driving the app with `chromote` (§N1.4).

---

## Non-Negotiables

Full rationale in the linked sections.

1. **One state object.** All session state in `shared_state` (created in `edark.R`'s `server()`); no `<<-`, no globals; modules talk only through it (§M5).
2. **Module convention.** `foo_ui(id)` + `foo_server(id, shared_state)`; siblings only; all server calls in `edark.R` (§M5.1).
3. **Analyze fields are private.** `analysis_data` / `analysis_spec` / `analysis_result` are read and written only by Analyze modules; Analyze reads Prepare state only at freeze (§M5.3).
4. **Original data is immutable.** `dataset_original` and `original_column_types` are never overwritten (§P2.3).
5. **Compute on click; stage Prepare changes.** Exceptions are only those in §M2.3.
6. **Prepare pipeline order:** overrides → column selection → transforms → row filters (§P7.2).
7. **One statistics engine.** p-values and CIs only via `R/stats_inference.R`; never call `confint*`, `chisq.test`, `fisher.test`, `kruskal.test`, `cor.test` or format a p-value elsewhere (§N2).
8. **`%>%` only**, never `|>` — in app code and generated scripts (§M9.3).
9. **Guard every observer that writes `shared_state` with `!identical()`** (§N1.2); never trust a conditionally rendered input (§N1.3).
10. **One definition per function** — no duplicates across files (§N1.8).

---

## File Map

```
R/
├── edark.R                      Entry point: validate, cast, UI (3 tabs), shared_state, server wiring, Prepare sub-tab auto-apply, cross-tab navigation (§M4, §M5)
├── edark_report.R               edark_report() — programmatic Full Report, no Shiny (§E15)
├── validate_input.R             Input guard before launch (§P2.1)
├── cast_column_types.R          Auto-cast rules at launch (§P2.2)
├── detect_column_types.R        col → "numeric" / "factor" / "datetime" / "character" (§P2.3)
├── route_plot_type.R            Type pair → plot type, Explore › Describe / Correlate (§E4)
├── build_plot_spec.R            build_univariate / bivariate / trend_plot_spec() (§E3–E5)
├── render_plot.R                All plot types; dispatches on spec$plot_type (§E8, §N4)
├── build_variable_summary.R     One-variable summary table (§E6.1)
├── stats_inference.R            THE place p-values and CIs are computed (§N2)
├── generate_report.R            generate_report() / generate_custom_report(); PPTX / DOCX / HTML assemblers (§E10–E15, §N5)
│
├── module_column_manager.R      Prepare › Columns — include / exclude (§P4)
├── module_column_transform.R    Pipeline helpers: .apply_column_transforms, .make_range_labels, .transform_spec_is_valid (§N3.4)
├── module_transform_variables.R Prepare › Transforms (§P5)
├── module_row_filter.R          Prepare › Row Filters (§P6)
├── module_prepare_confirm.R     Prepare Apply sidebar — pipeline, warnings, reset, revert (§P7)
├── module_data_preview.R        Prepare › Data Preview (§P8)
│
├── module_explore_controls.R    Explore › Describe + Correlate sidebars; shared aesthetics accordion (§E3, §E4, §E7)
├── module_trend_controls.R      Explore › Trend sidebar (§E5)
├── module_explore_output.R      Explore output panel — plot, summary, Save / Copy / Add to Custom Report / View Report (§E6)
├── module_report.R              Explore › Report — Full Report + Custom Report pills (§E10–E12)
│
├── module_analysis_main.R           Analyze orchestrator — 9-step navset_pill, progress JS handler, step gating (§A5.1, §N6.3)
├── module_analysis_setup.R          Step 1 Setup — freeze, roles, study type, model purpose + train/test split (§A5.3, §N6.4)
├── module_analysis_table1.R         Step 2 Table 1 (§A5.3)
├── module_analysis_varinvestigation.R  Step 3 Variable Investigation; shared .analysis_progress_modal() (§A5.3, §N6.5)
├── module_analysis_covariate_confirm.R Step 4 Covariate Confirmation — live writes (§A5.3, §N6.6)
├── module_analysis_modelspec.R      Step 5 Model Creation — Summary + Run Model (§A5.3, §A8.4, §N6.7)
├── module_analysis_diagnostics.R    Step 6 Diagnostics — assumptions (§A5.3, §N6.9)
├── module_analysis_performance.R    Step 7 Performance — apparent + test set (§A5.3, §N6.9a)
├── module_analysis_results.R        Step 8 Results (§A5.3, §N6.10)
├── module_analysis_export.R         Step 9 Export — stub (§A10)
│
├── analysis_utils.R                 Formula, reference levels, complete cases, covariate sample, train/test rows (§N6.2)
├── service_analysis_pipeline.R      reset_analysis_pipeline(); .default_model_design() (§A8.6, §N6.13)
├── service_analysis_validation.R    validate_analysis() — preflight (§A8, §N6.12)
├── service_analysis_models.R        Model fitting and model options (§A7, §N6.8)
├── service_analysis_summary.R       build_analysis_summary() (§N6.11)
├── service_analysis_diagnostics.R   Diagnostic options and computation (§N6.9)
├── service_analysis_performance.R   Performance options and computation (§N6.9a)
├── service_analysis_tables.R        Table 1; results table; fit statistics (§N6.10)
├── service_analysis_plots.R         Diagnostic and performance plots; forest plot
├── service_analysis_variable_selection.R  Univariable screen / stepwise / LASSO (§A9, §N6.5)
├── service_analysis_codegen.R       R script generator — stub, deferred (§A7.9)
├── service_analysis_export.R        Export assembly — stub (§A10)
│
├── data.R                       Roxygen docs for liver_tx
data/liver_tx.rda                500 × 36 synthetic liver transplant dataset (§N7)
data-raw/liver_tx_sample.R       Regenerates liver_tx (seeded): Rscript data-raw/liver_tx_sample.R
inst/report_template.Rmd         HTML report template
inst/templates/ppt_16x9_blank_template.pptx   PPTX template
```

---

## Current State

- **Prepare, Explore (Plot + Report):** built.
- **Analyze:** nine steps. Phases 0–7 and 6b complete (Setup incl. model purpose + train/test split, Table 1, Variable Investigation, Covariate Confirmation, Model Creation, Diagnostics, Performance, Results). Step 9 Export is a stub. Phase 5b (R code generator) deferred — Step 5's R Code Preview is a placeholder; it should consume `prepare_snapshot` + the spec (incl. `purpose_specification`).
- **Built 2026-09-19:** Phase 7b performance validation — Step 1 validation method (bootstrap / cross-validation / held-out test set, mutually exclusive), settings and Cancel-able runs in Model › Performance (§A1.4a, §A5.3).
- **Planned:** Phase 8 export materials (§A10, with items disabled until created — §A5.3 Step 9); Phase S session save / load / autosave (§M8).

---

## To-dos

### Doc discrepancies to resolve
Found while building `docs_mod/`. Each needs a decision: change the code or change the doc.
- **Trend "count" mode.** Old docs described a "None" trend variable giving `trend_count`, and a `trend_proportion` type. Code: the trend variable is required, and types are `trend_numeric` / `trend_factor`. §E5 documents the code. Decide whether an event-count mode is wanted.
- **Bug — factor trend summary table.** `module_explore_output.R` (~line 179) lists trend types as `trend_count` / `trend_numeric` / `trend_proportion`, so a `trend_factor` plot summarises the timestamp column instead of the trend variable. Fix: use the real type names.
- **Dead renderer.** `render_plot()` dispatches `trend_mean`, which no spec builder produces.
- **Dataset signature.** §A3.2 specifies a structural signature; Step 1 stores a sha256 hash of the data (see the note in §A3.2).
- **Type overrides without UI.** `column_type_overrides` exists in state and pipeline, but no UI sets it (§P4). Keep as a hook or remove.
- **Two Table Ones, two report systems.** Explore › Report has its own Table One (`.build_tableone_df()`) and report assemblers; Analyze has gtsummary Table 1 and a planned Step 9 report. Decide: keep both deliberately, or converge.
- **Zero baseline default.** `shared_state$trend_zero_baseline` initialises TRUE; the checkbox renders FALSE. §E5 documents FALSE.

### In progress
- Analyze Step 6 Export (Phase 8) and Phase 5b code generator — see the build plan.

### High magnitude
- Alternative plot types per variable combination (heat map, balloon plot, etc.)
- Word report: reference `.docx` template with heading styles
- Integrate studybuddy — working dataset → direct model creation and publication outputs

### Mid magnitude
- Dataset export (§P9): working dataset to RDS / CSV; original dataset + Prepare spec to RDS. Share a writer with Step 9 and sessions (§M7).
- Statistical tests in Explore › Correlate summary (num × fac → Kruskal-Wallis; fac × fac → chi-square / Fisher's) — reports already have them.
- transform → row filter → transform does not show a warning on stage.
- Warnings section in the Apply pane — mimic the "Stratify by" section header in Report › Full Report.
- Async report generation (synchronous now; cancel needs `future` / `promises`).

### Small magnitude
- Report contents option: collinearity investigation.
- `shinytest2` module tests + `testthat` unit tests.
- **Bug — centre tables in PPT + HTML reports:** `flextable::set_table_properties(align = "center")` in `.style_dataset_summary_ft()` and `.style_section_ft()` has no effect in PPT and HTML (DOCX may work).

### Analyze debugging
- Univariable screen flags a multi-level factor as suggested if *any* level term clears the threshold; a per-variable likelihood-ratio p would be more correct (`service_analysis_variable_selection.R`).
- Collinearity plot base size should scale with the number of variables; still too small with few.
- **EPV computed two ways:** Step 4 / Summary divide events by *parameters*; the validator's `PF_LOW_EPV_*` divides by *predictors* (more lenient). Pick one — parameters is the usual convention.
- **`PF_LOOKS_CATEGORICAL` may be noisy** on genuine small counts (e.g. transfusion units 0–8). Threshold `.PF_CATEGORICAL_MAX_VALUES` (10).
- **`postop_aki_stage` conflates "no AKI" with "missing"** — including it drops ~62% of rows and trips `PF_MISSING_GT50`. Consider `has_aki` + stage-among-AKI.
- LASSO has no seed (`cv.glmnet` folds are random) — needed for the Phase 5b script to reproduce the app.
- **Mixed models have no influence check** — Step 6 offers Cook's distance / leverage only for lm / glm. A cluster-level (leave-one-cluster-out) influence check would close the gap (§A11.2).
- **Nine step pills wrap to two rows** at ~1500 px. Consider shorter labels (e.g. "Variables", "Covariates") or a vertical rail.
- **Split variable choices include any factor** (e.g. `postop_aki_stage`, `transplant_center`). A split by centre is a legitimate external-style validation; nothing stops a nonsensical choice.

---

## Keeping the Docs Current

- Behaviour change → update the stage PRD (or §M if cross-stage).
- New pitfall or non-obvious mechanic → §N, in the relevant stage section.
- New to-do or discovered doc/code mismatch → this file.
- Cite sections with their prefix (§P7.2, §A8.6) in code comments and docs.
