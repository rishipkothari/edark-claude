# CLAUDE.md — EDARK v0.2

## What this is
An R package providing an interactive Shiny GUI for exploratory data analysis of tabular datasets, focused on clinical research workflows. A researcher calls `edark(dataset)`, prepares the data, explores variables interactively, and optionally exports a report.

Full spec: `PRD/PRD_0_Master.md` (plus the per-stage PRDs alongside it).

---

## How to run

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

## File map

```
R/
├── edark.R                     Entry point: validates input, casts types, builds UI+server
├── edark_report.R              Programmatic API: edark_report() — no Shiny required
├── validate_input.R            Input guard called before Shiny launches
├── cast_column_types.R         Auto-cast rules — runs once at launch
├── detect_column_types.R       Returns named char vector: col → "numeric"/"factor"/"datetime"/"character"
├── route_plot_type.R           Type combo → plot type string (Analyze tab only)
├── build_plot_spec.R           build_univariate_plot_spec() / build_bivariate_plot_spec() / build_trend_plot_spec()
├── render_plot.R               All 11 plot types; dispatches from a spec list
├── build_variable_summary.R    Summary stats table for a single variable
├── stats_inference.R           THE place p-values and CIs are computed — see "Statistical methods registry"
├── generate_report.R           Core report generation: builds sections, assembles PPT/Word/HTML
│
├── module_column_manager.R     Prepare › Columns tab — include/exclude only
├── module_column_transform.R   Pipeline helpers: .apply_column_transforms, .make_range_labels, .transform_spec_is_valid
├── module_transform_variables.R Prepare › Transforms tab — flat table, one row per numeric col
├── module_row_filter.R         Prepare › Row Filters tab
├── module_prepare_confirm.R    Apply Changes sidebar — pipeline, validation, navigation
├── module_data_preview.R       Prepare › Data Preview tab — original + working reactables + summary sub-tabs
│
├── module_explore_controls.R   Explore › Describe + Relationship tab sidebars — describe_controls_ui/server + relationship_controls_ui/server
├── module_trend_controls.R     Explore › Trend tab sidebar — timestamp/resolution/variable/stat pickers
├── module_explore_output.R     Explore main panel — plot output + summary reactable + "Add to Custom Report" / "View Report" buttons
├── module_appearance.R        Explore › Appearance panel — the app's only plot-aesthetics controls; sole writer of the five aesthetic shared_state fields
├── module_report.R             Report tab — Full Report pill (type selector, variable modal, download) + Custom Report pill (gallery, reorder, download)
│
├── ui_helpers.R                Shared UI component library — lock reasons, buttons, section labels, empty states, messages, info rows, model header, aesthetics controls
│
├── module_analysis_main.R          Analyze tab — orchestrator; 6-step navset_pill (Step 5 nests Model sub-tabs) + JS progress handler + step/sub-tab gating
├── module_analysis_setup.R         Analyze › Step 1: Setup — dataset freeze, role assignment (outcome/exposure/candidates/clusters), study type, model purpose + train/test split, reset modal with undo (Phases 1, 6b)
├── module_analysis_table1.R        Analyze › Step 2: Table 1 — gtsummary descriptive table (Phase 2)
├── module_analysis_varinvestigation.R   Analyze › Step 3: Variable Investigation — univariable screen, collinearity, stepwise/LASSO (Phase 3)
├── module_analysis_covariate_confirm.R  Analyze › Step 4: Covariate Confirmation — final covariates, reference levels, live missingness; writes to spec on every change (Phase 4)
├── module_analysis_modelspec.R     Analyze › Step 5 Model › Summary (audit) + Create (auto model type, optimizer, live preflight, fit on training rows, results) (Phase 5)
├── module_analysis_diagnostics.R   Analyze › Step 5 Model › Diagnostics — assumption checks + Run; Overview + per-check tabs (Phase 6)
├── module_analysis_performance.R   Analyze › Step 5 Model › Performance — measures + Run; Overview (one column per set of rows) + per-set tabs (Phase 6b)
├── module_analysis_results.R       Analyze › Step 5 Model › Results — output checkboxes + Generate; Summary + per-output tabs (Phase 7)
├── module_analysis_export.R        Analyze › Step 6: Export — zip assembly, preset selector, download (Phase 8)
│
├── analysis_utils.R                build_analysis_formula() / apply_reference_levels() / compute_complete_cases() / compute_covariate_sample() / analysis_split() / analysis_split_rows() / analysis_model_data() / analysis_test_data()
├── service_analysis_pipeline.R     reset_analysis_pipeline(shared_state, from_step) — clears downstream state per PRD §8.6
├── service_analysis_validation.R   validate_analysis(spec, data, tier, verbose) — all Tier 1 + Tier 2 preflight checks
├── service_analysis_models.R       Model fitting engines: lm / glm / lmerTest::lmer / lme4::glmer; model options, outcome event, stale check (Phase 5)
├── service_analysis_summary.R      build_analysis_summary() — Step 5 Summary sections, pure, reusable by export (Phase 5)
├── service_analysis_diagnostics.R  analysis_diagnostic_options() / run_analysis_diagnostics() — pure (Phase 6)
├── service_analysis_performance.R  analysis_performance_options() / run_analysis_performance() / analysis_performance_job() — apparent, held-out test set, CV, bootstrap; pure (Phases 6b, 7b)
├── service_analysis_tables.R       Table 1 (gtsummary); Model › Results table (own data.frame → gt / flextable), fit statistics (Phases 2, 7)
├── service_analysis_plots.R        ggplot figures from plain data — diagnostic plots (Phase 6); performance plots (Phase 6b); forest plot (Phase 7)
├── service_analysis_variable_selection.R  Univariable screen / stepwise / LASSO (Phase 3)
├── service_analysis_codegen.R      Reproducible R script generator (Phase 5)
├── service_analysis_export.R       Export zip assembly pipeline (Phase 8)
│
└── data.R                      Roxygen docs for built-in liver_tx dataset

data/
└── liver_tx.rda                500 × 36 synthetic liver transplant dataset (default for edark())

data-raw/
└── liver_tx_sample.R           Regenerates data/liver_tx.rda — run with Rscript; seeded, reproducible

inst/
├── report_template.Rmd         Bundled Rmd template for HTML report output
└── templates/
    └── ppt_16x9_blank_template.pptx   Bundled slide template for PPT output
```

---

## Documentation

### What goes where
- Root CLAUDE.md holds only HIGH LEVEL information about the application at a glance, plus the running TO-DO list below. No TO-DOs belong in any nested CLAUDE.md.
- Documentation information lives in `PRD/CLAUDE.md`: which documentation lives in which file, how to read it, quick references.

### Reference files
- Development reference files live in `PRD/`. See `PRD/CLAUDE.md` for the full list.
- These cover application notes, PRDs, build plans and other references. They are detailed and should be the first stop for domain-specific questions.

---

## Coding philosophy
- do not use /u2014 dashes, use hyphens or other simple ASCII characters where appropriate

---

## TO-DOs

### Prepare

#### High magnitude

#### Mid magnitude
- transform → row filter → transform does not show a warning on stage.
- Warnings section in the Apply pane — mimic the "Stratify by" section header in Report › Full Report.
- varaible labels - in Prepare phase, column in master table that has a textbox for custom column labels. Buttons to apply some function (str to title, capitalize first only, variable name) to change all labels quickly for basic presentation purposes. 

#### Low magnitude


### Explore

#### High magnitude
- Alternative plot types per variable combination (heat map, balloon plot, etc.)

#### Mid magnitude
- Word report: reference `.docx` template with defined heading styles
- Statistical tests in the Explore › Relationship summary panel (num × fac → Kruskal-Wallis; fac × fac → chi-square / Fisher's). Reports already have these via the table helpers; the Explore summary does not.
- Async report generation (synchronous now; cancel needs `future` / `promises`).

#### Low magnitude
- Report contents option: collinearity investigation.
- **Bug — centre tables in PPT + HTML reports:** `flextable::set_table_properties(align = "center")` is set in both `.style_dataset_summary_ft()` and `.style_section_ft()` in `generate_report.R`, but tables still render left-aligned in PPT and HTML (DOCX may work). Investigate `officer` slide content alignment for PPT and the Rmd template's table rendering for HTML.

### Analyze

### In progress
Phases 0–7 and 6b complete; Step 6 (Export, Phase 8) is a placeholder stub. Phase 5b code generator (`service_analysis_codegen.R`) deferred — Step 5's R Code Preview is a placeholder; it should consume `prepare_snapshot` + the spec (incl. `purpose_specification`). Phase definitions and acceptance criteria: `PRD/BUILD_Analysis.md`.
- **Performance validation follow-ups** (Phase 7b built 2026-09-19): optional shrunk-coefficient output from the bootstrap calibration slope; decision curve analysis; CV / bootstrap for mixed models with several cluster variables groups by the first one only.

#### High magnitude
- Propensity score model subtypes - matching, score adjusted, IPTW, etc

#### Mid magnitude
- Univariable screen flags a multi-level factor as suggested if *any* level term clears the threshold; an overall per-variable likelihood-ratio p would be more correct (`service_analysis_variable_selection.R`).

#### Low magnitude
- **`PF_LOOKS_CATEGORICAL` may be noisy** on genuine small counts (e.g. transfusion units 0–8). Threshold `.PF_CATEGORICAL_MAX_VALUES` (10) in `service_analysis_validation.R`.
- Collinearity plot base size should scale with the number of variables; still too small with few.
- **Mixed models have no influence check** — Model › Diagnostics offers Cook's distance / leverage for lm / glm only. A cluster-level (leave-one-cluster-out) influence check would close the gap (§A11.2).

### Other

#### High magnitude
- **UI consistency** (Stages 0, 1 and 2 done; Stages 3-6 not started): honest step-locking first, then a shared component library (`R/ui_helpers.R`), one plain-CSS theme file, a config (left) / result / info (right) page contract with a dedicated messages area, and flatter navigation. Report stays inside Explore. Scoped to `bslib` + R + CSS - no SCSS, no new JS, no shell rewrite. Decisions, assessment and stage status table: `PRD/BUILD_UI-redesign.md`. Revised 2026-09-23 from user feedback (§1.3 - principles plus per-page details): Explore's mode pills stay in the left pane and Report's Full / Custom pills join them, while Analyze's sub-steps keep underline tabs across the page (D8 amended); one aesthetics control set, in its own Appearance panel (D9, amended 2026-09-23 from dialog to panel); one button scale, placement by scope (D10); Report › Custom loses its preview pane (D11). Work one stage per session and tick off its status table.
- investigate reset pipeline and what it looks like
    - also with UI refresh, might be able to eliminate some of the click to lock in steps, should evaluate
    - **Nine step pills wrap to two rows** at ~1500 px. Consider shorter labels (e.g. "Variables", "Covariates") or a vertical rail.

#### Mid magnitude
- Export (§P9): working dataset, prepare/analyze spec, model ouptuts/results (including diagnostics). Formats for results would be individual files vs single document/report (select output type word, pdf, HTML). Zip all files. Share a writer with Step 9 and sessions (§M7).

### Low magnitude
- `shinytest2` module tests + `testthat` unit tests.
