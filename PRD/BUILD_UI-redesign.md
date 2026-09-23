# EDARK v0.2 - UI Consistency Plan

> The single UI plan. It merges the Claude assessment and the competing Codex assessment
> (the Codex document is kept at `archive/BUILD_UI-redesign_CODEX.md` for history only).
> Work one stage per session and update the status table below as part of each stage.
>
> **Scope rule:** this is an academic project, not a shipped product. Every stage is
> achievable with `bslib` + plain R + plain CSS. **No SCSS / Sass and no build step.** CSS
> lives in one file (`inst/www/edark.css`); it may grow past the original ~80-line estimate
> when a rule is genuinely needed, but prefer a Bootstrap utility class or a `bslib` argument
> first. **Zero new JavaScript.** The existing reactable-embedded-input JS (§N1.4) and the
> progress-message handlers are the only JS and must not be touched.

## Status

| Stage | Scope | Effort | Status |
|---|---|---|---|
| 0 | Quick fixes that do not wait for the redesign | S | done 2026-09-22 (2 of 3, see §4) |
| 1 | Honest locking and one precondition affordance | S-M | not started |
| 2 | Component library (`R/ui_helpers.R`) + Explore report aesthetics | M | not started |
| 3 | Theme file, dark mode, nav polish (navbar, pills, stepper, font) | S-M | not started |
| 4 | Page contract: config / result / info panes + messages area | M-L | not started |
| 5 | Flatten navigation + one nav vocabulary (§1.2) | M | not started |
| 6 | Small fixes: empty states, density, copy | S | not started |

Order: 1 first (the highest-value fix, and the user's priority). 2 and 3 are independent of
each other. 4 depends on 2. 5 is independent but touches `edark.R` and
`module_analysis_main.R` routing. 6 depends on 2.

No screenshot baseline is needed before starting (decision D4).

---

## 1 - Decisions

Settled 2026-09-22. Do not reopen without the user.

| # | Decision |
|---|---|
| D1 | **Reports stay separate and stay where they are.** Explore › Report remains a sub-tab of Explore; it is *not* promoted to a top-level tab. Analyze › Step 6 Export is a different thing with a different job (see §1.1). The two share no UI. |
| D2 | **Keep dedicated areas for config and for "what this results in".** Settings go in a left sidebar; a right-hand info pane says what the current settings produce (sample size, pending changes, counts, checks). This generalises what Setup and Covariates already do. See Stage 4. |
| D3 | **A dedicated messages area, separate from the info pane.** Warnings, errors, blockers and stale notices always appear in the same place, and never mixed into the neutral info pane. |
| D4 | **Honest locking first.** Stage 1. No screenshot baseline. |
| D5 | **CSS only.** No SCSS. More CSS is acceptable if needed. |
| D6 | **Sidebars on every page, same default width.** Including Model › Summary and Step 6 Export. Left config sidebar: 340 px. Right info pane: 300 px. Both are constants in `R/ui_helpers.R`. |
| D7 | **Explore's report uses the aesthetics on screen.** Report must not have its own aesthetics controls. See Stage 2. |
| D8 | **One navigation vocabulary for the whole app** (decided 2026-09-23): each nav level has one look everywhere - including Explore's Describe / Correlate / Trend, which stop being pills inside a sidebar and become sub-steps like Analyze Step 5's. Sub-steps use **underline tabs across the top of the page** (option A, decided 2026-09-23). See §1.2. |

### 1.1 Explore report vs Analyze export (D1)

| | Explore › Report | Analyze › Step 6 Export |
|---|---|---|
| What it is | A compiled document of plots and summary tables | The outputs of one analysis |
| Modes | **Full** (prespecified: every selected variable, fixed layout) and **Custom** (user-curated items added from Explore) | Individual files **and** a compiled document |
| Output | One PPTX / DOCX / HTML file - compilation only | A zip of individual files (data, spec, tables, figures, diagnostics) plus an optional compiled report |
| Lives in | Explore (sibling of Plot) | Analyze, last step |

Both pages follow the same page contract (Stage 4). Sharing low-level writers (flextable
styling, file assembly) below the UI layer is fine; sharing screens is not.

### 1.2 Navigation vocabulary (D8)

Today the app uses five nav looks, and the same level is drawn differently in each stage:

| Level | Meaning | Prepare | Explore | Analyze |
|---|---|---|---|---|
| 1 | Stage | navbar | navbar | navbar |
| 2 | Page within a stage | card tabs (Columns / Transforms / Filters / Preview) | plain tabs (Plot / Report) | pills (Steps 1-6) |
| 3 | Sub-step / mode of a page | - | **pills inside the sidebar** (Describe / Correlate / Trend); pills in the main panel (Report: Full / Custom) | **pills inside pills** (Step 3); **underline tabs** (Step 5) |
| 4 | Views of one result | tabs inside card tabs (Data Preview) | - | card tabs (Diagnostics, Performance, Results) |

Explore's sidebar pills, Report's Full / Custom pills and Analyze Step 3 / Step 5 sub-steps are
the same kind of thing - a mode of the page that changes both the settings and the output -
and are drawn three ways.

**Decided: one look per level, everywhere.**

| Level | One look | Notes |
|---|---|---|
| 1 Stage | navbar | Restyled in Stage 3 (light bar, active underline). |
| 2 Page | **pills**, in all three stages | Analyze's pills also get stepper states (number, done, current, locked - Stage 1 sets the state, Stage 3 styles it). Prepare and Explore pills are unnumbered: their pages are not a gated sequence. |
| 3 Sub-step | **underline tabs across the top of the page** (A) | Applies to Explore (Describe / Correlate / Trend), Explore › Report (Full / Custom), Analyze Step 3 (Univariable / Collinearity / Stepwise-LASSO) and Step 5 (Summary / Create / Diagnostics / Performance / Results). No pills at this level and no nav inside a sidebar. |
| 4 Result view | card tabs, only here | Data Preview's inner tabs are removed (Stage 5). |

**Level 3 look - decided 2026-09-23: A.** Options considered:

- **A. Underline strip across the top of the page (chosen).** Matches Step 5 today. For Explore, the
  strip sits above the page layout; because Explore has one shared output panel, the strip
  drives a `navset_hidden()` in the sidebar via `nav_select()` (pure R) rather than each
  sub-step owning a whole page. Smallest change for Analyze.
- **D. Sections in the left sidebar** (the user's idea, 2026-09-22; not chosen, kept for reference).
  Each sub-step is a collapsible section (`bslib::accordion(multiple = FALSE)`) holding that
  sub-step's settings and its own primary button; the open section decides what the centre
  shows; the right info pane stays fixed for the whole page ("what this step hands on").
  Fits Explore most naturally (it is nearly what Explore does today, minus the pills).
  Costs: each Analyze sub-step module splits into a config part and a result part
  (`module_analysis_modelspec.R` already is); sub-step locking moves into the section body;
  the "one primary action" rule becomes one per open section; Model › Summary has almost no
  settings; check long sections (Performance, LASSO) at 1280 x 800.

(Earlier options B - a radio mode selector for Step 3 only - and C - promoting sub-steps to
steps, bringing back nine pills - were dropped.)

---

## 2 - Assessment

*(The durable part of this document. Line numbers are as of 2026-09-21 and drift; search
for the quoted code if a line has moved.)*

### 2.1 What already works (keep it)

- Prepare, Explore and Analyze are distinct tasks; Analyze is a gated, ordered workflow.
- Computation happens on an explicit action, not on every input change.
- Modules talk through `shared_state`, not through each other's UI.
- Setup and Covariates put configuration in the table where it belongs (one row per
  variable) and a live summary beside it. D2 makes this the pattern for every page.
- The same plot and statistics services drive both the app and the exported output.

### 2.2 No page contract

| Symptom | Evidence |
|---|---|
| Sidebar side flips mid-workflow | `module_analysis_setup.R:138` and `module_analysis_covariate_confirm.R:147` use `position = "right"`; every other page uses left |
| Sidebar vanishes | Model › Summary (`module_analysis_modelspec.R:80`) and Step 6 (`module_analysis_export.R:18`) have none |
| Six sidebar widths | 400 (Prepare, Explore), 380 (Report), 405, 390, 360, 340 - three different widths inside Step 3 alone (`module_analysis_varinvestigation.R:127,164,186`) |
| Config and info mixed in one sidebar | Setup's right sidebar holds config (action buttons, study type, purpose) *and* info (incoming snapshot, role summary, selected snapshot) (`module_analysis_setup.R:140-148`). Prepare's Apply pane holds info (dimensions), warnings, status and actions in one stack (`module_prepare_confirm.R:26-56`) |
| Four main-panel idioms in one tab strip | Prepare's sub-tabs are a `card` (`module_column_manager.R:18`), a bare `div` whose card appears at render time (`module_transform_variables.R:30` vs `:130`), a flat `tagList` (`module_row_filter.R:20`) and a nested `navset_card_tab` (`module_data_preview.R:19`) |

### 2.3 Navigation depth

- **Data Preview is 3 tab levels deep** (navbar > `prepare_tabs` > `navset_card_tab` > `navset_tab`).
- **Analyze › Model › Diagnostics is 9 containers deep.**
- **Three looks for one concept (sub-step / mode):** Explore's modes are pills inside the
  sidebar (`edark.R:150`), Report's are pills in the main panel (`module_report.R:47`), Step 3's
  are pills inside the step pills (`module_analysis_varinvestigation.R:116`), Step 5's are
  underline tabs (`module_analysis_main.R:64`). See D8 / §1.2.
- **Three looks for one level (page within a stage):** card tabs in Prepare (`edark.R:112`),
  plain tabs in Explore (`edark.R:142`), pills in Analyze.
- **Pill styling reaches one place only.** The only nav CSS (`edark.R:48-75`, from commit
  `63ced12`) is scoped to `.sidebar .nav-pills`, so it styles Explore's sidebar pills and
  nothing else; Analyze's step pills and the navbar are stock Flatly.
- **Step pills wrap to two rows** at ~1500 px (long labels, e.g. "3 · Variable Investigation").

(Report being a sub-tab of Explore was listed here as a problem in the first assessment. It
is intended - D1.)

### 2.4 Locking and state - the biggest functional gap

`.apply_gate()` (`module_analysis_main.R:146-165`) adds Bootstrap's `disabled` class and a
native `title=` tooltip to the parent `<li>`. No app CSS styles `.disabled`, so a locked step
is grey text with `pointer-events: none`: clicking it does *nothing*, and the tooltip appears
only after ~1 s hover.

- Lock wording disagrees with the in-panel placeholder for the same condition: tooltip says
  "Model › Create" (`module_analysis_main.R:135`), placeholders say "the Create tab"
  (`module_analysis_diagnostics.R:179`, `module_analysis_performance.R:364`,
  `module_analysis_results.R:163`).
- **Two affordances for one kind of precondition.** Run is disabled via `shinyjs::disabled()`
  in Step 3 (`:139`, `:201`) and Create (`module_analysis_modelspec.R:106`), but Table 1
  (`:29`), Diagnostics (`:64`), Performance (`:67`) and Results (`:66`) stay enabled and fail
  with a toast.
- **Four status vocabularies** for one severity scale: `alert-*` blocks
  (`module_prepare_confirm.R:125,131,159`), `badge bg-*` (`module_row_filter.R:84-90`),
  `card(class = "border-warning")` (`module_explore_output.R:98-106`) and transient toasts
  (`module_prepare_confirm.R:247`, `edark.R:290`).
- **Staged vs applied is invisible in Prepare.** A staged transform looks identical to an
  applied one (`module_transform_variables.R:104-128`); the pending badge is a bare count
  (`module_prepare_confirm.R:121-136`); blocking validation is a 6-second toast plus a
  forced tab switch (`:245-252`).
- ~~False warning about clearing custom report items~~ - fixed in Stage 0.

### 2.5 Duplication - the cause, not the symptom

No shared UI layer, so every convention is re-typed and drifts.

| Duplicated thing | Copies |
|---|---|
| Uppercase section label `"text-muted small text-uppercase fw-semibold mt-2 mb-1"` | Re-typed ~30x across 11 modules, plus four identical private `.hdr()` helpers (`module_analysis_modelspec.R:92`, `_diagnostics.R:49`, `_performance.R:56`, `_results.R:44`), plus an unused canonical `.sidebar_label()` (`module_explore_controls.R:86-88`), plus Prepare's variant `"mt-2 mb-1 fw-semibold"` (`module_prepare_confirm.R:29`) |
| Aesthetics accordion | 4 copies: `module_explore_controls.R:16-54`, `module_trend_controls.R:55-91`, `module_report.R:132-168` and `:203-239`. The Report copies use `custom_*` ids and are applied at generation time (`module_report.R:836-840`), so the report does not match what Explore showed (D7) |
| Model header card | 4 near-duplicates with different fields: `module_analysis_modelspec.R:380-398`, `_diagnostics.R:185-192`, `_performance.R:370-386` (no formula), `_results.R:170-176` |
| Empty state | Six grammars: `.ms_placeholder()` (`module_analysis_modelspec.R:474-478`), hand-rolled divs in Steps 2-4, no icon in collinearity (`:496-499`), card-with-header in Step 1 (`module_analysis_setup.R:517`), centered stub in Step 6 (`module_analysis_export.R:21-25`), full-width alert in Step 3 tier 1 (`:21-24`) |
| "Fit a model first" | Five wordings (`module_analysis_main.R:135`, `diagnostics.R:108,179`, `performance.R:123,364`, `results.R:163`, `modelspec.R:305`) in two classes (`text-muted` vs `text-danger`) |
| Custom-report modal | Two copies (`module_prepare_confirm.R` and `edark.R`) - merged into one helper in Stage 0 |

Button grammar drifts the same way: `btn-primary w-100`, `w-75` (`module_report.R:63`),
`btn-sm btn-outline-primary` (`module_row_filter.R:30`), unclassed `input_task_button`
(`module_trend_controls.R:50`); labels from "Generate Table 1" to a bare "Run"
(`module_analysis_varinvestigation.R:204`); Generate at the *top* of Full Report
(`module_report.R:60-64`) but the *bottom* of Custom Report (`:259-263`).

### 2.6 Interaction-model collisions

- **Explore stacks staged and live controls with no distinction.** Variable pickers are
  staged until Describe is clicked (`module_explore_controls.R:181-185`); the aesthetics
  accordion directly below applies live (`module_explore_output.R:112-135`).
- **Explore has no empty state.** Before any plot: an empty 500 px card, an empty summary
  card, and four enabled buttons that answer with a JS `alert()` (`:51`), a thrown download
  error (`:207`) or a toast (`:235`).
- **Controls far from their effect.** The row-count badge scrolls away as filters accumulate
  (`module_row_filter.R:36,40`); a long warnings list pushes Prepare's Apply below the fold
  (`module_prepare_confirm.R:26-56`).
- **No scroll containment** on the column manager (`module_column_manager.R:89-98`) or the
  transform table (`:130-139`); "Select all" scrolls away with the header.
- ~~Collinearity "Threshold" label with no control~~ - fixed in Stage 0.

### 2.7 Visual / theming

- Inline `tags$style` in three places: `edark.R:48-99`, `module_analysis_modelspec.R:41-56`,
  and a global `.form-check` override inside a *render function* (`module_column_manager.R:91-95`).
- Dark mode swaps the whole bootswatch preset (`flatly` <-> `darkly`, `edark.R:342-355`).
- Navbar controls are `rgba(255,255,255,0.75)` on primary - low contrast (`edark.R:90-98`).
- Amber means "transformed" in Data Preview (`module_data_preview.R:48`), "type changed" in
  the column manager (`module_column_manager.R:81`) and "warning" in four other places.

---

## 3 - Not doing

- A persistent left step rail or custom app shell (a router replacing `nav_select()`). The
  first Claude draft proposed one; both assessments rejected it: too much churn, and it
  crowds the 1280 x 800 viewport (§M9.4 NF-05). Stage 4's right info pane is a standard
  `bslib` sidebar, not a shell.
- SCSS / a token build step (D5).
- Promoting Report to a top-level tab (D1).
- A screenshot baseline (D4).
- A density toggle, virtualised tables, or a full WCAG audit. (Focus visibility and the
  navbar contrast fix are in scope.)

---

## 4 - Stages

Each stage is independently runnable and leaves the app working.

### Stage 0 - Quick fixes (done 2026-09-22)

- [x] **False custom-report warning.** The modal said Prepare changes "will clear custom
  report items" and offered "Apply and Clear Custom Report"; nothing clears them. Items store
  only a plot spec and are re-drawn from the working dataset when the custom report is
  generated. The copy now says so, the buttons say "Apply Changes" / "Reset to Original", and
  the two modal copies (`module_prepare_confirm.R`, `edark.R`) share one helper,
  `.custom_items_modal()`.
- [x] **Collinearity "Threshold" label** removed - it headed static text with no input. The
  0.7 cut-off is fixed in `service_analysis_variable_selection.R`; if it should become
  configurable, that is an Analyze feature, not a UI fix.
- [ ] **One "fit a model first" wording** - folded into Stage 1's lock-reason table.

### Stage 1 - Honest locking

Pure R plus the first few lines of `inst/www/edark.css`.

- **Lock-reason table.** One named character vector in `R/ui_helpers.R` (created in this
  stage with only what locking needs) holding every "do X first" message. The nav tooltip,
  the in-panel placeholder and the disabled-button reason all read from it, so they cannot
  disagree. Wording rule: name the destination exactly as the nav shows it ("Model › Create").
- **A locked step explains itself.** Keep `.apply_gate()` for state. Replace the native
  `title=` with `bslib::popover()` on the nav item so a *click* shows the reason. Create
  `inst/www/edark.css` (loaded via `shiny::addResourcePath("edark", system.file("www",
  package = "edark"))` + a `tags$link`) with a `.nav-link.disabled` treatment: lock glyph,
  `cursor: not-allowed`, and **not** `pointer-events: none` so the click reaches the popover.
  If `.apply_gate()` needs to stop the click navigating, do it in R (re-select the previous
  step), not with new JS.
- **Disabled-with-reason is the only precondition affordance.** `edark_run_button(id, label,
  enabled, reason)`: disabled when a precondition is unmet, with the reason shown as small
  text directly under the button (not only in a tooltip). Apply it to Table 1, Diagnostics,
  Performance and Results (currently enabled-then-toast) and to the already-disabled Step 3
  and Create buttons. Remove the validate-on-click toasts (`module_analysis_table1.R:233`,
  `module_analysis_modelspec.R:314`).
- **Step states for the Analyze pills.** Alongside `disabled`, `.apply_gate()` (or a sibling)
  adds `edark-step-done` to a step whose output exists and is current, from R. Stage 3 styles
  the states; until then the class is harmless.
- **Toasts only confirm.** `showNotification()` is kept for transient success ("Added to
  report", "Reset to original"). Any error or warning that toasts today moves to the
  messages area (Stage 4) - until then, to inline text beside the control.

**Done when:** clicking every locked step shows a reason; every Run button with an unmet
precondition is disabled with visible reason text; `grep` finds each "do X first" string
once, in `R/ui_helpers.R`.

### Stage 2 - Component library + Explore report aesthetics

Extend `R/ui_helpers.R`. Helpers return tag objects only - no reactive state, no module
servers. Names indicative:

| Helper | Replaces |
|---|---|
| `edark_section_label(text)` | ~30 re-typed label strings, the four `.hdr()` copies, `.sidebar_label()`, Prepare's variant |
| `edark_empty_state(icon, title, body)` | the six empty-state grammars |
| `edark_message(level, text, detail)` | alerts, badges and bordered cards used as status. Levels: `ok`, `info`, `warn`, `error`, `pending`, `stale`, `locked` - mapped to Bootstrap utility classes |
| `edark_info_row(label, value)` | the hand-built label/value rows in the Setup, Covariates and Prepare summaries |
| `edark_model_header(result, fields)` | the four model header cards; union of fields, show what applies |
| `edark_aesthetics_controls(ns)` | the four aesthetics accordions |
| `edark_run_button()` | (from Stage 1) |

**Explore report aesthetics (D7).** Delete both aesthetics accordions from `module_report.R`
and the `custom_*` aesthetic inputs. Full Report generates with the aesthetics currently set
in Explore (`shared_state$color_palette`, `ggplot_theme`, `legend_position`, ...). Custom
Report items already snapshot a `plot_spec`, but (a) Report's `custom_*` controls override it
at generation (`modifyList()` in `.build_custom_report_sections()`, `generate_report.R:1074`),
and (b) the snapshot is `shared_state$plot_specification`, which may predate live aesthetic
changes made after the plot was drawn. Fix both: at Add time write the aesthetics in force
into the item's spec (`module_explore_output.R:230-256`), and have the app call
`generate_custom_report()` without report-level aesthetics so each item looks exactly as it
did on screen. `edark_report()` / `generate_custom_report()` keep their aesthetic arguments
for programmatic use.
Update §E (PRD_2_Explore.md) in the same change.

**Done when:** `grep` for `"text-uppercase fw-semibold"`, `\.hdr <- ` and the aesthetics
accordion body each return one hit, in `R/ui_helpers.R`; a report generated from Explore
matches the on-screen plot styling. App otherwise looks unchanged.

### Stage 3 - Theme file

Extend `inst/www/edark.css`:

- CSS custom properties on `:root` and `[data-bs-theme="dark"]`: the status colours and four
  column-type colours (`--edark-type-{numeric,factor,datetime,character}`), resolving the
  "amber means three things" problem by naming.
- **Navbar:** a calm bar instead of Flatly's solid primary - body background, 1 px bottom
  border, nav links in the secondary text colour, the active stage in primary with a 2 px
  primary underline. This also fixes the theme / debug button contrast. (Bar colour may be
  set with `page_navbar(navbar_options = ...)` instead of CSS.)
- **Pills (level 2):** promote the existing rule at `edark.R:52-75` from `.sidebar .nav-pills`
  to all level-2 pills - rounded, tertiary background with border when inactive, primary fill
  when active.
- **Analyze stepper states:** current = primary fill; done (`edark-step-done`) = light primary
  tint with a check glyph; locked (`.disabled`) = muted, lock glyph, `cursor: not-allowed`.
  Step numbers stay in the labels.
- **Level 3 and 4 tabs:** one font weight (500) and one active colour (primary) for the
  sub-step idiom and card tabs, so all nav reads as one family; slightly tighter nav padding.
- **Typography:** `bs_theme(base_font = bslib::font_collection("system-ui", "-apple-system",
  "Segoe UI", "Roboto", "sans-serif"))` - the native OS font, works offline. (Avoid
  `font_google()`: it needs internet on first launch, a problem on locked-down hospital
  machines.)
- **Motion and focus:** `transition: background-color .15s, color .15s` on nav links;
  visible `:focus-visible` outline on every interactive element.
- Scroll containment for the column manager and transform table (`max-height`,
  `overflow: auto`, `position: sticky` header).
- Pane styling for Stage 4 (info pane background, messages area spacing).

Also:

- Replace the `flatly <-> darkly` swap (`edark.R:342-355`) with one preset plus
  `bslib::input_dark_mode()` (`bslib >= 0.7.0` is already required).
- Move the inline `tags$style` blocks into the file and delete the leak inside the render
  function (`module_column_manager.R:91-95`).

**Done when:** dark mode toggles on every page with no layout shift or change of identity;
no `tags$style` remains inside a render function.

### Stage 4 - Page contract

Every page has the same four places. This is D2 + D3 + D6 made concrete.

```
+--------------+-------------------------------------+-------------+
| CONFIG       | MESSAGES (only when there are any)  | INFO        |
| left sidebar |  warnings, errors, blockers, stale  | right pane  |
| 340 px       +-------------------------------------+ 300 px      |
|              |                                     |             |
| required     | RESULT                              | what the    |
| optional     |  the one artefact this page         | current     |
| advanced >   |  produces (plot, table, model)      | settings    |
|              |                                     | produce     |
| [Primary]    |  - or a config table (see below)    |             |
+--------------+-------------------------------------+-------------+
```

- **Config (left sidebar, 340 px).** Inputs grouped required -> optional -> advanced
  (accordion), then **one** primary action at the bottom, full width, labelled verb + object
  ("Fit Model", never "Run").
- **Result (centre).** The one artefact the page produces. Table-shaped configuration stays
  here when it is one row per variable - Setup roles, Covariates, Prepare's column and
  transform tables. Its table-level controls (Include all / Clear, search, legend) go in the
  left sidebar. **Do not re-render these reactables:** the patch-don't-re-render contract
  (§N1.4) and the `MutationObserver` wrappers must survive.
- **Info (right pane, 300 px).** Neutral, factual, live: what the current settings produce.
  Never inputs, never warnings. A standard `bslib::sidebar(position = "right")` in a nested
  `layout_sidebar`, collapsible with bslib's own toggle.
- **Messages (top of the centre column).** One `edark_messages_ui(id)` slot per page,
  rendering `edark_message()` items. Empty = takes no space. Every warning, error, blocker
  and stale notice on the page goes here and nowhere else.

Per page:

| Page | Config (left) | Result (centre) | Info (right) | Messages |
|---|---|---|---|---|
| Prepare (all sub-tabs) | Apply / Reset + controls for the active sub-tab | Columns / Transforms / Filters / Preview | Dimensions now -> after apply; **itemised** pending list ("log(preop_meld); filter on age_tx; 2 columns excluded") | transform validation, stale report items; invalid rows also marked inline |
| Explore › Plot | Describe / Correlate / Trend pickers + Plot button; **"Plot appearance - updates live"** accordion visually separate | Plot | Variable summary table | plot errors, small-n warnings |
| Explore › Report | Report type, variables / items, format; Generate & Download at the bottom in both modes | Preview / item gallery | What will be included (n sections, n items, format) | empty report, stale data |
| Analyze 1 Setup | Study type, purpose, split, action buttons, table controls | Role table | Incoming dataset snapshot, role summary, selected sample | role conflicts, tier-1 blockers |
| Analyze 2 Table 1 | Table options + Generate | Table 1 | Sample / strata counts | |
| Analyze 3 (each sub-step) | Method settings + Run | Results | Candidates in, flagged n | |
| Analyze 4 Covariates | Table controls | Covariate table | Sample size, EPV, missingness | checks that fail |
| Analyze 5 Model › * | Settings + one action | Summary / model / diagnostics / performance / results | Model header (`edark_model_header()`) | stale model, changed spec |
| Analyze 6 Export | Items and format + Download | File list / preview | What the zip will contain | missing outputs |

Viewport check (§M9.4 NF-05): at 1280 px the centre gets ~600 px with both panes open. Verify
Setup and Covariates tables at 1280 x 800. If too tight, the right pane starts collapsed on
those two pages only (`open = "closed"`) - same width, same place, just folded.

Also in this stage: flip the two right-hand config sidebars to left
(`module_analysis_setup.R:138`, `module_analysis_covariate_confirm.R:147`) and split their
contents into config (left) and info (right); give Model › Summary and Step 6 both panes;
collapse the six widths to the two constants.

**Done when:** walking Prepare -> Explore -> Analyze 1-6 -> Explore › Report, config is
always left at 340 px, info always right at 300 px, and every warning appears in the messages
slot at the top of the centre column.

### Stage 5 - Flatten navigation

- **Apply the §1.2 vocabulary.** Level 2: Prepare's `navset_card_tab` (`edark.R:112`) and
  Explore's `navset_tab` (`edark.R:142`) become pills. Level 3 (D8, underline tabs):
  Step 3's `navset_pill` (`module_analysis_varinvestigation.R:116`), Report's Full / Custom
  `navset_pill` (`module_report.R:47`) and Explore's sidebar `navset_pill` (`edark.R:150`)
  become the sub-step idiom, matching Step 5. Keep the Explore -> Report hop and
  `requested_report_subtab` working.
- **Flatten Data Preview** from 3 tab levels to 1: Original/Working and Data/Summary become
  two `radioGroupButtons` in the left sidebar driving one output (`module_data_preview.R:19`).
- Shorten Analyze step labels so the pills fit on one row at 1280 px: "1 · Setup",
  "2 · Table 1", "3 · Variables", "4 · Covariates", "5 · Model", "6 · Export".
- Card tabs (`navset_card_tab`) are used only for views of one generated result
  (diagnostic checks, performance sets, result outputs).

**Done when:** each nav level has one look everywhere (§1.2 table) - no pills inside a
sidebar or inside pills, and card tabs only for result views; gating and the Explore -> Report hop
(`requested_tab`, `edark.R:432-442`) still work.

### Stage 6 - Small fixes

- Explore empty state; disable Save / Copy / Add to Report until a plot exists
  (`module_explore_output.R:28-46`), with reasons from the Stage 1 table.
- Move the row-count badge below the filter list (`module_row_filter.R:36,40`) - or into the
  Prepare info pane if Stage 4 has landed.
- Replace any remaining native `title=` attributes with `bslib::tooltip()`.
- One copy pass: button labels verb + object; empty-state and message wording consistent.

---

## 5 - Verification

Launch: `devtools::load_all(); edark(liver_tx)` (headless recipe:
`memory/project_running_edark_headless.md` - full `Rscript` path, port 7788, do not kill `ark`).

- **Every stage:** `devtools::check()` at 0 errors / 0 warnings; walk
  Prepare -> Explore -> Analyze 1-6 -> Explore › Report at 1280 x 800 and a wide window, light
  and dark.
- **1:** click each locked step - it says why. Each Run button with an unmet precondition is
  disabled with reason text visible.
- **2:** the three `grep`s return one hit each. A Full and a Custom report generated from
  Explore match the on-screen styling. Regenerate all three formats with `edark_report()`.
- **3:** toggle dark mode on every page - no layout shift, no identity change.
- **4:** panes and widths per the contract on every page. **Setup and Covariates:** drive with
  `chromote` and watch the console - reactable-embedded inputs still patch, survive a search
  clear, and never re-render (`testServer` cannot catch this).
- **5:** gating and the Explore -> Report hop still work.
