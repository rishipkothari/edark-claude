# RESOLVED — EDARK v0.9

Closed TO-DOs, with the root cause and whatever was learned fixing them.

Open TO-DOs live in the root `CLAUDE.md`. When one closes, move it here in full and
delete it there — the root file is loaded into every session, so it carries only open
work. Keep entries newest-first within each area, headed with the close date.

Consult this file when a bug smells familiar, before re-deriving a fix.

---

## Prepare

### 2026-09-24 — transform → row filter → transform did not warn on stage

Root cause was one line shared by `.build_prepare_warnings()` and
`.prune_conflicting_filter_specs()`: both derived the changed-transform set from
`names(specs)`, the *currently staged* transforms, so a transform that had been REMOVED
since the last Apply was never tested.

Worst case was cutpoints -> filter on the bands -> remove the cutpoints: the categorical
filter survived onto a column that was numeric again, matched no rows, and Apply produced
an empty dataset with no warning.

Both now use `union(names(specs), names(last_tx))`, and `.apply_row_filters()` skips a
filter whose `type` disagrees with the column as a backstop.

**Durable rule: §N3.4.**

---

## Explore

### 2026-09-25 - report progress bar filled twice for Word and PowerPoint

Full Report counted to n twice for Word and PowerPoint ("Variable i of n", then
"Section i of n"), and once for HTML. Custom Report did the same ("Item", then "Slide").

Root cause: the section builders and the PPT / Word assemblers were handed the same
`progress_fn` and each reported `i / n` over the whole bar. `.assemble_html()` reports
nothing (one `rmarkdown::render()` call), which is why HTML looked right.

Fix: `.progress_span()` gives each pass its own share of the bar - building 0-60% and
writing 60-100% for PPT / Word, building 0-90% for HTML - and the labels name the pass
("Building plots: variable i of n", "Writing slides: section i of n").

**Durable rule: §N5.1.**

### 2026-09-25 - Report contents option: collinearity investigation

Full Report gains a **Collinearity** checkbox (default off). It runs Analyze's
`compute_collinearity()` over Table One's variable set and renders the three pieces of
Step 3's Collinearity pill: Pearson heatmap (numerics), Cramer's V heatmap (factors),
pairs above 0.7. Placed after Table One in PPT, Word and HTML.

The two heatmaps were inline in Step 3's `renderPlot()`s; they moved to
`service_analysis_plots.R` so the app and the report draw the same figure. Known gap
carried over from Step 3: numeric x factor pairs are not measured.

**Durable rule: §N5.5.**

### 2026-09-24 — Word report: reference `.docx` template with defined heading styles

`inst/templates/word_docx_blank_template.docx` now supplies the Title / Subtitle /
heading 1-9 styles, and `.assemble_docx()` builds a real document on top of them: title
page, a Word TOC field that populates from the headings (heading 1 = Table 1 / Dataset
Summary / the section group, heading 2 = each variable), a running header naming the
document, a page number bottom-right, and four page sections so the dataset summary is
landscape and everything else portrait. Per-variable summary tables are laid out at 18pt.

Two things worth knowing:

- Word's NUMPAGES field counts *within a section*, so the footer is "Page N" and not
  "Page N of M".
- Word's own table autofit wrecks a table wider than the page, so `.docx_fit_ft()`
  computes the widths in R and `.docx_shrink_widths()` takes the overflow out of the
  widest columns only.

**Durable rule: §N5.7.**

---

## Analyze

_Nothing closed yet._

---

## Other

### 2026-09-25 - first-launch delay: splash screen

The app took a visibly long time to become usable on launch. Temporary `[edark boot]`
instrumentation in `edark()` timed each phase, and the first reading was misread: the gap
from `edark()` to the browser's page request looked like 7-18 s of startup, but it was the
user walking from the R console to the browser to hit refresh. **Only the browser-side
numbers, which anchor on the page request, meant anything.**

Measured from the page request: 2.4 s warm, 4.1 s cold. Roughly 0.5 s of that is Shiny
building and sending the HTML (theme compile included), 0.5-2.3 s is wiring the module
servers, and ~1.1 s is computing the initial outputs. All of it lands after the page
arrives, so a splash in the page HTML covers effectively the whole gap - the theme
precompiling that was considered as an alternative would have bought ~0.5 s.

Built as `edark_splash()` (`R/ui_helpers.R`) plus section 9 of `edark.css`, not with
`waiter`, which is for busy-spinners over outputs. The instrumentation was removed.

**Durable rule: §N1.16.**


### 2026-09-24 — roxygen errors on every `devtools::document()`

Two unrelated causes.

1. `DESCRIPTION` sets `Roxygen: list(markdown = TRUE)`, and markdown mode escapes `%` for
   you, so a hand-written `\%` came out of roxygen as `\\%` - a literal backslash followed
   by an Rd comment that ate the rest of the line, including the closing `}` of the
   `\item{}` it sat in. That is what made `man/liver_tx.Rd` report every later `\item` as
   an unknown macro and every later section header as unexpected, and what roxygen called
   mismatched braces in `stats_inference.R`. **Write a plain `%` in roxygen comments.**
2. Markdown links like `[edark_run_gate()]` become real `\link{}` cross-references, but
   every helper in `R/ui_helpers.R` is `@keywords internal` + `@noRd` and so has no man
   page to link to. **Undocumented internals are referred to with a code span** -
   `` `edark_run_gate()` `` - not a link.

**Durable rule: §N1.13.**

### 2026-09-23 — RHS pane was tied to the main pane; three independent panes wanted

Root cause was not the pane structure: bslib ships
`.bslib-card .card-body { max-height: var(--bslib-card-body-max-height, none) }`, two
classes to `.edark-scroll-table`'s one, so any scroll cap put directly on a `card_body`
lost on specificity and the content grew without limit. That blew out the CSS grid row the
centre and info panes share, stretching the info pane to match (1660 px on Prepare ›
Columns) and forcing the whole document to scroll.

**Cap the content - never the `card_body` itself.** That fixes all three panes at once.
Convention and the three containment mechanisms are in the header comment on
`.edark-scroll-table` (`inst/www/edark.css`) and `EDARK_RESULT_HEIGHT` (`R/ui_helpers.R`).

**Durable rule: §N1.12.**

### 2026-09-23 — UI consistency plan (all six stages)

All six stages of [BUILD_UI-redesign.md](BUILD_UI-redesign.md) are done: honest
step-locking, a shared component library (`R/ui_helpers.R`), one plain-CSS theme file
(`inst/www/edark.css`), a config (left) / result / info (right) page contract with a
dedicated messages area, and flatter navigation. Report stays inside Explore. `bslib` + R
+ CSS only - no SCSS, no new JS.

The one decision left open by Stage 5 was **ruled 2026-09-23**: Explore › Report's Full /
Custom stay underline tabs (level 3b), not the config-pane pills D8 originally named,
because that is the third nested level and consistency at a level beats the D8 wording.
See Stage 5's build note in `BUILD_UI-redesign.md`.

### 2026-09-23 — nine step pills wrapped to two rows

There are six steps, and with "3 · Variables" / "4 · Covariates" they fit one row at
1280 px (Stage 5).

### 2026-09-25 - full report tables described the dataset, not the report

Dataset Summary was built from every numeric/factor column in the working dataset and
Table One from the selected variables only in Describe mode, where it was also the only
mode that offered the checkbox. Both now follow the report contents:

- `content_vars` = selected variables, plus the primary variable in Correlate mode
  (it appears in every section).
- **Table One** = `content_vars` minus the stratify variable, which is the column header.
- **Dataset Summary** = `content_vars` plus the stratify variable.

`.build_dataset_summary()` gained an optional `variables` argument; NULL keeps the
whole-dataset behaviour that Prepare > Data Preview and the custom report rely on.
Table One's `report_type == "all_vars"` gate is gone from `generate_report()` and from
the Report module's checkbox, info row, and call, so Correlate reports can carry one.
