# replace-plotly: risks and test checklist

## Functionality losses (expected, not bugs)
- **No zoom/pan/hover tooltips** — plotly gave those for free. `plotOutput` renders a static PNG. For a clinical EDA tool this is probably fine, but worth knowing it's gone.

---

## Things that could silently break

**1. Plot sizing / responsiveness**
`plotlyOutput` renders in a resizable HTML widget. `plotOutput` renders a fixed-size PNG. We need `width = "100%"` on `plotOutput`, otherwise it'll be a narrow fixed box on wide screens. Also: patchwork divides the two-panel plot into 45/55 at render time — if the `plotOutput` container is too narrow, panels will look squashed.

**2. waiter spinner**
`waiter::waiter_on_busy()` is placed inside the card body next to the plot output. It hooks into Shiny's busy state generically, so it *should* still fire during `renderPlot`. But this is untested — worth explicitly verifying it appears during computation.

**3. `shared_state$active_plot` contents change**
`current_plot()` stores the return value of `render_plot()` in `shared_state$active_plot` (line 133). Currently for histogram_density this is an `edark_two_panel` list; after this change it'll be a patchwork. Nothing currently consumes `active_plot` (the report module isn't built yet), but if anything checks `inherits(active_plot, "edark_two_panel")` elsewhere it would break.

**4. `spec_now` isolation in the new `renderPlot`**
The `renderPlotly` block reads `shared_state$plot_specification` with `isolate()` to avoid a double-reactive dependency. The new `renderPlot` block needs the same pattern — otherwise reading `shared_state$plot_specification` inside `renderPlot` creates a second reactive dependency separate from `current_plot()`, meaning the render triggers twice on spec changes. The plan uses `isolate()` here — confirmed correct.

---

## Things native ggplot2 handles differently (mostly fixes, but test each)

**5. `guide = "none"` on scales now works**
`scale_fill_brewer(guide = "none")` was ignored by ggplotly. With `renderPlot`, it will be honoured. Bar charts (`bar_count`, `bar_grouped`) use this to suppress the fill legend — they should now correctly show no legend. Test: do they look right?

**6. Legend position on the density panel (histogram_density stratified)**
The unresolved density legend bug from CLAUDE.md should resolve automatically. But verify: does the legend actually appear on the left density panel with a factor stratify? Does toggling show/hide work?

**7. Annotation positioning in `scatter_loess` (correlation stats)**
The anchor point was placed with no hjust/vjust specifically because ggplotly ignores those hints. With native ggplot2, `annotate()` default hjust = 0.5 (center) is applied, so text IS centered on the anchor — which happens to be what we wanted. Should look the same or better. Test: does the R²/r/p annotation appear clearly and not overlap the data?

**8. QQ plot `coord_cartesian(ylim = ...)` clamping**
This was added to stop plotly over-expanding the y-axis during `subplot()`. With native rendering it's harmless but may make the QQ plot slightly tight at the extremes. Worth checking it doesn't clip real data points.

---

## Things that could cause `devtools::check()` to fail

**9. Any remaining `plotly::` calls in source**
After removal, `R CMD check` will error on any `plotly::` call if `plotly` is no longer in Imports. Need to grep all R files to confirm zero plotly calls remain before removing from DESCRIPTION.

**10. `ggpubr` in Imports but possibly unused**
Pre-existing issue, unrelated to this change — but if `check()` warns about unused imports this could surface.

---

## Test matrix

| Scenario | Risk |
|---|---|
| Numeric describe, no stratify | Two-panel histogram+QQ renders, sizing OK |
| Numeric describe + factor stratify | Density left, faceted QQ right, legend on left only |
| Factor describe, no stratify | Bar chart, no legend (guide="none" now honoured) |
| Factor describe + stratify | Faceted bars |
| Numeric × numeric correlate | Scatter+loess, annotation visible |
| Numeric × numeric + stratify | Faceted scatter, legend suppressed |
| Factor × numeric correlate | Violin+jitter, legend always suppressed |
| Factor × factor correlate | Grouped bars |
| Legend toggle | Show/hide + position (top/bottom/left/right) affects all non-suppressed plots |
| Palette change | Re-render triggers, colours update |
| Waiter spinner | Appears during computation |
| Window resize | Plot fills container width |
