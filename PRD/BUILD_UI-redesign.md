# EDARK v0.2 — UI Assessment & Staged Redesign

> The working plan for the UI redesign. Work one stage per session and tick it off below
> when it lands. A stage that needs its own design pass gets planned in detail first.

## Status

| Stage | Scope | Status |
|---|---|---|
| 0 | Design foundation — SCSS, tokens, colour modes | ☐ not started |
| 1 | Component library (`R/ui_helpers.R`) | ☐ not started |
| 2 | Shell and rail (`R/ui_shell.R`, nav service) | ☐ not started |
| 3 | Migrate Analyze | ☐ not started |
| 4 | Migrate Prepare, Explore, Report | ☐ not started |
| 5 | State, locking and staleness made visible | ☐ not started |
| 6 | Content, density and accessibility | ☐ not started |

Stages 0 and 1 are independent of each other and of everything else; 2 depends on 1;
3 and 4 depend on 2; 5 and 6 come last. **Update this table as part of each stage's work.**

## Context

EDARK is a guided, linear, dependency-gated analysis tool for users ranging from novice
clinicians to experienced analysts. The UI has grown feature-first: each of the ~25 modules
invented its own layout container, section-label markup, status vocabulary, empty state and
button grammar. The result is an app whose *furniture moves as you walk through it* — the
sidebar jumps left↔right, disappears on two steps, changes width five times, and the
step-locking that enforces the whole workflow is communicated only by a greyed-out link and
a native browser tooltip.

Goal: one shell, one component vocabulary, one status language, applied to every page, with a
deliberate visual design — so that workflow position, current state, and what-to-do-next are
always in the same place. Desktop-only; horizontal space is ample.

Decisions taken (user): restructure navigation freely; full visual redesign; deliver
assessment **and** staged refactor plan.

---

## Part 1 — Assessment

### 1.1 The structural problem: no page contract

Every module answers "where do controls go?" differently.

| Symptom | Evidence |
|---|---|
| Sidebar side flips mid-workflow | `module_analysis_setup.R:138` and `module_analysis_covariate_confirm.R:147` use `position = "right"`; every other step uses left |
| Sidebar vanishes entirely | Model › Summary (`module_analysis_modelspec.R:80`) and Step 6 (`module_analysis_export.R:18`) have no sidebar — the page furniture disappears mid-tab-strip |
| Five sidebar widths | 405 / 390 / 360 / 360 / 390 / 340 — three different widths inside *one* step (`module_analysis_varinvestigation.R:127,164,186`) |
| Sidebar contract inverted | Steps 1 and 4 put the *configuration* (role radios, covariate checkboxes) in the main-panel reactable and *status* in the sidebar — the opposite of every other step and of the sidebar-is-setup rule in `NOTE_UI-principles.md` |
| Four main-panel idioms in one tab strip | Prepare's four sub-tabs are a `card` (`module_column_manager.R:18`), a bare `div` whose card only appears at render time (`module_transform_variables.R:30` vs `:130`), a flat `tagList` (`module_row_filter.R:20`), and a nested `navset_card_tab` (`module_data_preview.R:19`) |

### 1.2 Navigation depth

- **Data Preview is 3 tab levels deep** (navbar → `prepare_tabs` → `navset_card_tab` → `navset_tab`), 8 containers from the page root.
- **Analyze › Model › Diagnostics is 9 containers deep** (`page_navbar > nav_panel > navset_pill > nav_panel > navset_underline > nav_panel > div > layout_sidebar > navset_card_tab > nav_panel > card`).
- **Report is not a stage.** It is a sub-tab of Explore (`edark.R:159-163`) despite being the fourth phase of the workflow and having its own two-mode sidebar app inside it.
- **Two idioms for one concept.** Step 3's sub-steps are `navset_pill` inside a `navset_pill` (`module_analysis_varinvestigation.R:116`); Step 5's sub-steps are `navset_underline` (`module_analysis_main.R:64`). Same concept, different visual language, nested inside each other.

### 1.3 Locking and state — the biggest functional gap

The workflow's defining feature is its dependency graph, and it is nearly invisible.

`.apply_gate()` (`module_analysis_main.R:146-165`) adds Bootstrap's `disabled` class and sets a
native `title=` attribute on the parent `<li>`. There is **no app CSS overriding `.disabled`**
(`edark.R:49-98` styles `.sidebar .nav-pills .nav-link` but never `.disabled`). So a locked step
is grey text with `pointer-events: none` and a tooltip that only appears after ~1s hover — and
because the link is pointer-events-none, a user who clicks a locked step gets *nothing at all*.

Related:
- Lock reason wording disagrees with the in-panel placeholder for the same condition: tooltip says "Model › Create" (`module_analysis_main.R:135`), placeholders say "the Create tab" (`module_analysis_diagnostics.R:179`, `module_analysis_performance.R:364`, `module_analysis_results.R:163`).
- Disabled-vs-validate-on-click is applied at random: `shinyjs::disabled()` wraps Run in varinvestigation (`:139`,`:201`) and modelspec (`:106`), but table1 (`:29`), diagnostics (`:64`), performance (`:67`) and results (`:66`) stay enabled and fail with a toast. Two different affordances for the same class of precondition.
- **Four status/warning vocabularies** for the same severity: `alert-danger`/`alert-warning`/`alert-success` (`module_prepare_confirm.R:125,131,159`), `badge bg-warning`/`bg-success` (`module_row_filter.R:84-90`), `card(class="border-warning")` (`module_explore_output.R:98-106`), plus transient `showNotification` toasts (`module_prepare_confirm.R:247`, `edark.R:290`).
- **Staged-vs-applied is under-communicated in Prepare.** A staged transform looks identical to an applied one (`module_transform_variables.R:104-128`). The pending badge gives an aggregate count only, never *which* items are pending (`module_prepare_confirm.R:121-136`). Blocking validation arrives as a 6-second toast plus a forced tab switch (`:245-252`) rather than inline on the offending row.
- **A false warning.** The stale-data modal claims dataset changes "will clear custom report items" (`module_prepare_confirm.R:221-238`, duplicated at `edark.R:300-315`) and offers "Apply and Clear Custom Report" — but nothing in the codebase ever clears `custom_report_items`. The warning and the button label are both wrong.

### 1.4 Duplication — the cause, not the symptom

There is no shared UI layer, so every convention is re-typed and drifts.

| Duplicated thing | Copies |
|---|---|
| Uppercase section label `"text-muted small text-uppercase fw-semibold mt-2 mb-1"` | Re-typed ≥14× (`module_analysis_setup.R:792,835,850,1004,1039,1067,1085`; `module_analysis_table1.R:219`; `module_analysis_varinvestigation.R:129,166,188,655,662,672`; `module_analysis_covariate_confirm.R:839,843,881`; `module_trend_controls.R:25,29,38,44`; `module_report.R:67,80,94,108,118,122`), plus **four private `.hdr()` helpers with identical bodies** (`module_analysis_modelspec.R:92`, `module_analysis_diagnostics.R:49`, `module_analysis_performance.R:56`, `module_analysis_results.R:44`), plus a canonical `.sidebar_label()` nobody outside its own file uses (`module_explore_controls.R:86-88`), plus Prepare's entirely different `"mt-2 mb-1 fw-semibold"` (`module_prepare_confirm.R:29`) |
| Aesthetics accordion | 4 verbatim copies — `module_explore_controls.R:16-54`, `module_trend_controls.R:55-91`, `module_report.R:132-168`, `module_report.R:203-239`. The Report copies use `custom_*` input ids, so palette set in Explore silently does or doesn't carry into Report depending on which pill you are on |
| Model header card | 4 near-duplicate hand-written cards with different field sets — `module_analysis_modelspec.R:380-398` (label+modelling+fitted-on+formula), `module_analysis_diagnostics.R:185-192` (label+formula+timestamp), `module_analysis_performance.R:370-386` (label+purpose+validation, **no formula**), `module_analysis_results.R:170-176` (label+formula+generated-at) |
| Empty state | `.ms_placeholder()` (`module_analysis_modelspec.R:474-478`) used by 4 modules; Steps 2/3/4 hand-roll the same div with different icons and no `fst-italic`; Step 3 collinearity has no icon at all (`:496-499`); Step 1 uses a card-with-header instead (`module_analysis_setup.R:517`); Step 6 uses a centered italic stub with a clock icon (`module_analysis_export.R:21-25`); Step 3 tier-1 uses a full-width `alert-warning` (`:21-24`). Six grammars |
| "Fit a model first" copy | Five wordings across `module_analysis_main.R:135`, `diagnostics.R:108,179`, `performance.R:123,364`, `results.R:163`, `modelspec.R:305` — and two different classes (`text-muted` vs `text-danger`) for the same message |

Button grammar drifts the same way: `btn-primary w-100` (most), `btn-primary w-75`
(`module_report.R:63`), `btn-sm btn-outline-primary w-100` (`module_row_filter.R:30`), unclassed
`input_task_button` (`module_trend_controls.R:50`). Labels run from "Generate Table 1" to a bare
**"Run"** (`module_analysis_varinvestigation.R:204`). Generate sits at the *top* of the Full
Report sidebar (`module_report.R:60-64`) and the *bottom* of the Custom Report sidebar (`:259-263`).

### 1.5 Interaction-model collisions

- **Explore stacks two opposite models with no visual distinction.** The variable pickers above the button are *staged* until Describe is clicked (`module_explore_controls.R:181-185`); the aesthetics accordion directly below it applies *live* (`module_explore_output.R:112-135`). Nothing tells the user which is which.
- **Explore has no empty state at all.** `explore_output_ui` renders the action row and both cards unconditionally (`module_explore_output.R:28-84`): before any plot, the user sees an empty 500px card, an empty summary card, and four enabled buttons that respond with a JS `alert()` (`:51`), a thrown download error (`:207`), or a toast (`:235`).
- **Controls far from effect.** The row-count badge — the only feedback a filter slider did anything — sits above the `hr` and scrolls off-screen as filters accumulate (`module_row_filter.R:36,40`). Prepare's Apply/Reset live in the left sidebar while every edit happens in the right-hand tabs, and a long warnings list can push Apply below the fold (`module_prepare_confirm.R:26-56`). Full Report's Generate sits above ~110 lines of the controls it depends on.
- **No pagination or scroll containment** on the column manager (`module_column_manager.R:89-98`) or transform table (`:130-139`); a 60-column dataset is one long scroll and "Select all" scrolls away with the header.
- **A label promising a control that does not exist**: Step 3 collinearity renders an uppercase "Threshold" section header over static prose with no input (`module_analysis_varinvestigation.R:165-167`).

### 1.6 Visual / theming

- All styling is inline `tags$style` in three places — `edark.R:48-99`, `module_analysis_modelspec.R:41-56`, and a global `.form-check` override leaked from inside a *render function* (`module_column_manager.R:91-95`). No `inst/www`, no `.scss`, no design tokens.
- Dark mode swaps the entire bootswatch preset (`flatly` ↔ `darkly`, `edark.R:342-355`), so the app's whole palette, typography and shadow language change identity between modes rather than re-mapping tokens.
- Navbar controls are `rgba(255,255,255,0.75)` on primary (`edark.R:90-98`) — below WCAG AA at that size.
- Colour carries meaning inconsistently: amber means "transformed" in Data Preview (explained at `module_data_preview.R:48`) and "type changed" in the column manager (`module_column_manager.R:81`) with no legend; the same amber is also "warning" in four other places.

---

## Part 2 — Recommended shell

**Recommendation: the tri-pane with a persistent step rail (option 1).** Reasoning:

The app has *two* distinct "where am I" questions and they are currently tangled in one top navbar
plus three levels of nested tabs: **(a) where am I in the workflow and what is unlocked**, and
**(b) what is true about my data/model right now**. Give each a permanent home.

```
┌──────────────────────────────────────────────────────────────────────┐
│ EDARK v0.2   liver_tx · 500 × 36 · working 431 × 22 · ⚠ 3 pending  ☾ │  global status bar
├────────────┬──────────────────┬──────────────────────┬───────────────┤
│ PREPARE    │ CONFIGURE        │                      │ STATUS & NEXT │
│  ✓ Columns │                  │      CANVAS          │               │
│  ✓ Transf. │  Outcome   [▾]   │                      │  n used  431  │
│  ○ Filters │  Exposure  [▾]   │   the one thing      │  EPV     8.2⚠ │
│  ○ Preview │                  │   this page is       │  ✓ preflight  │
│ EXPLORE    │  ADVANCED      ▸ │   about              │  ⚠ 2 warnings │
│  ● Plot    │  ───────────     │                      │ ───────────── │
│ ANALYZE    │  [   Run Model ] │                      │ NEXT          │
│  ✓ 1 Setup │                  │                      │ Run the model │
│  🔒 5 Model│                  │                      │ to unlock     │
│  🔒 6 Expt │                  │                      │ Diagnostics.  │
│ REPORT     │                  │                      │               │
└────────────┴──────────────────┴──────────────────────┴───────────────┘
   rail 200      config 340            flexible            status 300
```

**Why not option 2 (two-pane + status strip):** a horizontal strip can hold four or five facts.
Step 4's live listwise-deletion panel, Step 5's verbose preflight and Prepare's warning list are
*lists* that grow. They need a column, not a strip.

**Why not option 3 (tri-pane, keep navbar):** it keeps the pills-inside-pills tab nesting that
produces the 9-deep Diagnostics page, and leaves locking rendered as a greyed tab — the single
worst UX defect found. The rail is what makes the dependency graph legible.

**The cost** is ~840px of chrome. On a 1920px desktop that leaves ~1080px of canvas — more than
today's Step 4 gets. Both side panes use `bslib::sidebar(open = "desktop")` so they stay
collapsible for the wide reactables, and the rail collapses to icons.

**The pane contract — every page, no exceptions:**

| Pane | Always contains | Never contains |
|---|---|---|
| Rail | Workflow position + lock/done/stale state. Nothing else | Any input |
| Config (left) | The inputs for this page, grouped required → optional (accordion) → **one** primary action at the bottom | Results, status, long prose |
| Canvas | The one artefact this page produces: table, plot, or results tabs | Inputs, except inputs *inside* the artefact (Steps 1 & 4 role/covariate tables) |
| Status (right) | Live state (counts, checks, validation) **and** "What's next" guidance | Inputs, results |

Defining the right pane as **Status *and* Next Step** is what makes it non-empty on every page
and simultaneously retires the six competing empty-state/guidance grammars from §1.4.

**Resolving the Step 1 / Step 4 inversion:** their config genuinely lives in the table. Under the
contract, the left pane holds the *table-level* controls (Include All/Clear, role legend, method
Add/Replace, search/filter), the canvas holds the table, the right pane holds sample counts and
checks — which is where they already are. The inversion disappears without touching the fragile
reactable-embedded-input machinery.

### Information architecture (rail replaces the navbar tabs)

```
PREPARE   Columns · Transforms · Row Filters · Data Preview
EXPLORE   Plot                                            (Describe/Correlate/Trend = config-pane mode switch)
ANALYZE   1 Setup · 2 Table 1 · 3 Variables · 4 Covariates · 5 Model ▾ · 6 Export
                                                     ├ Summary ├ Create ├ Diagnostics ├ Performance └ Results
REPORT    Full Report · Custom Report
```

- **Report promoted to a top-level stage** — it is phase 4 of the workflow, not a sub-tab of Explore.
- **Data Preview flattened** from 3 tab levels to a rail item with two segmented controls in the config pane (Original/Working, Data/Summary). Consider showing Original and Working side by side.
- **Step 5's `navset_underline` and Step 3's inner `navset_pill` both dissolve** into rail children. Max container depth drops from 9 to 4 (`shell > page > pane > navset_card_tab`).
- The only tabs left are `navset_card_tab` on the canvas for *result facets* (diagnostic checks, performance sets, result outputs) — one idiom, one meaning.

---

## Part 3 — Staged implementation

Each stage is independently runnable and leaves the app working.

### Stage 0 — Design foundation

*(Plan persisted here and cross-referenced from the root `CLAUDE.md` and `PRD/CLAUDE.md` on
2026-09-19 — done, no action needed.)*

**New:** `inst/www/edark.scss`, loaded via `bslib::bs_add_rules(theme, sass::sass_file(system.file("www/edark.scss", package = "edark")))`.

- Token layer as CSS custom properties on `:root` and `[data-bs-theme="dark"]`: type scale, spacing scale (4px base), radii, elevation, and **semantic colours** — `--edark-status-{ok,info,warn,error,pending,locked}` and `--edark-type-{numeric,factor,datetime,character}`.
- Replace the bootswatch `flatly ↔ darkly` swap (`edark.R:342-355`) with one Bootstrap 5.3 colour-mode theme + `bslib::input_dark_mode()`, so dark mode re-maps tokens instead of changing the app's identity. *Verify `bslib` version supports `input_dark_mode()`; `DESCRIPTION:21` pins `>= 0.7.0`, which does.*
- Fix navbar control contrast (`edark.R:90-98`); add a real `.nav-link.disabled` / `.edark-locked` treatment.
- Delete the render-time global CSS leak at `module_column_manager.R:91-95`.
- Move `.edark-pulse` and `.edark-summary-*` (`module_analysis_modelspec.R:41-56`) into the SCSS.

### Stage 1 — Component library
**New:** `R/ui_helpers.R` — the one place UI vocabulary is defined. No layout change yet; adopt mechanically across modules.

Components (names indicative): `edark_section_label()`, `edark_page_header()`,
`edark_status_chip(level, text)`, `edark_status_row(label, value, level)`,
`edark_empty_state(icon, title, body, action)`, `edark_run_button(id, label, enabled, reason)`,
`edark_guidance(text)`, `edark_metric_list()`, `edark_type_badge(type)`, `edark_model_header(result, fields)`.

- Delete the four private `.hdr()` copies and the ≥14 re-typed label strings (§1.4).
- Promote `.aesthetics_accordion()` (`module_explore_controls.R:16-54`) to `R/ui_helpers.R`; delete the three copies; **decide and document** whether Report inherits Explore's aesthetics or keeps an independent `custom_*` set — today it silently does both.
- One `edark_model_header()` replaces the four hand-written cards; take the union of fields, show what applies.
- One lock-reason string table so tooltip and placeholder can never disagree.
- `edark_run_button()` makes disabled-with-reason the *only* precondition affordance; remove the validate-on-click + toast paths (`module_analysis_table1.R:233`, `module_analysis_modelspec.R:314`).

### Stage 2 — Shell and rail
**New:** `R/ui_shell.R` (`edark_shell()`, `edark_page()`), `R/module_nav_rail.R`, `R/service_navigation.R`.

- `edark_page(id, title, config = , canvas = , status = )` → nested `bslib::layout_sidebar` (bslib allows one sidebar per call; outer = config left, inner = status right). Both `open = "desktop"`, fixed widths 340 / 300.
- `edark_shell()` = `bslib::page_fillable` + global status bar + rail + page outlet.
- **Navigation service** replaces `nav_select("main_navbar", ...)`: rail state is a `shared_state$active_page` string; `edark.R:432-442` (`requested_tab`, the Explore→Report hop) and `.apply_gate()` (`module_analysis_main.R:146-165`) both rewrite against it. Rail item states: `done` ✓ / `current` ● / `available` ○ / `locked` 🔒 / `stale` ⟳. **Clicking a locked item must surface its reason** (inline in the status pane), not silently do nothing.
- Global status bar: dataset lineage — original dims, working dims, pending-change count, frozen/stale flag, model-fitted flag. Always true, always the same place.

### Stage 3 — Migrate Analyze
Highest inconsistency density; migrate first.

- Steps 1–6 become `edark_page()` calls; Step 5's `navset_underline` (`module_analysis_main.R:64`) and Step 3's inner `navset_pill` (`module_analysis_varinvestigation.R:116`) dissolve into rail children.
- Steps 1 & 4: config pane gets the table-level controls per §Part 2; status pane keeps `sample_ui`/`checks_ui`. **Do not re-render the reactables** — the patch-don't-re-render contract in `CLAUDE.md` ("Interactive inputs inside reactable cells") still applies, and the `MutationObserver` wrappers must survive the move.
- Step 3 collinearity: either give the "Threshold" label a real input or remove the label (`:165-167`).
- Model › Summary and Step 6 gain the standard three panes.
- Sidebar widths collapse to the two shell constants.

### Stage 4 — Migrate Prepare, Explore, Report
- **Prepare:** four rail items. Apply/Reset move to the **status pane** next to the pending list; pending state becomes itemised ("3 pending: log(preop_meld), filter on age_tx, 2 columns excluded"), not a bare count. Per-row staged markers on transform rows and filter cards. Blocking validation renders inline on the offending row *and* in the status pane — replacing the 6-second toast + forced tab switch (`module_prepare_confirm.R:245-252`).
- **Explore:** Describe/Correlate/Trend stay a config-pane mode switch. Give the config pane an explicit **Plot settings (live)** group, visually separated from the staged pickers, closing the §1.5 collision. Status pane holds the variable summary + stale-data notice. Add the missing empty state; disable the four action buttons until a plot exists (`module_explore_output.R:28-46`).
- **Report:** promoted to a top-level rail stage with two children. Generate/Download goes to the **bottom of the config pane** in both modes; status pane holds the selection summary and readiness.
- Data Preview flattened per §Part 2.

### Stage 5 — State, locking and staleness made visible
- Rail states wired to real conditions, including a **stale** state: upstream Prepare changed after freeze, a diagnostic ran on a superseded fit, custom report items referencing dropped columns.
- Single status vocabulary applied everywhere; retire `alert-*` / `badge bg-*` / `border-warning` / toast as four ways to say the same thing (§1.3). Toasts reserved for transient confirmations only.
- **Fix the false warning** at `module_prepare_confirm.R:221-238` and its duplicate at `edark.R:300-315`: nothing clears `custom_report_items`, so the modal text and the "Apply and Clear Custom Report" button label are both wrong. Either implement the clearing or correct the copy — and de-duplicate the two modal definitions.

### Stage 6 — Content, density and accessibility
- One `edark_empty_state()` everywhere; one copy pass so every "do X first" message names the same destination with the same words.
- Novice/expert: a **Guided / Compact** toggle that shows or hides the status pane's "What's next" block and the inline explainer prose, persisted per session.
- Scroll containment + virtualisation on the column manager (`module_column_manager.R:89-98`) and transform table (`:130-139`); sticky table headers so Select all / Clear stay reachable.
- Real tooltips (`bslib::tooltip()`) replacing native `title=`; focus-visible rings; AA contrast on all status colours in both modes; keyboard traversal of the rail.

---

## Verification

Run the app and walk the workflow (see `memory/project_running_edark_headless.md` for the headless
launch recipe — full `Rscript` path, port 7788, do not kill `ark`):

```r
devtools::load_all(); edark(liver_tx)
```

Per stage:
- **0** — toggle dark mode on every page; no layout shift, no colour-identity change; check contrast on status colours; confirm no global CSS escapes a render function.
- **1** — `grep` for `"text-uppercase fw-semibold"`, `\.hdr <- `, and the aesthetics-accordion body; each must appear exactly once, in `R/ui_helpers.R`.
- **2–4** — walk Prepare → Explore → Analyze 1→6 → Report. Confirm: panes never move or vanish; rail state matches actual gating; clicking a locked item explains why; the Explore→Report hop and `requested_tab` still work.
- **3** — drive Steps 1 and 4 with `chromote` (installed) and check the browser console: reactable-embedded inputs must still patch, survive a search-filter clear, and never re-render. Server-side `testServer` cannot catch these failures.
- **5** — freeze the dataset, change Prepare, return to Analyze: stale state must appear in the rail and the global status bar. Stage a transform, click Apply with a custom report queued: the modal copy must match what actually happens.
- **Throughout** — `devtools::check()` must stay at 0 errors / 0 warnings; regenerate a report in all three formats (`edark_report()`) to confirm nothing in the report pipeline depended on UI-owned helpers.
