# CLAUDE.md — Shiny UI Principles

## App pattern

This applies to apps with a common workflow:

1. configure inputs (sidebar)
2. trigger an action
3. view results (main panel)
4. optionally export/share

Design for this flow explicitly.

---

## Core rules

- Organize UI around **user tasks**, not data structures
- Make **required vs optional inputs obvious**
- Keep **one primary action per screen**
- Prefer **clarity over flexibility**
- Reduce visual noise aggressively

---

## Layout

### Structure
- Sidebar = setup
- Main panel = results + interpretation

Do not overload the sidebar with explanation or multiple unrelated tasks.

---

### Sidebar

Keep it:
- flat (minimal borders)
- compact
- vertically scannable

Group controls into:

1. required inputs
2. optional inputs (visually secondary)
3. single primary action

Avoid:
- many nested boxes
- equal emphasis on all controls
- long unstructured stacks

---

### Sections

Use simple grouping:
- small uppercase section labels
- 1–3 related controls per section
- whitespace for separation

Do not wrap every section in a card.

---

## Actions

- One **primary button** (filled)
- Secondary actions = outline or subtle
- Avoid multiple competing primary buttons

---

## Inputs

- Use **consistent input types and styling**
- Do not mix visually different components without normalizing them
- Keep input height, spacing, and alignment uniform

---

## Task separation

If the app supports different actions (e.g., describe vs compare vs trend):

→ split into **tabs or modes**

Do not cram multiple workflows into one sidebar.

---

## Defaults

- Preselect sensible values
- Let users get output quickly
- Hide advanced options behind collapsible sections

---

## Main panel

- Should never feel empty
- Show:
  - results
  - summaries
  - context
- Use empty states to guide users

---

## Visual hierarchy

Use:
- spacing
- typography

Avoid:
- excessive borders
- excessive icons
- decorative styling

---

## Common failure modes to avoid

- “form dump” sidebar
- too many buttons
- inconsistent input styling
- unclear primary action
- mixing multiple workflows in one panel
- everything looking equally important

---

## Guiding principle

The UI should feel like:
> a guided tool that helps the user complete one task at a time

Not:
> a collection of controls the user has to figure out