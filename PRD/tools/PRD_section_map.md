# PRD Section Map — Old → New

How section references move from the two old PRDs to the `docs_mod/` set, and where the repo refers to them.

## Numbering Scheme

Every section ID now carries its document's prefix, so a reference is unambiguous anywhere in the repo:

| Prefix | Document |
|---|---|
| §M | `PRD_0_Master.md` |
| §P | `PRD_1_Prepare.md` |
| §E | `PRD_2_Explore.md` (Plot + Report) |
| §A | `PRD_3_Analyze.md` |
| §N | `NOTE_implementation.md` |

## Mapping Rules

**Old Analysis PRD** (`PRD/EDARK_Analysis_Module_PRD.md`) — numbering kept, prefix added:
- `§N` / `§N.M` → `§AN` / `§AN.M` (sections 1–12). Ranges map both ends: `§7.6–7.8` → `§A7.6–A7.8`.
- "Global Mandates" → `§A0` (its package list moved to §M9.1).
- `§13.x` (session save/load) → `§M8.x` — moved to the Master PRD because it spans stages.

**Old v0.2 PRD** (`PRD/EDARK V0.2 - PRD.md`) — rewritten, so mapped by hand. Summary:

| Old | New | Old | New |
|---|---|---|---|
| §1, §1.1, §1.2 | §M1, §M1.1, §M1.2 | §4.1 packages | §M9.1 |
| §1.3 design principles | §M2 | §4.2 auto-cast | §P2.2 |
| §2.1 entry point | §M4.3 | §4.3 plot routing | §E4 |
| §2.2 Prepare | §P4–P7 | §4.4 module architecture | §M5 |
| §2.3 single variable | §E3 (trend → §E5) | §4.5 data flow | §M6 (pipeline order → §P7.2) |
| §2.4 bivariate | §E4 | §4.6 file structure | §M9.2 + CLAUDE.md |
| §2.5 report API | §E15 | §5.1 layout | §M4.1 |
| §2.6 summary statistics | §E6.1 | §5.2 Prepare UI | §P3 |
| §2.7 dataset export | §P9 | §5.3 / §5.4 Explore UI | §E2 / §E6 |
| §3 non-functional | §M9.4 | §5.5 loading indicators | §M3.5 |
| §6 visualisation | §E8 (themes/palettes §E7) | §7 reports | §E13 (PDF → out of scope §M10.1) |
| §8 out of scope | §M10.1 | | |

Full per-section list: [prd_section_map.csv](prd_section_map.csv).

## Where the Old References Are

[prd_reference_inventory.csv](prd_reference_inventory.csv) lists every reference outside the old PRDs — file, line, old ref, which old PRD it points to, new ref, and the line's text. Current totals (129):

| File(s) | References | Notes |
|---|---|---|
| `PRD/EDARK_Analysis_Build_Plan.md` | 88 | Header says "All section references (§) refer to the PRD" — change to `docs_mod/PRD_3_Analyze.md` (and §M for Phase S) |
| `R/*.R` roxygen and comments | 36 across 17 files | Two point at the **v0.2** PRD, not the Analysis PRD: `R/build_plot_spec.R:76` (§4.3 → §E4) and `R/module_prepare_confirm.R:7` (§4.5 → §P7.2) |
| `CLAUDE.md` | 4 | Moot once CLAUDE.md is replaced by `docs_mod/CLAUDE.md` |
| `PRD/Codex proofing.md` | 1 | §4.2 → §A4.2 |

`man/*.Rd` is generated from R/ roxygen; after replacing refs in R/, run `devtools::document()`. Roxygen writes en dashes as `\enc{–}{-}`; the inventory keeps that form.

## Regenerating

The inventory is a snapshot, and other work is still editing these files. Re-run before replacing:

```bash
bash docs_mod/tools/build_prd_ref_map.sh
```

The script only reads the repo and writes the two CSVs in `docs_mod/`.

## Replacement Plan (not yet done)

1. Re-run the script.
2. Replace each inventory row's `old_ref` with `new_ref` on that exact `file:line` (line-scoped, so the two v0.2 refs map correctly). Also change "PRD §" wording where it names the old file.
3. Update the build plan header and any links to the old PRD file names.
4. `devtools::document()`; `devtools::check()`.
5. Move the old PRDs to `PRD/archive/` and the `docs_mod/` files to their final home.
