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
├── module_prepare_confirm.R    Prepare config pane (Apply/Reset) + info pane (dimensions, itemised pending list) + messages; pipeline, validation, navigation
├── module_data_preview.R       Prepare › Data Preview tab — two toggles (Original/Working, Data/Summary) over one of four reactables
│
├── module_explore_controls.R   Explore › Describe + Relationship tab sidebars — describe_controls_ui/server + relationship_controls_ui/server
├── module_trend_controls.R     Explore › Trend tab sidebar — timestamp/resolution/variable/stat pickers
├── module_explore_output.R     Explore result pane — plot + action toolbar; variable summary and custom-report state go to the info pane
├── module_appearance.R         Explore › Appearance panel — the app's only plot-aesthetics controls; sole writer of the five aesthetic shared_state fields
├── module_report.R             Report tab — Full / Custom underline tabs; Full has a config pane + resolved section list, Custom has no centre (D11)
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
├    ├── ppt_16x9_blank_template.pptx   Bundled slide template for PPT output
    └── word_docx_blank_template.docx  Bundled Word template for DOCX output - Title,
                                       Subtitle and heading 1-9 styles; the TOC and the
                                       section furniture are built in .assemble_docx()
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
- do not commit without permission
- if you are instructed to commit, add a message of at most 6 sentences, be brief. also, push after commits
- remind me to push after commits

---

## TO-DOs

### Prepare

#### High magnitude

#### Mid magnitude
- ~~transform → row filter → transform does not show a warning on stage~~ - closed
  2026-09-24. Root cause was one line shared by `.build_prepare_warnings()` and
  `.prune_conflicting_filter_specs()`: both derived the changed-transform set from
  `names(specs)`, the *currently staged* transforms, so a transform that had been
  REMOVED since the last Apply was never tested. Worst case was cutpoints -> filter on
  the bands -> remove the cutpoints: the categorical filter survived onto a column that
  was numeric again, matched no rows, and Apply produced an empty dataset with no
  warning. Both now use `union(names(specs), names(last_tx))`, and
  `.apply_row_filters()` skips a filter whose `type` disagrees with the column as a
  backstop.
- Warnings section in the Apply pane — mimic the "Stratify by" section header in Report › Full Report.
- varaible labels - in Prepare phase, column in master table that has a textbox for custom column labels. Buttons to apply some function (str to title, capitalize first only, variable name) to change all labels quickly for basic presentation purposes.

#### Low magnitude


### Explore

#### High magnitude
- Alternative plot types per variable combination (heat map, balloon plot, etc.)
- report -> full report main panel - should this contain a viewer for the file that is generated? and then a save button to export the report to a desired location? solves the "main panel sucks" issue

#### Mid magnitude
- ~~Word report: reference `.docx` template with defined heading styles~~ - closed
  2026-09-24. `inst/templates/word_docx_blank_template.docx` now supplies the
  Title / Subtitle / heading 1-9 styles, and `.assemble_docx()` builds a real
  document on top of them: title page, a Word TOC field that populates from the
  headings (heading 1 = Table 1 / Dataset Summary / the section group, heading 2 =
  each variable), a running header naming the document, a page number bottom-right,
  and four page sections so the dataset summary is landscape and everything else
  portrait. Per-variable summary tables are laid out at 18pt. Two things worth
  knowing: Word's NUMPAGES field counts *within a section*, so the footer is
  "Page N" and not "Page N of M"; and Word's own table autofit wrecks a table
  wider than the page, so `.docx_fit_ft()` computes the widths in R and
  `.docx_shrink_widths()` takes the overflow out of the widest columns only.
- Statistical tests in the Explore › Relationship summary panel (num × fac → Kruskal-Wallis; fac × fac → chi-square / Fisher's). Reports already have these via the table helpers; the Explore summary does not.
- Async report generation (synchronous now; cancel needs `future` / `promises`).
- when changing LHS pills in explore data from describe to corelate and then clicking plot relationship button, secondary variable chosen for plot is the secondary variable in the correlate LHS pane; primary and stratify by are still left over from the last selection in the describe pill.
- when going from correlate back to describe, it uses the primary and stratify by variables in correlate; i think we need to reassign the state variables on pill change/click
- Custom Report's config pane now holds only Output Format + Generate, so it has room for a "Report Contents" box like Full Report's (Dataset Summary, Table One). Probably a shared component between the two rather than two copies.
- **Drag-and-drop reordering of Custom Report items.** The list is in the centre and reorders via the toolbar's Move Up / Move Down, which needs no JS. Drag would need `sortable` (a SortableJS wrapper) attached to the row container - `sortable_js()`, not `rank_list()`, which is text-labels-only. The fiddly part is not the drag: it is that the drop rewrites the DOM while `renderUI` re-renders from `shared_state$custom_report_items`, so the input -> server reorder -> re-render round trip has to land on the same order or the row snaps back. Needs `chromote` to verify.
- generate full report spinner counts to 7 twice for word and powerpoint report format but not HTML: once with "variable #" then with "section #"

#### Low magnitude
- Report contents option: collinearity investigation.
- **Bug — centre tables in PPT + HTML reports:** `flextable::set_table_properties(align = "center")` is set in both `.style_dataset_summary_ft()` and `.style_section_ft()` in `generate_report.R`, but tables still render left-aligned in PPT and HTML (DOCX may work). Investigate `officer` slide content alignment for PPT and the Rmd template's table rendering for HTML.
- appearance should be a pill next to explore data and report; full screen for config; this may change to "settings" later but we can leave it as appearance for now. main panel will house container for settings.
en creating a report should only contain variables that are selected/included in report; all selected variables plus a stratify by variable if selected
ll selected variables plus a stratify by variable if selected
ll selected variables plus a stratify by variable if selected
ll selected variables plus a stratify by variable if selected
all selected variables plus a stratify by variable if selected

### Analyze

### In progress
Phases 0–7 and 6b complete; Step 6 (Export, Phase 8) is a placeholder stub. Phase 5b code generator (`service_analysis_codegen.R`) deferred — Step 5's R Code Preview is a placeholder; it should consume `prepare_snapshot` + the spec (incl. `purpose_specification`). Phase definitions and acceptance criteria: `PRD/BUILD_Analysis.md`.
- **Performance validation follow-ups** (Phase 7b built 2026-09-19): optional shrunk-coefficient output from the bootstrap calibration slope; decision curve analysis; CV / bootstrap for mixed models with several cluster variables groups by the first one only.

#### High magnitude
- Propensity score model subtypes - matching, score adjusted, IPTW, etc

#### Mid magnitude
- Univariable screen flags a multi-level factor as suggested if *any* level term clears the threshold; an overall per-variable likelihood-ratio p would be more correct (`service_analysis_variable_selection.R`).
- **Covariates and Model › Summary have config panes with nothing to configure.** Both pages keep their configuration in the table (Covariates) or have none at all (Summary), so after the Stage 4 page contract their left panes carry orientation text rather than controls. Honest but thin. Either give them real global controls - Covariates has an obvious candidate in table-level Select all / Clear, and a search - or decide those two pages are a deliberate exception to D6 and say so in the plan.

#### Low magnitude
- **`PF_LOOKS_CATEGORICAL` may be noisy** on genuine small counts (e.g. transfusion units 0–8). Threshold `.PF_CATEGORICAL_MAX_VALUES` (10) in `service_analysis_validation.R`.
- Collinearity plot base size should scale with the number of variables; still too small with few.
- **Mixed models have no influence check** — Model › Diagnostics offers Cook's distance / leverage for lm / glm only. A cluster-level (leave-one-cluster-out) influence check would close the gap (§A11.2).
- generate table 1 spinner - specify which table its working on, e.g. if it has 3 to generate (overall, by exposure, by outcome) have 3 stops on the bar and change text to say which is being created
- need to think about what we want table 1 RHS to show; for now, it doesn't accurately reflect what it's stratifying by, it just picks one of the vars i think maybe exposure by defualt?
- **Setup and Covariates open with the info pane folded** (`info_open = "closed"` in their `edark_page()` calls). Both centres are wide one-row-per-variable tables and at 1280 px they were too tight with both panes open, so this was the Stage 4 viewport fallback. Worth re-checking at your usual window size: if there is room, drop the argument so they match every other page.

### Other

#### High magnitude
- **UI consistency - built 2026-09-23, one decision open for you.** All six stages of
  `PRD/BUILD_UI-redesign.md` are done: honest step-locking, a shared component library
  (`R/ui_helpers.R`), one plain-CSS theme file (`inst/www/edark.css`), a config (left) /
  result / info (right) page contract with a dedicated messages area, and flatter
  navigation. Report stays inside Explore. `bslib` + R + CSS only - no SCSS, no new JS.
  Explore › Report's Full / Custom are underline tabs (level 3b), not the config-pane pills
  D8 originally named - **ruled 2026-09-23: they stay underlines**, because that is the third
  nested level and consistency at a level beats the D8 wording. See Stage 5's build note in
  `PRD/BUILD_UI-redesign.md`.
- investigate reset pipeline and what it looks like
    - also with UI refresh, might be able to eliminate some of the click to lock in steps, should evaluate
    - ~~Nine step pills wrap to two rows~~ - closed 2026-09-23: there are six steps, and with
      "3 · Variables" / "4 · Covariates" they fit one row at 1280 px (Stage 5).
- ~~RHS pane is tied to the main pane, where the LHS pane is independent; I wanted three
  independent panes~~ - closed 2026-09-23. Root cause was not the pane structure: bslib
  ships `.bslib-card .card-body { max-height: var(--bslib-card-body-max-height, none) }`,
  two classes to `.edark-scroll-table`'s one, so any scroll cap put directly on a
  `card_body` lost on specificity and the content grew without limit. That blew out the
  CSS grid row the centre and info panes share, stretching the info pane to match (1660 px
  on Prepare › Columns) and forcing the whole document to scroll. Capping the content -
  never on the card_body itself - fixes all three panes at once. Convention and the three
  containment mechanisms are in the header comment on `.edark-scroll-table`
  (`inst/www/edark.css`) and `EDARK_RESULT_HEIGHT` (`R/ui_helpers.R`).

#### Mid magnitude
- Export (§P9): working dataset, prepare/analyze spec, model ouptuts/results (including diagnostics). Formats for results would be individual files vs single document/report (select output type word, pdf, HTML). Zip all files. Share a writer with Step 9 and sessions (§M7).

### Low magnitude
- `shinytest2` module tests + `testthat` unit tests.
- **Install Rtools 4.5 and get `devtools::check()` to 0/0/0.** `devtools::check()`
  currently dies at "Could not find tools necessary to compile a package" - Rtools is
  not installed (https://cran.r-project.org/bin/windows/Rtools/). The package has no
  compiled code, so the gate can be skipped with
  `options(buildtools.check = function(action) TRUE)`, but installing Rtools is the real
  fix. With the gate skipped on 2026-09-24 the check ran 0 errors, 2 warnings, 1 note;
  the roxygen errors are closed (see below) and what remains is undeclared imports -
  `@importFrom` for the `stats` / `utils` functions used (`median`, `sd`, `IQR`,
  `na.omit`, `quantile`, `setNames`, `modifyList`, `str`, ...) plus a
  `utils::globalVariables()` entry for `.data` and the NSE column names.
- ~~roxygen errors on every `devtools::document()`~~ - closed 2026-09-24. Two unrelated
  causes. (1) `DESCRIPTION` sets `Roxygen: list(markdown = TRUE)`, and markdown mode
  escapes `%` for you, so a hand-written `\%` came out of roxygen as `\\%` - a literal
  backslash followed by an Rd comment that ate the rest of the line, including the
  closing `}` of the `\item{}` it sat in. That is what made `man/liver_tx.Rd` report
  every later `\item` as an unknown macro and every later section header as unexpected,
  and what roxygen called mismatched braces in `stats_inference.R`. Write a plain `%` in
  roxygen comments. (2) Markdown links like `[edark_run_gate()]` become real `\link{}`
  cross-references, but every helper in `R/ui_helpers.R` is `@keywords internal` +
  `@noRd` and so has no man page to link to. Undocumented internals are referred to with
  a code span - `` `edark_run_gate()` `` - not a link.
