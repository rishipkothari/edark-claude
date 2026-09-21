# EDARK v0.2 — Shiny-Native UI Redesign Assessment

> A competing assessment of [BUILD_UI-redesign.md](BUILD_UI-redesign.md), with a
> lower-complexity redesign recommendation that stays close to standard Shiny and
> `bslib` patterns.

## Status

This is a design proposal only. No implementation stages have started.

| Stage | Scope | Status |
|---|---|---|
| 0 | Confirm design decisions and capture a visual baseline | ☐ not started |
| 1 | Theme and shared UI helpers | ☐ not started |
| 2 | Standardize page layouts and component usage | ☐ not started |
| 3 | Simplify navigation and promote Report | ☐ not started |
| 4 | Improve state, guidance, density and accessibility | ☐ not started |

Work one stage per session. Keep the app runnable at the end of every stage and update
this table when a stage lands.

---

## 1 — Purpose

The current EDARK interface is feature-complete enough to expose a recurring UI problem:
each module has developed its own layout, navigation, empty-state, status and action
conventions. The result is functional but visually and behaviorally inconsistent.

The original redesign plan correctly diagnoses these problems. Its proposed solution,
however, introduces a custom application shell with a workflow rail, two side panes, a
navigation service and responsive pane behavior. That design is possible, but it would
require substantially more custom HTML, CSS and JavaScript than EDARK needs.

This competing plan aims for most of the usability benefit while preserving the existing
Shiny architecture:

- standard `bslib::page_navbar()` navigation;
- standard `bslib::layout_sidebar()` pages;
- standard `navset_*()` components with fewer levels of nesting;
- a small shared R UI-helper layer;
- a modest SCSS/CSS theme;
- existing Shiny reactive state and navigation mechanisms.

The guiding constraint is: **prefer a standard Shiny component over a custom UI mechanism
unless the standard component cannot support the required behavior.**

---

## 2 — Assessment of the Current UI

### 2.1 What already works

The application already has a sound functional structure:

- Prepare, Explore and Analyze represent distinct user tasks.
- Most computation occurs only after an explicit action.
- Sidebars generally contain configuration and main panels contain output.
- Analyze has meaningful workflow gating.
- Modules communicate through `shared_state` rather than through UI coupling.
- The same plots and statistical services support both the app and exported output.

The redesign should preserve these strengths and avoid changing server behavior merely to
achieve a different visual layout.

### 2.2 Main problems

#### Inconsistent page structure

- Sidebars change side and width between modules.
- Some pages have no sidebar while adjacent pages do.
- Setup and Covariate Confirmation place status in the sidebar and interactive tables in
  the main panel, while other pages use the sidebar for all configuration.
- Primary actions appear at different positions, including at the top of Full Report and
  the bottom of Custom Report.

#### Excessive and inconsistent navigation

- The app mixes navbar tabs, ordinary tabs, card tabs, pills and underline tabs.
- Data Preview has nested source and content tabs.
- Analyze nests Model tabs inside step pills and uses another set of pills within Variable
  Investigation.
- Report behaves like a major task but is nested beneath Explore.

#### Weak state communication

- Locked Analyze steps are mainly communicated through disabled links and native browser
  tooltips.
- Equivalent preconditions are handled inconsistently: some actions are disabled, while
  others remain enabled and fail with a toast.
- Prepare shows an aggregate pending state but does not clearly identify the staged items.
- Stale, warning, pending and success states use several unrelated visual conventions.
- Some empty result areas provide guidance, while others render as blank cards.

#### Repeated UI code

The following patterns are independently recreated across modules:

- uppercase sidebar section labels;
- plot-aesthetics controls;
- model summary headers;
- empty-state messages;
- status and warning blocks;
- primary run/generate buttons.

This duplication causes visual and wording drift.

#### Density and discoverability

- Column and transform interfaces become very long for wide datasets.
- Important bulk actions and table headings can scroll out of view.
- Explore does not visually distinguish inputs applied by the Run button from appearance
  settings applied live.
- Explore initially shows empty output containers and actions that cannot yet succeed.

### 2.3 Problems that should be fixed independently of the redesign

- Correct the custom-report warning: current copy says applying Prepare changes clears
  custom report items, but the implementation does not clear them.
- Remove the Collinearity “Threshold” heading unless an actual threshold control is added.
- Use consistent wording for “fit a model first” and similar prerequisites.
- Fix known functional UI discrepancies listed in `PRD/CLAUDE.md`, such as the factor-trend
  summary behavior and mismatched trend baseline default.

---

## 3 — Assessment of the Original Redesign Plan

### 3.1 Strengths

The original [BUILD_UI-redesign.md](BUILD_UI-redesign.md) is especially strong in its
source-level diagnosis. It correctly identifies:

- the absence of a shared page contract;
- deep and inconsistent navigation;
- poor communication of locking and stale state;
- duplicated UI fragments and status vocabularies;
- the collision between staged and live controls in Explore;
- missing empty states and inconsistent primary actions;
- scattered inline styling and inconsistent dark-mode behavior;
- the need to preserve the browser-side reactable patching used by Analyze.

The following recommendations should be retained:

- introduce semantic design tokens;
- create shared R helpers for repeated UI elements;
- promote Report to a top-level destination;
- flatten unnecessary nested navigation;
- show locked and stale states explicitly;
- standardize empty states, model headers, warnings and action buttons;
- add scroll containment and sticky controls to long tables;
- verify browser-side interaction with `chromote`.

### 3.2 Weaknesses and implementation risks

#### The proposed shell is larger than the problem requires

The persistent workflow rail, configuration pane, canvas and status pane amount to a
custom application framework. Implementing it robustly would require custom layout CSS,
responsive behavior, custom navigation state, JavaScript interaction and additional
accessibility work.

This moves EDARK away from the framework behavior supplied and maintained by Shiny and
`bslib`.

#### The fixed four-region layout conflicts with the viewport requirement

The proposed widths are approximately:

- workflow rail: 200px;
- configuration pane: 340px;
- status pane: 300px;
- plus gutters, borders and page margins.

At the required 1280 × 800 viewport (§M9.4 NF-05), too little width would remain for the
tables, plots and model outputs that are the application's main purpose. Collapsing panes
can mitigate this, but doing so introduces more custom behavior.

#### The pane contract contains exceptions and contradictions

The original plan says the status pane contains no inputs, but later moves Prepare's Apply
and Reset controls into it. It says the canvas contains no inputs, although Setup and
Covariate Confirmation necessarily contain interactive inputs inside their reactables.

These exceptions are legitimate, but they weaken the value of enforcing a four-pane shell
on every page.

#### A custom navigation service duplicates existing Shiny behavior

An `active_page` router and custom rail would replace navigation that `page_navbar()`,
`navset_*()` and `bslib::nav_select()` already provide. It would also create another layer
that must remain synchronized with existing shared-state requests and Analyze gating.

#### The implementation order delays visible value

The original plan builds the foundation, component library and shell before migrating a
complete workflow. This creates a long period of infrastructure work before users see a
coherent improvement, and makes it harder to validate whether the shell works well for
real EDARK pages.

---

## 4 — Comparison of the Two Approaches

| Area | Original tri-pane/rail plan | Shiny-native plan |
|---|---|---|
| Main navigation | Custom persistent workflow rail | `page_navbar()` with four top-level stages |
| Page layout | Rail + config + canvas + status | Consistent left sidebar + main result panel |
| Status presentation | Permanent right pane | Inline banner/card near the affected output |
| Routing | New navigation service and `active_page` state | Existing navset IDs and `bslib::nav_select()` |
| Responsive behavior | Custom pane collapsing | Standard `layout_sidebar()` behavior |
| Implementation complexity | High | Moderate |
| Custom HTML/CSS/JS | Substantial | Limited and mostly presentational |
| Canvas width at 1280px | Constrained unless panes collapse | Similar to the current app or wider |
| Workflow visibility | Excellent | Good, using numbered tabs/pills and status text |
| State visibility | Excellent if fully implemented | Improved through standardized inline components |
| Maintenance burden | A custom UI framework must be maintained | Mostly delegated to Shiny and `bslib` |
| Migration risk | High | Lower; modules can be migrated incrementally |

### When the original plan would be preferable

The custom rail and persistent status pane would be justified if EDARK were becoming a
large platform with many datasets, user accounts, saved projects, branching workflows and
multiple simultaneous analyses. In that case a dedicated application shell could provide
enough long-term value to justify its complexity.

For the current single-session Prepare → Explore → Analyze → Report application, the
Shiny-native option is more proportionate.

---

## 5 — Final Recommendation

Use a consistent two-pane Shiny layout inside a four-stage navbar.

```text
┌──────────────────────────────────────────────────────────┐
│ EDARK       Prepare | Explore | Analyze | Report         │
├────────────────────┬─────────────────────────────────────┤
│ CONFIGURE          │ RESULT                              │
│                    │                                     │
│ Required inputs    │ Plot, table, preview or model      │
│ Optional inputs    │                                     │
│ Advanced options ▸ │ Inline status, interpretation and  │
│                    │ next-step guidance as needed        │
│ [Primary action]   │                                     │
└────────────────────┴─────────────────────────────────────┘
```

### 5.1 Application structure

Keep `bslib::page_navbar()` and use four top-level destinations:

1. Prepare
2. Explore
3. Analyze
4. Report

Use a consistent `bslib::layout_sidebar()` within task pages:

- sidebar on the left;
- one standard width, approximately 340–380px;
- required inputs first;
- optional and advanced inputs second;
- one full-width primary action at the bottom;
- results and interpretation in the main panel.

Do not require every page to render an empty sidebar. Read-only summary or export-placeholder
pages may use a full-width result layout, provided the page header and spacing remain
consistent.

### 5.2 Navigation vocabulary

Give each navigation component one meaning:

- navbar: major application stages;
- pills: task modes or ordered workflow steps;
- card tabs: alternate views of one generated result;
- accordions: optional or advanced settings.

Avoid underline tabs and nested pills. Do not use tabs merely to group visual content.

Recommended information architecture:

```text
PREPARE
  Columns | Transforms | Row Filters | Data Preview

EXPLORE
  Describe | Relate | Trend

ANALYZE
  1 Setup | 2 Table 1 | 3 Variables | 4 Covariates | 5 Model | 6 Export

MODEL
  Summary | Create | Diagnostics | Performance | Results

REPORT
  Full Report | Custom Report
```

Model may retain one level of sub-navigation because all five views concern the same fitted
model. Its tabs should use the same visual component used for result facets elsewhere.

Variable Investigation should use either a simple mode selector in the sidebar or ordinary
tabs, rather than pills nested inside the Analyze step pills.

### 5.3 Shared UI helpers

Create `R/ui_helpers.R`, but keep it small and presentational. Suggested helpers:

- `edark_section_label()`;
- `edark_page_header()`;
- `edark_empty_state()`;
- `edark_status_message()`;
- `edark_primary_action()`;
- `edark_model_header()`;
- `edark_aesthetics_controls()`;
- `edark_type_badge()`.

Helpers should return Shiny tag objects. They should not own reactive state, call module
servers or implement a second component framework.

### 5.4 Theme and CSS

Add one small stylesheet or SCSS file under `inst/www/` for:

- spacing and typography tokens;
- semantic status colors;
- consistent sidebar section spacing;
- empty states;
- locked/stale treatments;
- sticky headers and bounded table containers;
- focus-visible styling;
- light/dark color-mode adjustments.

Prefer Bootstrap utility classes and `bslib` theme variables before adding custom CSS.
Custom JavaScript should be limited to behavior Shiny cannot provide, such as the existing
reactable cell patching and progress message handlers.

### 5.5 State and action rules

- Disable actions that cannot succeed and show the reason immediately beside them.
- Use inline messages for persistent errors, warnings and stale results.
- Use notifications only for transient confirmations.
- Every output area must have a useful initial state.
- Use consistent status terms: ready, pending, stale, warning, error and complete.
- Destructive actions continue to require confirmation, and Cancel must restore the UI.

### 5.6 Stage-specific recommendations

#### Prepare

- Keep Apply Changes at the bottom of the left sidebar.
- Show an itemized summary of staged changes above the action.
- Mark affected transform and filter rows as pending.
- Show invalid transform configuration inline on its row.
- Add bounded scrolling and sticky headers to Columns and Transforms.
- Flatten Data Preview to two compact selectors: Original/Working and Data/Summary.

#### Explore

- Use Describe, Relate and Trend as sidebar modes.
- Visually separate plot-definition inputs from a “Plot appearance — updates live”
  accordion.
- Show a guided empty state before the first plot.
- Disable Save, Copy and Add to Report until a plot exists.
- Place the variable summary below or beside the plot according to available width, using
  ordinary Bootstrap grid utilities rather than a permanent status pane.

#### Analyze

- Keep the numbered six-step structure and existing gating logic.
- Standardize the sidebar side and width.
- Show a visible explanation when a step or action is unavailable.
- Preserve interactive inputs inside the Setup and Covariate reactables.
- Use one model-context header across Create, Diagnostics, Performance and Results.
- Use card tabs only for generated-result facets.
- Keep stale-model and changed-spec warnings immediately above the affected results.

#### Report

- Promote Report to a top-level navbar stage.
- Keep Full Report and Custom Report as modes.
- Put Generate & Download at the bottom of both sidebars.
- Use the main panel for the preview and readiness summary.
- Decide explicitly whether report aesthetics inherit Explore settings or remain independent;
  do not preserve the current accidental mixture.

---

## 6 — Staged Implementation

### Stage 0 — Decisions and baseline

- Confirm Report's promotion to the top navbar and update §M4, §M6 and §E accordingly.
- Confirm whether Report aesthetics inherit Explore aesthetics.
- Capture screenshots of every page at 1280 × 800 in light and dark modes.
- Record current gating, stale-state and destructive-confirmation behavior.
- Fix the false custom-report clearing warning before using it as a redesign baseline.

**Acceptance:** the current interface has a documented visual and behavioral baseline; open
design decisions are resolved.

### Stage 1 — Theme and shared helpers

- Add the stylesheet/SCSS token layer.
- Normalize light and dark modes without changing the application's visual identity.
- Add the small helper set from §5.3.
- Replace duplicated section labels, empty states, status messages, aesthetics controls and
  model headers without changing page layouts.
- Standardize primary and secondary button styling.

**Acceptance:** repeated UI patterns have one implementation; no workflow behavior changes;
the app remains usable at 1280 × 800.

### Stage 2 — Standard page layouts

- Move all configuration sidebars to the left.
- Adopt one default sidebar width.
- Order controls required → optional → advanced → primary action.
- Move Full Report's Generate action to the bottom.
- Add consistent page headers and result empty states.
- Add bounded scrolling and sticky controls where long tables require them.

Setup and Covariate Confirmation keep their interactive reactables in the main panel.

**Acceptance:** moving between pages no longer causes the main layout or primary action to
jump unpredictably.

### Stage 3 — Navigation simplification

- Promote Report to a top-level navbar tab.
- Remove the Explore Plot/Report nesting and preserve the View Report navigation request.
- Flatten Data Preview's nested tabs.
- Simplify Variable Investigation navigation.
- Standardize Model sub-navigation and remove the underline-tab idiom.
- Update all affected PRDs and cross-stage navigation descriptions in the same change.

**Acceptance:** navigation has no more than two levels below the navbar; each nav component
has the meaning defined in §5.2; existing gating still works.

### Stage 4 — State, density and accessibility

- Standardize disabled-action reasons and locked-step messages.
- Add itemized pending state to Prepare.
- Add initial and stale empty states to Explore.
- Standardize stale model/result warnings in Analyze.
- Reserve notifications for transient confirmations.
- Verify keyboard navigation, focus visibility and AA contrast.
- Test long datasets and all required viewport sizes.

**Acceptance:** users can tell what is ready, pending, stale or blocked without clicking an
action to discover it; all primary workflows remain usable at 1280 × 800.

---

## 7 — Verification

For every stage:

- run `devtools::check()` with 0 errors and 0 warnings;
- launch with `devtools::load_all(); edark(liver_tx)`;
- inspect at 1280 × 800 and a wider desktop viewport;
- check light and dark modes;
- walk Prepare → Explore → Analyze → Report;
- confirm that primary actions remain explicit and compute-on-click behavior is unchanged;
- verify locked, pending and stale states;
- use `chromote` for Setup and Covariate Confirmation reactable interactions;
- confirm Explore report navigation still reaches the correct Report mode;
- regenerate PPTX, DOCX and HTML reports after Report UI changes.

---

## 8 — Final Decision Summary

The original redesign plan should be treated as a valuable assessment and source of detailed
findings, but not adopted wholesale as the target architecture.

Adopt from it:

- the diagnosis;
- shared UI components;
- semantic theme tokens;
- flatter navigation;
- top-level Report;
- explicit locking, pending and stale states;
- improved table density and accessibility.

Do not adopt at this stage:

- a custom workflow rail;
- an application-level routing service;
- an always-visible status pane;
- a mandatory tri-pane contract for every module;
- responsive behavior that depends on substantial custom JavaScript.

The recommended redesign is a disciplined, consistent use of Shiny and `bslib`, not a new UI
framework built on top of them.
