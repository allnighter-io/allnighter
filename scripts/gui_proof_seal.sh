#!/usr/bin/env bash
# GUI Visual Proof Gate — seal a proof packet (run AFTER a layout-watcher PASS).
#
# Binds ONLY the views you explicitly name (`--views`) to this packet as
# PASS, via git blob hashes — never every view that happens to differ from
# BASE. That "auto-bind everything changed" behavior used to let a seal for
# ONE reviewed surface silently attest every other view that happened to be
# dirty in the same working tree, including unreviewed ones. Explicit
# `--views` is the fix: name what the fixtures actually rendered.
#
# Any OTHER view that changed in your diff but was NOT named in --views is
# never marked proven. If it is not already covered by some other proof, it
# is recorded into docs/qa/gui/DEBT.manifest (frozen at its current hash) —
# reported as debt on the next gate run, never silently upgraded to PASS.
#
# Usage:
#   bash scripts/gui_proof_seal.sh <surface> <slug> \
#       --fixtures <fixture> [<fixture>...] \
#       --views <file> [<file>...]
# Example:
#   bash scripts/gui_proof_seal.sh team-dropdown anchor-refactor \
#       --fixtures team-open-mixed \
#       --views Apps/AllnighterMac/Sources/TeamDropdownView.swift
set -euo pipefail
ROOT="${ALLNIGHTER_GUI_PROOF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: gui_proof_seal.sh <surface> <slug> --fixtures <fixture>... --views <file>...
EOF
  exit 2
}

[ "$#" -ge 5 ] || usage
surface="$1"; slug="$2"; shift 2

fixtures=()
views=()
mode=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixtures) mode="fixtures" ;;
    --views) mode="views" ;;
    --*) echo "seal: unknown flag $1" >&2; usage ;;
    *)
      case "$mode" in
        fixtures) fixtures+=("$1") ;;
        views) views+=("$1") ;;
        *) echo "seal: positional argument '$1' before --fixtures/--views" >&2; usage ;;
      esac
      ;;
  esac
  shift
done
[ "${#fixtures[@]}" -ge 1 ] || { echo "seal: at least one --fixtures value required" >&2; usage; }
[ "${#views[@]}" -ge 1 ] || { echo "seal: at least one --views value required (only what the fixtures actually rendered)" >&2; usage; }

SRC_DIR="${ALLNIGHTER_GUI_PROOF_SRC_DIR:-Apps/AllnighterMac/Sources}"
PACKET_ROOT="${ALLNIGHTER_GUI_PROOF_PACKET_ROOT:-docs/qa/gui}"
DEBT_BASELINE_FILE="${ALLNIGHTER_GUI_PROOF_DEBT_BASELINE:-$ROOT/scripts/.gui_proof_debt_baseline}"
DATE="$(date +%F)"
pkt="$PACKET_ROOT/$surface/$DATE-$slug"
mkdir -p "$pkt"

is_view() { grep -qE ':[[:space:]]*View\b|some View\b|:[[:space:]]*App\b|PreviewProvider' "$1"; }

# Validate the named views before touching anything.
for v in "${views[@]}"; do
  [ -f "$v" ] || { echo "seal: no such view file: $v" >&2; exit 1; }
  is_view "$v" || { echo "seal: $v does not look like a visible SwiftUI surface (no View/App/PreviewProvider) — refusing to seal it" >&2; exit 1; }
done

# Copy the rendered capture(s) into the packet.
single=$([ "${#fixtures[@]}" -eq 1 ] && echo 1 || echo 0)
for fx in "${fixtures[@]}"; do
  src="$PACKET_ROOT/_captures/$fx.png"
  [ -s "$src" ] || { echo "seal: missing capture $src — run: bash scripts/gui_proof.sh $fx" >&2; exit 1; }
  dest=$([ "$single" -eq 1 ] && echo "$pkt/native.png" || echo "$pkt/native-$fx.png")
  cp "$src" "$dest"
done

man="$pkt/proof.manifest"
{
  echo "# surface: $surface"
  echo "# fixtures: ${fixtures[*]}"
  echo "# watcher: PASS"
  echo "# sealed: $DATE"
  echo "# Binds ONLY the explicitly reviewed views below to their exact content"
  echo "# hash. Re-editing any of them changes its hash and invalidates this"
  echo "# proof — re-render and re-seal."
  for v in "${views[@]}"; do
    echo "$(git hash-object "$v")  $v"
  done
} > "$man"

# Watcher verdict stub (agent must fill with the real verdict).
if [ ! -f "$pkt/watcher.md" ]; then
  cat > "$pkt/watcher.md" <<EOF
# $surface — layout-watcher verdict

Fixtures: ${fixtures[*]}
Command: bash scripts/gui_proof.sh ${fixtures[0]}

## VERDICT: PASS  (replace with the actual layout-watcher output)

P1 — broken (blocks): none
P2 — advisory:
- (none)
EOF
fi

echo "sealed $pkt"
echo "  fixtures: ${fixtures[*]}"
echo "  bound (proven) views:"
grep -vE '^[[:space:]]*#' "$man" | sed 's/^/    /'
echo "NEXT: paste the layout-watcher's actual verdict into $pkt/watcher.md"

# --- Collateral: views that changed in the same diff but were NOT named
# above. Never silently proven — recorded as DEBT if not already covered by
# some other proof/waiver. ------------------------------------------------
BASE="${ALLNIGHTER_GUI_PROOF_BASE:-HEAD}"
changed_views() {
  { git diff --name-only "$BASE" -- "$SRC_DIR" 2>/dev/null || true
    git ls-files --others --exclude-standard -- "$SRC_DIR" 2>/dev/null || true
  } | sort -u | while IFS= read -r f; do
      case "$f" in *.swift) ;; *) continue ;; esac
      [ -f "$f" ] && is_view "$f" && printf '%s\n' "$f"
    done
}
is_named_view() {
  local target="$1"
  for v in "${views[@]}"; do [ "$v" = "$target" ] && return 0; done
  return 1
}

TMP_ROOT="${ALLNIGHTER_TMPDIR:-/tmp}"
COVER="$(mktemp "$TMP_ROOT/alln-gui-seal-cover.XXXXXX")"
trap 'rm -f "$COVER"' EXIT
while IFS= read -r m; do
  [ -n "$m" ] || continue
  grep -qiE '^#[[:space:]]*watcher:[[:space:]]*PASS\b' "$m" || continue
  grep -vE '^[[:space:]]*#' "$m" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
done < <(find "$PACKET_ROOT" -name proof.manifest 2>/dev/null || true)
if [ -f "$PACKET_ROOT/WAIVERS.manifest" ]; then
  grep -vE '^[[:space:]]*#' "$PACKET_ROOT/WAIVERS.manifest" | awk 'NF>=2 {print $1, $2}' >> "$COVER"
fi

collateral=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_named_view "$f" && continue
  h="$(git hash-object "$f")"
  awk -v h="$h" -v f="$f" '($1==h && $2==f){ok=1} END{exit ok?0:1}' "$COVER" && continue
  collateral+=("$f")
done < <(changed_views)

if [ "${#collateral[@]}" -gt 0 ]; then
  debt_man="$PACKET_ROOT/DEBT.manifest"
  [ -f "$debt_man" ] || printf '# GUI proof DEBT — pre-existing unproven views, frozen at content hash.\n# NOT proof and NOT a waiver. See docs/gui/Visual_Proof_Gate.md.\n' > "$debt_man"
  {
    echo ""
    echo "# --- Recorded by gui_proof_seal.sh ($surface/$DATE-$slug): changed in the"
    echo "# same diff but not named in --views, so not reviewed by this seal. ---"
    for f in "${collateral[@]}"; do
      h="$(git hash-object "$f")"
      if ! grep -qF "$h  $f" "$debt_man" 2>/dev/null; then
        printf '%s  %s\n' "$h" "$f" >> "$debt_man"
      fi
    done
  } >> "$debt_man"
  echo "  ⚠ ${#collateral[@]} other changed view(s) were NOT part of this seal — recorded as DEBT, not proven:"
  for f in "${collateral[@]}"; do echo "      - $f"; done
fi

# --- Ratchet upkeep: if sealing dropped repo-wide debt below the current
# ceiling, tighten it. Never raises it. Best-effort — never fails the seal. -
if [ -f "$DEBT_BASELINE_FILE" ]; then
  find_all_views() {
    find "$SRC_DIR" -name '*.swift' 2>/dev/null | sort | while IFS= read -r f; do
      [ -f "$f" ] || continue
      is_view "$f" && printf '%s\n' "$f"
    done
  }
  new_debt_count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    h="$(git hash-object "$f")"
    awk -v h="$h" -v f="$f" '($1==h && $2==f){ok=1} END{exit ok?0:1}' "$COVER" || new_debt_count=$((new_debt_count + 1))
  done < <(find_all_views)
  ceiling="$(tr -dc '0-9' < "$DEBT_BASELINE_FILE" 2>/dev/null || true)"
  if [ -n "$ceiling" ] && [ "$new_debt_count" -lt "$ceiling" ]; then
    if printf '%s\n' "$new_debt_count" > "$DEBT_BASELINE_FILE" 2>/dev/null; then
      echo "  ratchet: repo-wide debt fell to $new_debt_count — tightened $DEBT_BASELINE_FILE (was $ceiling)"
    fi
  fi
fi
