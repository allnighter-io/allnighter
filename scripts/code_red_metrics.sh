#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY="$ROOT/config/architecture-policy.json"

python3 - "$ROOT" "$POLICY" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
p = json.load(open(sys.argv[2]))
sources = root / 'Packages/AllnighterCore/Sources'
files = [path for path in sources.rglob('*') if path.is_file()]

forbidden = p['forbiddenConcepts'] + p['forbiddenAlternateRootFields']
hits = sum(sum(text.count(term) for term in forbidden) for text in (path.read_text(errors='ignore') for path in files))

# CR-S06 deleted the resident execution control plane outright. The operation
# count is therefore measured by absence: any surviving declaration of the
# operation union anywhere in production is a nonzero count.
operations = []
for path in files:
    operations += re.findall(r'enum\s+(\w*ResidentExecutionOperation)\b', path.read_text(errors='ignore'))
returned = [name for name in p['forbiddenProductionFiles'] if (root / name).is_file()]

owner = root / p['runSemanticsOwnerFile']
owner_declarations = len(re.findall(r'public\s+func\s+run\s*\(', owner.read_text()))
request = owner.read_text().split('public struct RunRequest', 1)[1].split('public enum RunServiceError', 1)[0]
canonical_root_matches = len(re.findall(rf'var\s+{re.escape(p["canonicalRootField"])}\s*:', request))
resident_files = [root / name for name in p['residentProductionFiles']]
loc = sum(len(path.read_text().splitlines()) for path in resident_files)

print(f'forbidden_production_concept_occurrences={hits}')
print(f'resident_operation_case_count={len(operations)}')
print('resident_operation_case_names=' + ','.join(operations))
print(f'deleted_resident_files_returned={len(returned)}')
print('deleted_resident_files_returned_names=' + ','.join(returned))
print(f'run_service_public_run_declarations={owner_declarations}')
print(f'run_request_canonical_root_field_matches={canonical_root_matches}')
print(f'resident_production_loc_current={loc}')
print(f'resident_production_loc_ceiling={p["residentProductionLineCeiling"]}')
print(f'resident_production_loc_closeout_target={p["residentCloseoutLineBudget"]}')
print('resident_production_loc_files=' + ','.join(p['residentProductionFiles']))
PY
