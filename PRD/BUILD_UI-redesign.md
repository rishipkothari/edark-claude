# EDARK v0.2 — UI Consistency Plan

> Working plan for tidying the UI. Work one stage per session and tick it off below.
>
> **Scope rule:** this is an academic project, not a shipped product. Every stage below is
> achievable with `bslib` + plain R. The total budget for non-R code is **one small CSS file
> (~80 lines) and zero new JavaScript**. If a proposed change needs hand-written HTML, a Sass
> build step, or custom JS handlers, it is out of scope — pick the simpler `bslib` option
> instead, or drop it. The existing reactable-embedded-input JS (§N1.4) is the one exception
> and must not be touched.

## Status

| Stage | Scope | Effort | Status |
|---|---|---|---|
| 1 | Component library (`R/ui_helpers.R`) — pure R, no visual change | M | ☐ not started |
| 2 | Locking and status made honest — pure R | S | ☐ not started |
| 3 | Minimal theme file + dark mode — ~80 lines CSS | S | ☐ not started |
| 4 | Layout contract: one sidebar rule applied to every page | M | ☐ not started |
| 5 | Flatten navigation (Report promoted, deep tabs dissolved) | M | ☐ not started |
| 6 | Small fixes: empty states, density, tooltips | S | ☐ not started |

Stages 1–3 are independent and can be done in any order. 4 depends on 1. 5 is independent but
touches `edark.R` routing. 6 depends on 1. **Update this table as part of each stage's work.**

## Context

EDARK is a guided, linear, dependency-gated analysis tool. The UI has grown feature-first:
each of the ~25 modules invented its own layout container, section-label markup, status
vocabulary, empty state and button grammar. The furniture moves as the user walks through the
app — the sidebar jumps left↔right, disappears on two steps, changes width five times — and
the step-locking that enforces the whole workflow is communicated only by grey text and a
native browser tooltip.

Goal: **one component vocabulary and one status language, applied consistently.** Not a visual
redesign. The Bootstrap/bslib default look is fine for an academic tool; the problem is
inconsistency and a genuinely broken locking affordance, both of which are R-level problems.

---

## Part 1 — Assessment

*(This audit is the durable part of the document. The stages in Part 2 are one way to act on
it; the findings stand on their own.)*

### 1.1 No page contract

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
- **Report is not a stage.** It is a sub-tab of Explore (`edark.R:159-163`) despite being the fourth phase of the workflow and containing its own two-mode sidebar app.
- **Two idioms for one concept.** Step 3's sub-steps are `navset_pill` inside a `navset_pill` (`module_analysis_varinvestigation.R:116`); Step 5's sub-steps are `navset_underline` (`module_analysis_main.R:64`). Same concept, different visual language, nested inside each other.
- **Nine step pills wrap to two rows** at ~1500 px.

### 1.3 Locking and state — the biggest functional gap

The workflow's defining feature is its dependency graph, and it is nearly invisible.

`.apply_gate()` (`module_analysis_main.R:146-165`) adds Bootstrap's `disabled` class and a
native `title=` attribute on the parent `<li>`. There is **no app CSS overriding `.disabled`**
(`edark.R:49-98` styles `.sidebar .nav-pills .nav-link` but never `.disabled`). So a locked step
is grey text with `pointer-events: none` and a tooltip that appears only after ~1s hover — and
because the link is `pointer-events: none`, a user who clicks a locked step gets *nothing at all*.

Related:

- Lock wording disagrees with the in-panel placeholder for the same condition: tooltip says "Model › Create" (`module_analysis_main.R:135`), placeholders say "the Create tab" (`module_analysis_diagnostics.R:179`, `module_analysis_performance.R:364`, `module_analysis_results.R:163`).
- Disabled-vs-validate-on-click is applied at random: `shinyjs::disabled()` wraps Run in varinvestigation (`:139`,`:201`) and modelspec (`:106`), but table1 (`:29`), diagnostics (`:64`), performance (`:67`) and results (`:66`) stay enabled and fail with a toast. Two affordances for one class of precondition.
- **Four status vocabularies** for the same severity: `alert-danger`/`alert-warning`/`alert-success` (`module_prepare_confirm.R:125,131,159`), `badge bg-warning`/`bg-success` (`module_row_filter.R:84-90`), `card(class="border-warning")` (`module_explore_output.R:98-106`), plus transient `showNotification` toasts (`module_prepare_confirm.R:247`, `edark.R:290`).
- **Staged-vs-applied is under-communicated in Prepare.** A staged transform looks identical to an applied one (`module_transform_variables.R:104-128`). The pending badge gives an aggregate count only, never *which* items are pending (`module_prepare_confirm.R:121-136`). Blocking validation arrives as a 6-second toast plus a forced tab switch (`:245-252`) rather than inline on the offending row.
- **A false warning.** The stale-data modal claims dataset changes "will clear custom report items" (`module_prepare_confirm.R:221-238`, duplicated at `edark.R:300-315`) and offers "Apply and Clear Custom Report" — but nothing in the codebase ever clears `custom_report_items`. The warning and the button label are both wrong.

### 1.4 Duplication — the cause, not the symptom

There is no shared UI layer, so every convention is re-typed and drifts.

| Duplicated thing | Copies |
|---|---|
| Uppercase section label `"text-muted small text-uppercase fw-semibold mt-2 mb-1"` | Re-typed ≥14× (`module_analysis_setup.R:792,835,850,1004,1039,1067,1085`; `module_analysis_table1.R:219`; `module_analysis_varinvestigation.R:129,166,188,655,662,672`; `module_analysis_covariate_confirm.R:839,843,881`; `module_trend_controls.R:25,29,38,44`; `module_report.R:67,80,94,108,118,122`), plus **four private `.hdr()` helpers with identical bodies** (`module_analysis_modelspec.R:92`, `module_analysis_diagnostics.R:49`, `module_analysis_performance.R:56`, `module_analysis_results.R:44`), plus a canonical `.sidebar_label()` nobody outside its own file uses (`module_explore_controls.R:86-88`), plus Prepare's different `"mt-2 mb-1 fw-semibold"` (`module_prepare_confirm.R:29`) |
| Aesthetics accordion | 4 verbatim copies — `module_explore_controls.R:16-54`, `module_trend_controls.R:55-91`, `module_report.R:132-168`, `module_report.R:203-239`. The Report copies use `custom_*` input ids, so a palette set in Explore silently does or doesn't carry into Report depending on which pill you are on |
| Model header card | 4 near-duplicates with different field sets — `module_analysis_modelspec.R:380-398` (label+modelling+fitted-on+formula), `module_analysis_diagnostics.R:185-192` (label+formula+timestamp), `module_analysis_performance.R:370-386` (label+purpose+validation, **no formula**), `module_analysis_results.R:170-176` (label+formula+generated-at) |
| Empty state | `.ms_placeholder()` (`module_analysis_modelspec.R:474-478`) used by 4 modules; Steps 2/3/4 hand-roll the same div with different icons and no `fst-italic`; Step 3 collinearity has no icon (`:496-499`); Step 1 uses a card-with-header (`module_analysis_setup.R:517`); Step 6 a centered italic stub with a clock icon (`module_analysis_export.R:21-25`); Step 3 tier-1 a full-width `alert-warning` (`:21-24`). Six grammars |
| "Fit a model first" copy | Five wordings across `module_analysis_main.R:135`, `diagnostics.R:108,179`, `performance.R:123,364`, `results.R:163`, `modelspec.R:305` — and two classes (`text-muted` vs `text-danger`) for the same message |

Button grammar drifts the same way: `btn-primary w-100` (most), `btn-primary w-75`
(`module_report.R:63`), `btn-sm btn-outline-primary w-100` (`module_row_filter.R:30`), unclassed
`input_task_button` (`module_trend_controls.R:50`). Labels run from "Generate Table 1" to a bare
**"Run"** (`module_analysis_varinvestigation.R:204`). Generate sits at the *top* of the Full
Report sidebar (`module_report.R:60-64`) and the *bottom* of the Custom Report sidebar (`:259-263`).

### 1.5 Interaction-model collisions

- **Explore stacks two opposite models with no visual distinction.** The variable pickers above the button are *staged* until Describe is clicked (`module_explore_controls.R:181-185`); the aesthetics accordion directly below applies *live* (`module_explore_output.R:112-135`). Nothing says which is which.
- **Explore has no empty state.** `explore_output_ui` renders the action row and both cards unconditionally (`module_explore_output.R:28-84`): before any plot the user sees an empty 500px card, an empty summary card, and four enabled buttons that respond with a JS `alert()` (`:51`), a thrown download error (`:207`), or a toast (`:235`).
- **Controls far from effect.** The row-count badge — the only feedback a filter slider did anything — sits above the `hr` and scrolls off-screen as filters accumulate (`module_row_filter.R:36,40`). Prepare's Apply/Reset live in the left sidebar while every edit happens in the right-hand tabs, and a long warnings list can push Apply below the fold (`module_prepare_confirm.R:26-56`).
- **No scroll containment** on the column manager (`module_column_manager.R:89-98`) or transform table (`:130-139`); a 60-column dataset is one long scroll and "Select all" scrolls away with the header.
- **A label promising a control that does not exist**: Step 3 collinearity renders an uppercase "Threshold" header over static prose with no input (`module_analysis_varinvestigation.R:165-167`).

### 1.6 Visual / theming

- All styling is inline `tags$style` in three places — `edark.R:48-99`, `module_analysis_modelspec.R:41-56`, and a global `.form-check` override leaked from inside a *render function* (`module_column_manager.R:91-95`).
- Dark mode swaps the entire bootswatch preset (`flatly` ↔ `darkly`, `edark.R:342-355`), so the whole palette and typography change identity between modes.
- Navbar controls are `rgba(255,255,255,0.75)` on primary (`edark.R:90-98`) — low contrast.
- Colour carries meaning inconsistently: amber means "transformed" in Data Preview (explained at `module_data_preview.R:48`) and "type changed" in the column manager (`module_column_manager.R:81`) with no legend; the same amber is also "warning" in four other places.

---

## Part 2 — What we are and are not doing

**Not doing** (considered and dropped as out of scope for an academic project):

- A tri-pane shell with a persistent left step rail. It is achievable in `bslib` — a rail is just
  a column of `actionLink`s, and nested `layout_sidebar` gives three panes — but it means
  rewriting the container of all ~25 modules and building a navigation service to replace
  `nav_select()`. Too much churn for the benefit. If the layout still frustrates after Stages 1–6,
  revisit it then, with Stage 1's components already in place to make it cheap.
- A Sass/SCSS token layer and design system. Replaced by one small CSS file (Stage 3).
- A Guided/Compact density toggle, virtualised tables, full WCAG audit.

**Doing instead:** keep the current `page_navbar` + `layout_sidebar` structure, and make it
consistent. One set of helper functions, one sidebar rule, one status language, honest locking.
The look stays recognisably Bootstrap; the behaviour stops drifting.

---

## Part 3 — Stages

Each stage is independently runnable and leaves the app working.

### Stage 1 — Component library
**New:** `R/ui_helpers.R` — the one place UI vocabulary is defined. Pure R, no visual change;
adopt mechanically across modules.

Components (names indicative):
`edark_section_label(text)`, `edark_status_chip(level, text)`, `edark_status_row(label, value, level)`,
`edark_empty_state(icon, title, body)`, `edark_run_button(id, label, enabled, reason)`,
`edark_model_header(result, fields)`, `edark_aesthetics_accordion(ns, prefix)`.

- Delete the four private `.hdr()` copies and the ≥14 re-typed label strings (§1.4). Fold Prepare's variant into the same helper.
- Promote `.aesthetics_accordion()` (`module_explore_controls.R:16-54`) into the helper file; delete the three copies. **Decide and document** whether Report inherits Explore's aesthetics or keeps an independent `custom_*` set — today it silently does both depending on which pill you are on.
- One `edark_model_header()` replaces the four hand-written cards; take the union of fields, show what applies.
- One lock-reason string table (a named character vector) so tooltip and placeholder can never disagree.
- One `edark_empty_state()` replaces the six grammars.

`levels` used by chips/rows are fixed and small: `ok`, `info`, `warn`, `error`, `pending`,
`locked`. They map to existing Bootstrap utility classes — no new CSS needed at this stage.

**Done when:** `grep` for `"text-uppercase fw-semibold"`, `\.hdr <- `, and the aesthetics-accordion
body each return exactly one hit, in `R/ui_helpers.R`.

### Stage 2 — Locking and status made honest
Pure R. This is the highest-value fix in the document and does not depend on any layout change.

- **A locked step must explain itself.** Keep `.apply_gate()` for the visual state, but make locked items clickable: on click, do not navigate — show the reason. Simplest route that stays in R: `bslib::tooltip()` / `popover()` on the nav item instead of the native `title=` attribute.
- Make disabled-with-reason the **only** precondition affordance. Route every Run button through `edark_run_button()`; remove the validate-on-click + toast paths (`module_analysis_table1.R:233`, `module_analysis_modelspec.R:314`) and add reasons to the four buttons that currently stay enabled (`table1.R:29`, `diagnostics.R:64`, `performance.R:67`, `results.R:66`).
- Retire three of the four status vocabularies (§1.3). One chip/row helper everywhere; toasts reserved for transient confirmations only.
- **Fix the false warning** at `module_prepare_confirm.R:221-238` and its duplicate at `edark.R:300-315`: nothing clears `custom_report_items`, so both the modal text and the "Apply and Clear Custom Report" button label are wrong. Correct the copy and de-duplicate the two modal definitions.
- Itemise Prepare's pending state — "3 pending: log(preop_meld), filter on age_tx, 2 columns excluded" instead of a bare count (`module_prepare_confirm.R:121-136`).
- Blocking validation renders inline on the offending row as well as in the Apply pane, replacing the 6-second toast + forced tab switch (`:245-252`).

### Stage 3 — Minimal theme file
**New:** `inst/www/edark.css`, loaded with `tags$head(tags$link(rel = "stylesheet", href = "edark/edark.css"))` and a `shiny::addResourcePath("edark", system.file("www", package = "edark"))` in `edark()`. No Sass, no build step.

Budget: **~80 lines.** Contents:

- A dozen CSS custom properties on `:root` and `[data-bs-theme="dark"]` — the six status colours and the four column-type colours (`--edark-type-{numeric,factor,datetime,character}`), so the amber-means-two-things problem (§1.6) gets resolved by naming rather than by a palette system.
- A real `.nav-link.disabled` / `.edark-locked` treatment (lock glyph, cursor, and **not** `pointer-events: none`, so Stage 2's click-to-explain works).
- Navbar control contrast fix (`edark.R:90-98`).
- Scroll containment on the two long tables (`max-height` + `overflow:auto` + `position:sticky` header) — 6 lines, closes §1.5.

Also in this stage:

- Replace the `flatly ↔ darkly` bootswatch swap (`edark.R:342-355`) with **one** bootswatch preset plus `bslib::input_dark_mode()`, so dark mode re-maps Bootstrap's own variables instead of changing the app's identity. `DESCRIPTION:21` pins `bslib >= 0.7.0`, which supports it.
- Move the inline `tags$style` blocks (`edark.R:48-99`, `module_analysis_modelspec.R:41-56`) into the file, and **delete the global CSS leak inside a render function** at `module_column_manager.R:91-95`.

### Stage 4 — Layout contract
No new shell. Apply one rule to the pages that already exist.

**The rule:** every page is `layout_sidebar(sidebar = sidebar(position = "left", width = 340), ...)`.
Sidebar holds inputs, grouped required → optional (accordion) → **one** primary action at the
bottom. Main panel holds the one artefact the page produces. Status that does not fit in the
sidebar goes in a card at the top of the main panel.

- Flip the two right-hand sidebars to left (`module_analysis_setup.R:138`, `module_analysis_covariate_confirm.R:147`).
- Collapse the five widths to the single constant.
- Give Model › Summary (`module_analysis_modelspec.R:80`) and Step 6 (`module_analysis_export.R:18`) a sidebar so the furniture stops disappearing.
- Steps 1 and 4 keep their config-in-the-table design — it is genuinely the right shape for role and covariate assignment. Their sidebars take the *table-level* controls (Include All / Clear, legend, search) plus the existing sample/checks output. **Do not re-render the reactables**: the patch-don't-re-render contract (§N1.4) still applies and the `MutationObserver` wrappers must survive.
- Prepare: move Apply/Reset above the warnings list so a long list cannot push them below the fold.
- Explore: give the sidebar an explicit **Plot settings (live)** group, visually separated from the staged pickers, closing the §1.5 collision.
- Report: Generate/Download at the bottom of the sidebar in both modes.
- Unify button grammar: one primary-action class, one label convention (verb + object, so no bare "Run").

### Stage 5 — Flatten navigation
Structural, but all `nav_panel` rearrangement — no new components.

- **Promote Report to a top-level navbar tab** (`edark.R:159-163`). It is phase 4 of the workflow, not a sub-tab of Explore. Keep the Explore→Report hop working (`edark.R:432-442`, `requested_tab`).
- **Dissolve the doubled tab idioms.** Step 3's inner `navset_pill` (`module_analysis_varinvestigation.R:116`) and Step 5's `navset_underline` (`module_analysis_main.R:64`) become one idiom. Pick `navset_underline` for sub-steps and use it in both places.
- **Flatten Data Preview** from 3 tab levels to one: two `radioGroupButtons` in the sidebar (Original/Working, Data/Summary) driving a single output (`module_data_preview.R:19`).
- Shorten the Analyze step labels so the pills stop wrapping at ~1500 px ("Variables", "Covariates").
- The only tabs left are `navset_card_tab` on the main panel for *result facets* (diagnostic checks, performance sets, result outputs) — one idiom, one meaning.

### Stage 6 — Small fixes
- Add Explore's missing empty state; disable the four action buttons until a plot exists (`module_explore_output.R:28-46`).
- One copy pass: every "do X first" message names the same destination in the same words, drawn from Stage 1's lock-reason table.
- Step 3 collinearity: either give the "Threshold" label a real input or remove the label (`:165-167`).
- Move the row-count badge below the filter list so it stays near the controls it reports on (`module_row_filter.R:36,40`).
- Replace remaining native `title=` attributes with `bslib::tooltip()`.

---

## Verification

Run the app and walk the workflow (see `memory/project_running_edark_headless.md` for the
headless launch recipe — full `Rscript` path, port 7788, do not kill `ark`):

```r
devtools::load_all(); edark(liver_tx)
```

Per stage:

- **1** — `grep` for the three duplicated bodies; each appears exactly once. App looks unchanged.
- **2** — click a locked step: it must say why. Every Run button with an unmet precondition is disabled and states the reason. Stage a transform with a custom report queued and click Apply: the modal copy must match what actually happens.
- **3** — toggle dark mode on every page: no layout shift, no colour-identity change. Confirm no `tags$style` remains inside a render function.
- **4** — walk Prepare → Explore → Analyze 1→6 → Report: the sidebar is on the left, one width, present on every page.
- **4, Steps 1 & 4** — drive with `chromote` (installed) and watch the browser console: reactable-embedded inputs must still patch, survive a search-filter clear, and never re-render. `testServer` cannot catch these failures.
- **5** — confirm the Explore→Report hop and `requested_tab` still work after the promotion.
- **Throughout** — `devtools::check()` stays at 0 errors / 0 warnings; regenerate a report in all three formats (`edark_report()`) to confirm nothing in the report pipeline depended on a UI-owned helper.
