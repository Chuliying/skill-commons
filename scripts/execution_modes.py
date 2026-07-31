#!/usr/bin/env python3
"""Single accessor for Execution Mode stage contracts (ADR-R3).

Every consumer that needs to know which artifacts a mode requires reads them here.
The data itself lives in protocol-registry.json; this module only resolves and shapes
it. Invariant I-M1 is "one stage list": a consumer that keeps its own tuple of
artifact names will drift from the registry silently, because both halves keep looking
correct in isolation -- the grader once accepted a five-artifact team-feature roster
while the registry declared a different contract.

Stdlib only, so the journey harness and the work-item validator can both import it
without a dependency step.
"""

from __future__ import annotations

import json
from pathlib import Path

REGISTRY_PATH = Path(__file__).resolve().parent.parent / "protocol-registry.json"
SCHEMA_VERSION = "skill-commons/protocol-registry/v1"

# Artifact name -> (stage name in meta.yml, canonical file path within the work item).
# The registry names artifacts; a work item names stages. This is the only place the
# two vocabularies are joined.
ARTIFACT_STAGES = {
    "prd": ("prd", "prd.md"),
    "spec": ("spec", "spec.md"),
    "qa-plan": ("qa-plan", "qa-plan.md"),
    "plan": ("plan", "plan/plan.md"),
    "implement-report": ("implement", "implement-report.md"),
    "qa-report": ("qa-report", "qa-report.md"),
}


def load_registry(path: Path = REGISTRY_PATH) -> dict:
    """Read and version-check the registry. A wrong schema fails closed."""
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot load protocol registry {path}: {exc}") from exc
    if registry.get("schema_version") != SCHEMA_VERSION:
        raise RuntimeError(f"unsupported protocol registry schema: {path}")
    return registry


REGISTRY = load_registry()
_MODES = REGISTRY["execution_modes"]


def mode_names() -> list[str]:
    return sorted(_MODES)


def is_mode(name: str) -> bool:
    return name in _MODES


def stage_requirements(mode: str) -> dict[str, str]:
    """Artifact name -> one of required | optional | absent, for one mode."""
    spec = _MODES.get(mode)
    if not isinstance(spec, dict):
        raise KeyError(f"unknown execution mode: {mode}")
    return {name: entry["requirement"] for name, entry in spec["artifacts"].items()}


def _artifacts_with(mode: str, requirement: str) -> list[str]:
    return sorted(
        name for name, value in stage_requirements(mode).items() if value == requirement
    )


def required_artifacts(mode: str) -> list[str]:
    return _artifacts_with(mode, "required")


def optional_artifacts(mode: str) -> list[str]:
    return _artifacts_with(mode, "optional")


def absent_artifacts(mode: str) -> list[str]:
    return _artifacts_with(mode, "absent")


def producers(mode: str, artifact: str) -> list[str]:
    """Skills allowed to own an artifact's stage in a given mode."""
    return list(_MODES[mode]["artifacts"][artifact]["producers"])


def canonical_file(artifact: str) -> str:
    """Work-item-relative path an artifact must occupy."""
    return ARTIFACT_STAGES[artifact][1]


def stage_name(artifact: str) -> str:
    return ARTIFACT_STAGES[artifact][0]


def required_files(mode: str) -> list[str]:
    """Canonical paths a completed work item in this mode must carry.

    This is what a grader or a closeout check should iterate, instead of restating
    the filenames.
    """
    return [canonical_file(name) for name in required_artifacts(mode)]


def flow(mode: str) -> str:
    return _MODES[mode]["flow"]
