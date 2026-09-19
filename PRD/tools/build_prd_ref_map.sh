#!/usr/bin/env bash
# Build the PRD section map and the reference inventory for the docs_mod migration.
# READ-ONLY with respect to the repo: writes only into docs_mod/.
#
# Outputs:
#   docs_mod/prd_section_map.csv        old section -> new section (one row per old section)
#   docs_mod/prd_reference_inventory.csv every § reference outside the old PRDs, with its new form
#
# Run from the repo root:  bash docs_mod/tools/build_prd_ref_map.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

ANALYSIS_PRD="PRD/EDARK_Analysis_Module_PRD.md"
MAP="docs_mod/prd_section_map.csv"
INV="docs_mod/prd_reference_inventory.csv"

# ── 1. Section map ────────────────────────────────────────────────────────────
{
  echo "old_doc,old_section,old_title,new_doc,new_section,note"

  # Analysis PRD: rule-based. §N.M -> §AN.M ; Global Mandates -> §A0 ; §13.x -> §M8.x
  echo "analysis,Global Mandates,\"Global Mandates — Code Paradigms and Conventions\",PRD_3_Analyze.md,§A0,\"package list moved to §M9.1\""
  perl -ne '
    if (/^## Section (\d+) — (.*)$/) {
      my ($n,$t)=($1,$2); $t=~s/"/""/g;
      if ($n==13) { print "analysis,§13,\"$t\",PRD_0_Master.md,§M8,\"moved: spans Prepare and Analyze\"\n"; }
      else        { print "analysis,§$n,\"$t\",PRD_3_Analyze.md,§A$n,\n"; }
    }
    elsif (/^### (\d+)\.(\d+)(?:–(\d+)\.(\d+))? (.*)$/) {
      my ($a,$b,$c,$d,$t)=($1,$2,$3,$4,$5); $t=~s/"/""/g;
      my $old = defined $c ? "§$a.$b–$c.$d" : "§$a.$b";
      if ($a==13) { my $new = "§M8.$b"; print "analysis,$old,\"$t\",PRD_0_Master.md,$new,\n"; }
      else { my $new = defined $c ? "§A$a.$b–A$c.$d" : "§A$a.$b"; print "analysis,$old,\"$t\",PRD_3_Analyze.md,$new,\n"; }
    }' "$ANALYSIS_PRD"

  # v0.2 PRD: hand-mapped (content was rewritten, not renumbered)
  cat <<'EOF'
v02,§1,"Overview",PRD_0_Master.md,§M1,
v02,§1.1,"Purpose",PRD_0_Master.md,§M1.1,
v02,§1.2,"Target Users",PRD_0_Master.md,§M1.2,
v02,§1.3,"Design Principles",PRD_0_Master.md,§M2,
v02,§2.1,"Application Entry Point",PRD_0_Master.md,§M4.3,
v02,§2.2,"Prepare Stage",PRD_1_Prepare.md,§P4–P7,"column mgmt §P4, transforms §P5, filters §P6, apply §P7"
v02,§2.3,"Explore Stage: Single Variable",PRD_2_Explore.md,§E3,"trend part -> §E5"
v02,§2.4,"Explore Stage: Bivariate",PRD_2_Explore.md,§E4,
v02,§2.5,"Programmatic Report API",PRD_2_Explore.md,§E15,
v02,§2.6,"Summary Statistics",PRD_2_Explore.md,§E6.1,"SS-01 dataset overview -> §P8; SS-03 Table One -> §E11.2 / §A (Table 1)"
v02,§2.7,"Dataset Export",PRD_1_Prepare.md,§P9,
v02,§3,"Non-Functional Requirements",PRD_0_Master.md,§M9.4,
v02,§4.1,"R Packages",PRD_0_Master.md,§M9.1,
v02,§4.2,"Column Auto-Cast Rules",PRD_1_Prepare.md,§P2.2,
v02,§4.3,"Plot Type Routing",PRD_2_Explore.md,§E4,"stratification table -> §E8.4"
v02,§4.4,"Module Architecture",PRD_0_Master.md,§M5,
v02,§4.5,"Data Flow",PRD_0_Master.md,§M6,"pipeline order specifically -> §P7.2"
v02,§4.6,"File Structure",PRD_0_Master.md,§M9.2,"per-file map -> CLAUDE.md"
v02,§5.1,"Layout",PRD_0_Master.md,§M4.1,
v02,§5.2,"Stage 1: Prepare",PRD_1_Prepare.md,§P3,
v02,§5.3,"Stage 2: Explore — Sidebar",PRD_2_Explore.md,§E2,
v02,§5.4,"Stage 2: Explore — Main Panel",PRD_2_Explore.md,§E6,
v02,§5.5,"Loading Indicators",PRD_0_Master.md,§M3.5,
v02,§6,"Visualization Specification",PRD_2_Explore.md,§E8,
v02,§6.1,"Architecture",PRD_0_Master.md,§M2.2,"one static ggplot engine"
v02,§6.2,"Plot Themes",PRD_2_Explore.md,§E7,
v02,§6.3,"Color Palettes",PRD_2_Explore.md,§E7,
v02,§6.4,"Plot-Specific Behaviors",PRD_2_Explore.md,§E8.1,
v02,§7,"Report Generation Specification",PRD_2_Explore.md,§E13,
v02,§7.5,"PDF",PRD_0_Master.md,§M10.1,"PDF is out of scope"
v02,§8,"Out of Scope for v2",PRD_0_Master.md,§M10.1,
EOF
} > "$MAP"

# ── 2. Reference inventory ────────────────────────────────────────────────────
# Files that point INTO the old PRDs. The old PRDs themselves are superseded, not edited.
# man/*.Rd is regenerated from R/ by devtools::document(), so it is not listed.
FILES=$(ls R/*.R CLAUDE.md PRD/EDARK_Analysis_Build_Plan.md "PRD/Codex proofing.md" .claude/*.md 2>/dev/null || true)

{
  echo "file,line,old_ref,target_doc,new_ref,context"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    FILE="$f" perl -ne '
      BEGIN {
        # References in these file:line spots point at the v0.2 PRD, not the Analysis PRD.
        %v02 = ("R/build_plot_spec.R:76" => "§E4", "R/module_prepare_confirm.R:7" => "§P7.2");
      }
      my $line = $.;
      my $ctx = $_; chomp $ctx; $ctx =~ s/"/""/g; $ctx =~ s/^\s+//; $ctx = substr($ctx, 0, 120);
      # ranges first (keep \enc{–}{-} and plain –), then singles
      while (/(§(\d+)(\.\d+)?(?:(?:–|\\enc\{–\}\{-\})(\d+)(\.\d+)?)?)/g) {
        my ($ref,$a,$b,$c,$d) = ($1,$2,$3,$4,$5);
        my $key = "$ENV{FILE}:$line";
        my ($doc,$new);
        if (exists $v02{$key}) { $doc = "v02"; $new = $v02{$key}; }
        else {
          $doc = "analysis";
          my $sep = ($ref =~ /\\enc/) ? "\\enc{–}{-}" : "–";
          if ($a == 13) {
            $new = "§M8" . ($b // "");
            $new .= $sep . "M8" . ($d // "") if defined $c;
          }
          else {
            $new = "§A$a" . ($b // "");
            $new .= $sep . "A$c" . ($d // "") if defined $c;
          }
        }
        print "\"$ENV{FILE}\",$line,\"$ref\",$doc,\"$new\",\"$ctx\"\n";
      }
      if (/Global Mandates/) { print "\"$ENV{FILE}\",$line,\"Global Mandates\",analysis,\"§A0\",\"$ctx\"\n"; }
    ' "$f"
  done <<< "$FILES"
} > "$INV"

echo "Section map:  $(($(wc -l < "$MAP") - 1)) rows -> $MAP"
echo "Inventory:    $(($(wc -l < "$INV") - 1)) references -> $INV"
