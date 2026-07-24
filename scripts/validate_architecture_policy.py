#!/usr/bin/env python3
"""Deterministic Code Red architecture-policy validator.

The validator deliberately accepts an arbitrary repository root and policy path so
the shell gate and its fixtures exercise precisely the same implementation.
"""

import argparse
import json
import pathlib
import re
import sys


REQUIRED_KEYS = {
    "version", "productionPaths", "livingTeachingPaths", "excludedPaths",
    "forbiddenConcepts", "forbiddenAlternateRootFields",
    "allowedResidentOperations", "runSemanticsOwner", "runSemanticsOwnerFile",
    "directAdapterFile", "canonicalRootField", "residentProductionFiles",
    "residentProductionLineCeiling", "residentCloseoutLineBudget", "founderOwnedPaths",
    "forbiddenProductionFiles",
}


class PolicyViolation(Exception):
    pass


def fail(message: str) -> None:
    raise PolicyViolation(message)


def load_policy(path: pathlib.Path) -> dict:
    try:
        policy = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read policy: {error}")
    missing = sorted(REQUIRED_KEYS - policy.keys())
    if missing:
        fail(f"policy is missing declared rules: {', '.join(missing)}")
    if policy["version"] != 1:
        fail("unsupported policy version")
    for key in REQUIRED_KEYS - {"version", "residentProductionLineCeiling", "residentCloseoutLineBudget", "runSemanticsOwner", "runSemanticsOwnerFile", "directAdapterFile", "canonicalRootField"}:
        if not isinstance(policy[key], list):
            fail(f"policy rule {key} must be a list")
    return policy


def relative_files(root: pathlib.Path, path_names: list[str], excluded: list[str]) -> list[pathlib.Path]:
    excluded_paths = [root / name for name in excluded]
    files: set[pathlib.Path] = set()
    for name in path_names:
        target = root / name
        if target.is_file():
            candidates = [target]
        elif target.is_dir():
            candidates = [path for path in target.rglob("*") if path.is_file()]
        else:
            fail(f"declared scan path is missing: {name}")
        for candidate in candidates:
            if any(candidate == excluded_path or excluded_path in candidate.parents for excluded_path in excluded_paths):
                continue
            files.add(candidate)
    return sorted(files)


def read_required(root: pathlib.Path, name: str) -> str:
    path = root / name
    if not path.is_file():
        fail(f"required file is missing: {name}")
    return path.read_text()


def validate(root: pathlib.Path, policy_path: pathlib.Path) -> None:
    policy = load_policy(policy_path)
    scan_files = relative_files(
        root,
        policy["productionPaths"] + policy["livingTeachingPaths"],
        policy["excludedPaths"],
    )
    for term in policy["forbiddenConcepts"] + policy["forbiddenAlternateRootFields"]:
        for path in scan_files:
            if term in path.read_text(errors="ignore"):
                fail(f"forbidden term {term!r} found in {path.relative_to(root)}")

    # CR-S06 deleted the resident execution control plane outright, so the
    # operation rule inverts: instead of pinning an allowed set, the gate now
    # proves the whole surface is absent. Each deleted file is named, so a
    # future agent cannot quietly reintroduce one and call it a bug fix.
    returned = [name for name in policy["forbiddenProductionFiles"] if (root / name).is_file()]
    if returned:
        fail(f"deleted resident control-plane file has returned: {', '.join(returned)}")

    if policy["allowedResidentOperations"]:
        # Retained for a future policy that deliberately re-allows a bounded
        # operation set; it must then name the file that declares it.
        resident_text = read_required(root, "Packages/AllnighterCore/Sources/AllnighterCore/ResidentExecution.swift")
        try:
            enum_text = resident_text.split("public enum ResidentExecutionOperation", 1)[1].split("public struct PanelStart", 1)[0]
        except IndexError:
            fail("cannot parse ResidentExecutionOperation")
        operations = re.findall(r"^\s*case\s+(\w+)\(", enum_text, re.M)
        if operations != policy["allowedResidentOperations"]:
            fail(f"resident operation set differs from policy: actual={operations}")
    else:
        for path in scan_files:
            if re.search(r"enum\s+\w*ResidentExecutionOperation", path.read_text(errors="ignore")):
                fail(f"resident operation union redeclared in {path.relative_to(root)}")

    owner_text = read_required(root, policy["runSemanticsOwnerFile"])
    owner_name, _, owner_method = policy["runSemanticsOwner"].partition(".")
    if not owner_name or not owner_method:
        fail("runSemanticsOwner must name a type and method")
    if owner_name not in owner_text:
        fail(f"semantic owner type {owner_name} is missing")
    if len(re.findall(rf"public\s+func\s+{re.escape(owner_method)}\s*\(", owner_text)) != 1:
        fail("RunService semantic owner must declare exactly one public run method")

    adapter_text = read_required(root, policy["directAdapterFile"])
    if "let service = RunService(" not in adapter_text or "await service.run(request" not in adapter_text:
        fail("RunCLI is not a direct RunService adapter")
    if "ResidentExecutionOperation" in adapter_text:
        fail("RunCLI must not route foreground work through resident operations")

    try:
        request_text = owner_text.split("public struct RunRequest", 1)[1].split("public enum RunServiceError", 1)[0]
    except IndexError:
        fail("cannot parse RunRequest")
    if not re.search(rf"var\s+{re.escape(policy['canonicalRootField'])}\s*:", request_text):
        fail("RunRequest is missing the canonical root field declared by policy")
    for field in policy["forbiddenAlternateRootFields"]:
        if field in request_text:
            fail(f"RunRequest contains alternate root field {field}")

    for name in policy["founderOwnedPaths"]:
        if not (root / name).is_file():
            fail(f"founder-owned path is missing: {name}")

    resident_files = [root / name for name in policy["residentProductionFiles"]]
    missing = [str(path.relative_to(root)) for path in resident_files if not path.is_file()]
    if missing:
        fail(f"resident production file set is incomplete: {', '.join(missing)}")
    loc = sum(len(path.read_text().splitlines()) for path in resident_files)
    if loc > policy["residentProductionLineCeiling"]:
        fail(f"resident production LOC {loc} exceeds CR-S01 ceiling {policy['residentProductionLineCeiling']}")
    if policy["residentCloseoutLineBudget"] > policy["residentProductionLineCeiling"]:
        fail("closeout LOC target cannot exceed the current phase ceiling")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--policy", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        validate(args.root.resolve(), args.policy.resolve())
    except PolicyViolation as error:
        print(f"architecture-policy: {error}", file=sys.stderr)
        return 1
    print("architecture-policy: passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
