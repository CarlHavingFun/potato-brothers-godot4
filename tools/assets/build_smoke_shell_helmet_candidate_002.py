"""Build the deterministic Smoke-Shell Helmet review candidate 002."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import tempfile
from collections.abc import Sequence
from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CANDIDATE_ID = "candidate-002"
ASSET_ID = "smoke_shell_helmet"
SHARED_SCALE = 0.625
FRAME_SIZE = (128, 128)
ICON_SIZE = (256, 256)
ATLAS_SIZE = (1024, 128)
LOCKED_NIKO_HASH = "fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d"
OUTLINE_COLORS_RGB = (
    (8, 5, 3),
    (9, 0, 0),
    (21, 13, 6),
    (29, 27, 24),
    (34, 34, 31),
)
DEFAULT_CARD_FONT_REGULAR = Path("C:/Windows/Fonts/msyh.ttc")
DEFAULT_CARD_FONT_BOLD = Path("C:/Windows/Fonts/msyhbd.ttc")
TRANSACTION_MARKER = ".candidate-transaction.json"
APPROVAL_UPDATE_LOCK = ".candidate-approval-update.lock"
REVIEW_FOOTER_TEXT = (
    "REVIEW EVIDENCE ONLY — no curated, runtime, or startup integration"
)
REGISTRY_ARTIFACT_PREFIX = (
    "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/"
    "smoke_shell_helmet/candidate-002/"
)
RUBRIC_DIMENSIONS = (
    "identity",
    "function",
    "material",
    "hierarchy",
    "originality",
)
REGISTRY_REFRESH_GUARD_SCHEMA = "gogobro-registry-refresh-guard-v2"
APPROVED_BINDINGS_SCHEMA = "gogobro-approved-candidate-bindings-v1"
APPROVED_AT_UTC = "2026-08-24T12:04:47Z"
APPROVED_AT_UTC_PATTERN = re.compile(
    r"^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"
    r"T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"
)
REGISTRY_REFRESH_EXCLUDED_FIELDS = (
    "units[smoke_shell_helmet].candidate_history[candidate-002].source_sha256.registry",
)
ARTIFACT_PATHS = (
    "derived/icon-256.png",
    "derived/appearance-128.png",
    "appearance/anchors-walk-down.json",
    "qa/composite-frame-001.png",
    "qa/composite-atlas-8x128.png",
    "qa/runtime-size-1920x1080.png",
    "qa/harmony-overlay.png",
    "qa/harmony-actual-size.png",
    "qa/harmony-report.json",
    "qa/visual-rubric.json",
    "qa/pixel-qa-report.json",
    "qa/approval-card.png",
)
ARTIFACT_ROLES = {
    "derived/icon-256.png": "icon",
    "derived/appearance-128.png": "appearance",
    "appearance/anchors-walk-down.json": "anchors",
    "qa/composite-frame-001.png": "composite_frame",
    "qa/composite-atlas-8x128.png": "composite_atlas",
    "qa/runtime-size-1920x1080.png": "runtime_preview",
    "qa/harmony-overlay.png": "harmony_overlay",
    "qa/harmony-actual-size.png": "harmony_actual_size",
    "qa/harmony-report.json": "harmony_report",
    "qa/visual-rubric.json": "visual_rubric",
    "qa/pixel-qa-report.json": "pixel_qa_report",
    "qa/approval-card.png": "approval_card",
}


@dataclass(frozen=True)
class BuildInputs:
    appearance_source: Path
    niko_atlas: Path
    rig_profile: Path
    registry: Path
    output_root: Path
    card_font_regular: Path = DEFAULT_CARD_FONT_REGULAR
    card_font_bold: Path = DEFAULT_CARD_FONT_BOLD


@dataclass(frozen=True)
class CandidateMetadata:
    candidate_id: str
    transform: dict[str, object]
    artifacts: Sequence[dict[str, object]]
    metrics: dict[str, object]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _approved_bindings_path() -> Path:
    return _repo_root() / "tools/assets/approved_candidate_bindings_v1.json"


def _load_checker() -> object:
    checker_path = (
        _repo_root()
        / "tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py"
    )
    spec = importlib.util.spec_from_file_location("gogobro_item_harmony_checker", checker_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("checker_import_failed")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): _sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def _has_candidate_files(root: Path) -> bool:
    ignored = {
        APPROVAL_UPDATE_LOCK,
        TRANSACTION_MARKER,
        f"{TRANSACTION_MARKER}.tmp",
    }
    return root.is_dir() and any(
        path.is_file() and path.relative_to(root).as_posix() not in ignored
        for path in root.rglob("*")
    )


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_json_bytes(payload))


def _json_bytes(payload: object) -> bytes:
    return (
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def _read_object(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def _canonical_json_bytes(payload: object) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _is_lower_sha256(value: object) -> bool:
    return (
        type(value) is str
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _load_approved_binding() -> dict[str, object]:
    payload = _read_object(_approved_bindings_path())
    if set(payload) != {"schema_version", "bindings"}:
        raise ValueError("invalid_approved_candidate_bindings")
    bindings = payload.get("bindings")
    if payload.get("schema_version") != APPROVED_BINDINGS_SCHEMA or type(bindings) is not list:
        raise ValueError("invalid_approved_candidate_bindings")
    matches = [
        binding
        for binding in bindings
        if type(binding) is dict
        and binding.get("asset_id") == ASSET_ID
        and binding.get("candidate_id") == CANDIDATE_ID
    ]
    if len(matches) != 1 or len(bindings) != 1:
        raise ValueError("invalid_approved_candidate_bindings")
    binding = matches[0]
    if set(binding) != {
        "asset_id",
        "candidate_id",
        "approval_event",
        "artifacts",
        "review_registry_normalized_sha256",
        "review_source_registry_sha256",
    }:
        raise ValueError("invalid_approved_candidate_bindings")
    event = binding.get("approval_event")
    expected_event = {
        "approved_at_utc": APPROVED_AT_UTC,
        "authority": "explicit_user_approval_in_current_task",
        "candidate_id": CANDIDATE_ID,
        "decision": "approved",
    }
    if type(event) is not dict or event != expected_event or set(event) != set(expected_event):
        raise ValueError("invalid_approved_candidate_bindings")
    artifacts = binding.get("artifacts")
    if (
        not _is_lower_sha256(binding.get("review_registry_normalized_sha256"))
        or not _is_lower_sha256(binding.get("review_source_registry_sha256"))
    ):
        raise ValueError("invalid_approved_candidate_bindings")
    if type(artifacts) is not list or len(artifacts) != len(ARTIFACT_PATHS):
        raise ValueError("invalid_approved_candidate_bindings")
    for expected_path, artifact in zip(ARTIFACT_PATHS, artifacts, strict=True):
        if (
            type(artifact) is not dict
            or set(artifact) != {"path", "role", "bytes", "sha256"}
            or artifact.get("path") != expected_path
            or artifact.get("role") != ARTIFACT_ROLES[expected_path]
            or type(artifact.get("bytes")) is not int
            or artifact["bytes"] <= 0
            or not _is_lower_sha256(artifact.get("sha256"))
        ):
            raise ValueError("invalid_approved_candidate_bindings")
    return copy.deepcopy(binding)


def _source_hashes(inputs: BuildInputs, candidate_001_hashes: dict[str, str]) -> dict[str, object]:
    return {
        "appearance_source": _sha256(inputs.appearance_source),
        "card_font_bold": _sha256(inputs.card_font_bold),
        "card_font_regular": _sha256(inputs.card_font_regular),
        "niko_atlas": _sha256(inputs.niko_atlas),
        "rig_profile": _sha256(inputs.rig_profile),
        "registry": _sha256(inputs.registry),
        "candidate_001_tree": candidate_001_hashes,
    }


def _validate_inputs(inputs: BuildInputs) -> Path:
    for path in (
        inputs.appearance_source,
        inputs.niko_atlas,
        inputs.rig_profile,
        inputs.registry,
        inputs.card_font_regular,
        inputs.card_font_bold,
        _approved_bindings_path(),
    ):
        if not path.is_file():
            raise FileNotFoundError(path)
    candidate_001 = inputs.appearance_source.resolve().parents[1]
    output = inputs.output_root.resolve()
    if output == candidate_001 or candidate_001 in output.parents:
        raise ValueError("output_root_overlaps_candidate_001")
    if _sha256(inputs.niko_atlas) != LOCKED_NIKO_HASH:
        raise ValueError("niko_atlas_hash_mismatch")
    return candidate_001


def _registry_artifacts_from_metadata(
    metadata: dict[str, object],
) -> list[dict[str, object]]:
    artifacts = metadata.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != len(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_metadata")
    expected_artifacts: list[dict[str, object]] = []
    seen_paths: set[str] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ValueError("invalid_candidate_metadata")
        relative = artifact.get("path")
        if (
            not isinstance(relative, str)
            or relative not in ARTIFACT_PATHS
            or relative in seen_paths
            or artifact.get("role") != ARTIFACT_ROLES[relative]
        ):
            raise ValueError("invalid_candidate_metadata")
        seen_paths.add(relative)
        expected_artifacts.append(
            {**artifact, "path": REGISTRY_ARTIFACT_PREFIX + relative}
        )
    if seen_paths != set(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_metadata")
    return expected_artifacts


def _candidate_records_match_allowing_registry_self_hash(
    registered: dict[str, object],
    expected: dict[str, object],
) -> bool:
    """Compare candidate content while excluding only the registry's self-hash."""
    normalized: list[dict[str, object]] = []
    for candidate in (registered, expected):
        candidate_copy = copy.deepcopy(candidate)
        source_sha256 = candidate_copy.get("source_sha256")
        if type(source_sha256) is not dict or not _is_lower_sha256(
            source_sha256.get("registry")
        ):
            return False
        source_sha256["registry"] = "<candidate-002-source-registry-sha256>"
        normalized.append(candidate_copy)
    return _canonical_json_bytes(normalized[0]) == _canonical_json_bytes(normalized[1])


def _expected_registered_candidate(
    metadata: dict[str, object],
) -> dict[str, object]:
    card_rendering = metadata.get("card_rendering")
    if not isinstance(card_rendering, dict):
        raise ValueError("invalid_candidate_metadata")
    return {
        "artifacts": _registry_artifacts_from_metadata(metadata),
        "candidate_id": CANDIDATE_ID,
        "decision": "review",
        "font_provenance": card_rendering.get("fonts"),
        "harmony_verdict": metadata.get("harmony_verdict"),
        "metrics": metadata.get("metrics"),
        "reasons": [],
        "report_verdicts": {
            "harmony": metadata.get("harmony_verdict"),
            "pixel_qa_passed": True,
        },
        "source_sha256": metadata.get("source_sha256"),
        "transform": metadata.get("transform"),
        "visual_rubric_sha256": metadata.get("visual_rubric_sha256"),
    }


def _project_registered_registry(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> dict[str, object]:
    projected = copy.deepcopy(registry)
    unit = _registry_unit(projected)
    history = unit.get("candidate_history")
    if not isinstance(history, list):
        raise ValueError("invalid_registry_history")
    matches = [
        index
        for index, candidate in enumerate(history)
        if isinstance(candidate, dict) and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    expected = _expected_registered_candidate(metadata)
    if not matches:
        history.append(expected)
    elif len(matches) == 1:
        history[matches[0]] = expected
    else:
        raise ValueError("duplicate_candidate_id")
    unit["active_candidate_id"] = CANDIDATE_ID
    _registry_approval_snapshot(unit)
    return projected


def _registry_approval_snapshot(unit: dict[str, object]) -> dict[str, object]:
    """Return the immutable review/approval state without rewriting history."""
    status = unit.get("approval_status")
    if status == "review":
        if "approval_history" in unit:
            raise ValueError("review_registry_has_approval_history")
        return {"approval_status": "review", "approval_history": []}
    if status != "approved":
        raise ValueError("unsupported_candidate_approval_status")
    history = unit.get("approval_history")
    if type(history) is not list or len(history) != 1:
        raise ValueError("invalid_approval_history")
    event = history[0]
    if (
        type(event) is not dict
        or set(event)
        != {"candidate_id", "decision", "authority", "approved_at_utc"}
        or event.get("candidate_id") != CANDIDATE_ID
        or event.get("decision") != "approved"
        or event.get("authority") != "explicit_user_approval_in_current_task"
        or not _is_rfc3339_utc(event.get("approved_at_utc"))
        or event.get("approved_at_utc") != APPROVED_AT_UTC
    ):
        raise ValueError("invalid_approval_history")
    return {
        "approval_status": "approved",
        "approval_history": copy.deepcopy(history),
    }


def _is_rfc3339_utc(value: object) -> bool:
    if type(value) is not str or APPROVED_AT_UTC_PATTERN.fullmatch(value) is None:
        return False
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return False
    return True


def _metadata_approval_snapshot(
    registry_snapshot: dict[str, object],
) -> dict[str, object] | None:
    has_status = "approval_status" in registry_snapshot
    has_history = "approval_history" in registry_snapshot
    if not has_status or not has_history:
        return None
    status = registry_snapshot.get("approval_status")
    history = registry_snapshot.get("approval_history")
    if status == "review" and history == []:
        return {"approval_status": "review", "approval_history": []}
    if status == "approved" and type(history) is list:
        return {
            "approval_status": "approved",
            "approval_history": copy.deepcopy(history),
        }
    return None


def _guard_registry_for_approval_transition(
    registry: dict[str, object],
    recorded: dict[str, object],
    current: dict[str, object],
) -> dict[str, object] | None:
    return registry if recorded == current else None


def _normalized_registered_registry(
    registry: dict[str, object],
) -> dict[str, object]:
    normalized = copy.deepcopy(registry)
    unit = _registry_unit(normalized)
    history = unit.get("candidate_history")
    if type(history) is not list:
        raise ValueError("invalid_registry_history")
    matches = [
        candidate
        for candidate in history
        if type(candidate) is dict and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    if len(matches) != 1:
        raise ValueError("candidate_002_registry_count")
    active = matches[0]
    artifacts = active.get("artifacts")
    if type(artifacts) is not list or len(artifacts) != len(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_artifacts")
    seen_paths: set[str] = set()
    for artifact in artifacts:
        if type(artifact) is not dict:
            raise ValueError("invalid_candidate_artifacts")
        raw_path = artifact.get("path")
        if type(raw_path) is not str or not raw_path.startswith(REGISTRY_ARTIFACT_PREFIX):
            raise ValueError("invalid_candidate_artifacts")
        relative = raw_path[len(REGISTRY_ARTIFACT_PREFIX) :]
        byte_count = artifact.get("bytes")
        artifact_sha256 = artifact.get("sha256")
        if (
            relative not in ARTIFACT_PATHS
            or relative in seen_paths
            or artifact.get("role") != ARTIFACT_ROLES[relative]
            or type(byte_count) is not int
            or byte_count < 0
            or not _is_lower_sha256(artifact_sha256)
        ):
            raise ValueError("invalid_candidate_artifacts")
        seen_paths.add(relative)
    if seen_paths != set(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_artifacts")
    source_sha256 = active.get("source_sha256")
    if type(source_sha256) is not dict or not _is_lower_sha256(
        source_sha256.get("registry")
    ):
        raise ValueError("invalid_candidate_source_sha256")
    source_sha256["registry"] = "<candidate-002-source-registry-sha256>"
    if "visual_rubric_sha256" not in active:
        raise ValueError("invalid_candidate_visual_rubric_sha256")
    visual_rubric_sha256 = active.get("visual_rubric_sha256")
    metrics = active.get("metrics")
    if type(metrics) is not dict:
        raise ValueError("invalid_candidate_metrics")
    metrics_has_rubric = "visual_rubric_sha256" in metrics
    if visual_rubric_sha256 is not None and not _is_lower_sha256(
        visual_rubric_sha256
    ):
        raise ValueError("invalid_candidate_visual_rubric_sha256")
    if metrics_has_rubric and not _is_lower_sha256(
        metrics.get("visual_rubric_sha256")
    ):
        raise ValueError("invalid_candidate_metrics")
    if visual_rubric_sha256 is None and metrics_has_rubric:
        raise ValueError("invalid_candidate_metrics")
    return normalized


def _approved_review_registry_digest(registry: dict[str, object]) -> str:
    """Bind every review-registry semantic except its unavoidable self-hash."""
    prior_review = copy.deepcopy(registry)
    unit = _registry_unit(prior_review)
    approval = _registry_approval_snapshot(unit)
    if approval["approval_status"] == "approved":
        unit["approval_status"] = "review"
        unit.pop("approval_history", None)
    normalized = _normalized_registered_registry(prior_review)
    return hashlib.sha256(_canonical_json_bytes(normalized)).hexdigest()


def _registry_refresh_guard(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> dict[str, object]:
    normalized = _normalized_registered_registry(
        _project_registered_registry(registry, metadata)
    )
    return {
        "excluded_fields": list(REGISTRY_REFRESH_EXCLUDED_FIELDS),
        "normalized_sha256": hashlib.sha256(
            _canonical_json_bytes(normalized)
        ).hexdigest(),
        "schema_version": REGISTRY_REFRESH_GUARD_SCHEMA,
    }


def _registry_refresh_guard_matches(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> bool:
    registry_snapshot = metadata.get("registry_snapshot")
    if not isinstance(registry_snapshot, dict):
        return False
    guard = registry_snapshot.get("refresh_guard")
    if not isinstance(guard, dict):
        return False
    expected_sha256 = guard.get("normalized_sha256")
    if (
        guard.get("schema_version") != REGISTRY_REFRESH_GUARD_SCHEMA
        or guard.get("excluded_fields") != list(REGISTRY_REFRESH_EXCLUDED_FIELDS)
        or not isinstance(expected_sha256, str)
        or len(expected_sha256) != 64
    ):
        return False
    try:
        current_normalized = _normalized_registered_registry(registry)
    except ValueError:
        return False
    return (
        hashlib.sha256(_canonical_json_bytes(current_normalized)).hexdigest()
        == expected_sha256
    )


def _registered_candidate_matches_metadata(
    registry_path: Path,
    output_root: Path,
    metadata: dict[str, object],
) -> bool:
    try:
        expected_active = _expected_registered_candidate(metadata)
    except ValueError:
        return False
    for artifact in metadata["artifacts"]:
        relative = artifact["path"]
        path = output_root / relative
        if (
            not path.is_file()
            or path.stat().st_size != artifact.get("bytes")
            or _sha256(path) != artifact.get("sha256")
        ):
            return False

    registry = _read_object(registry_path)
    unit = _registry_unit(registry)
    history = unit.get("candidate_history")
    if not isinstance(history, list):
        return False
    active_matches = [
        candidate
        for candidate in history
        if isinstance(candidate, dict) and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    if len(active_matches) != 1:
        return False
    active = active_matches[0]
    registry_snapshot = metadata.get("registry_snapshot")
    if not isinstance(registry_snapshot, dict):
        return False
    recorded_approval = _metadata_approval_snapshot(registry_snapshot)
    if recorded_approval is None:
        return False
    try:
        approval_snapshot = _registry_approval_snapshot(unit)
    except ValueError:
        return False
    guard_registry = _guard_registry_for_approval_transition(
        registry,
        recorded_approval,
        approval_snapshot,
    )
    if guard_registry is None:
        return False
    return (
        unit.get("active_candidate_id") == CANDIDATE_ID
        and unit.get("effects") == registry_snapshot.get("effects")
        and unit.get("localization") == registry_snapshot.get("localization")
        and _candidate_records_match_allowing_registry_self_hash(
            active,
            expected_active,
        )
        and _registry_refresh_guard_matches(guard_registry, metadata)
    )


def _approved_evidence_is_complete(
    output_root: Path,
    metadata: dict[str, object],
) -> bool:
    rubric_sha256 = metadata.get("visual_rubric_sha256")
    metrics = metadata.get("metrics")
    source_sha256 = metadata.get("source_sha256")
    projected_artifacts = _bound_artifact_projection(
        metadata.get("artifacts"),
        registry_paths=False,
    )
    if (
        metadata.get("asset_id") != ASSET_ID
        or metadata.get("candidate_id") != CANDIDATE_ID
        or metadata.get("harmony_verdict") != "harmony_pass"
        or metadata.get("reason_codes") != []
        or not _is_lower_sha256(rubric_sha256)
        or type(metrics) is not dict
        or metrics.get("visual_rubric_sha256") != rubric_sha256
        or type(source_sha256) is not dict
        or projected_artifacts is None
    ):
        return False
    artifacts_by_path = {
        str(artifact["path"]): artifact for artifact in projected_artifacts
    }
    try:
        report = _read_object(output_root / "qa/harmony-report.json")
        pixel_qa = _read_object(output_root / "qa/pixel-qa-report.json")
        rubric_bytes = (output_root / "qa/visual-rubric.json").read_bytes()
    except (OSError, UnicodeError, ValueError):
        return False
    input_sha256 = report.get("input_sha256")
    report_metrics = report.get("metrics")
    checks = pixel_qa.get("checks")
    return (
        hashlib.sha256(rubric_bytes).hexdigest() == rubric_sha256
        and report.get("verdict") == "harmony_pass"
        and report.get("reason_codes") == []
        and type(input_sha256) is dict
        and input_sha256.get("visual_rubric") == rubric_sha256
        and input_sha256.get("character_atlas") == source_sha256.get("niko_atlas")
        and input_sha256.get("rig_profile") == source_sha256.get("rig_profile")
        and input_sha256.get("appearance")
        == artifacts_by_path["derived/appearance-128.png"]["sha256"]
        and input_sha256.get("icon")
        == artifacts_by_path["derived/icon-256.png"]["sha256"]
        and input_sha256.get("anchors")
        == artifacts_by_path["appearance/anchors-walk-down.json"]["sha256"]
        and type(report_metrics) is dict
        and report_metrics.get("visual_rubric_sha256") == rubric_sha256
        and pixel_qa.get("candidate_id") == CANDIDATE_ID
        and pixel_qa.get("passed") is True
        and type(checks) is dict
        and bool(checks)
        and all(value is True for value in checks.values())
    )


def _bound_artifact_projection(
    artifacts: object,
    *,
    registry_paths: bool,
) -> list[dict[str, object]] | None:
    if type(artifacts) is not list or len(artifacts) != len(ARTIFACT_PATHS):
        return None
    projected: list[dict[str, object]] = []
    for expected_path, artifact in zip(ARTIFACT_PATHS, artifacts, strict=True):
        if type(artifact) is not dict:
            return None
        path = artifact.get("path")
        if registry_paths:
            if type(path) is not str or not path.startswith(REGISTRY_ARTIFACT_PREFIX):
                return None
            path = path[len(REGISTRY_ARTIFACT_PREFIX) :]
        projected_artifact = {
            "bytes": artifact.get("bytes"),
            "path": path,
            "role": artifact.get("role"),
            "sha256": artifact.get("sha256"),
        }
        if (
            path != expected_path
            or projected_artifact["role"] != ARTIFACT_ROLES[expected_path]
            or type(projected_artifact["bytes"]) is not int
            or projected_artifact["bytes"] <= 0
            or not _is_lower_sha256(projected_artifact["sha256"])
        ):
            return None
        projected.append(projected_artifact)
    return projected


def _approved_binding_matches(
    registry: dict[str, object],
    output_root: Path,
    metadata: dict[str, object],
    approval_snapshot: dict[str, object],
) -> bool:
    binding = _load_approved_binding()
    bound_artifacts = binding["artifacts"]
    if (
        approval_snapshot.get("approval_history") != [binding["approval_event"]]
        or _approved_review_registry_digest(registry)
        != binding["review_registry_normalized_sha256"]
        or _bound_artifact_projection(
            metadata.get("artifacts"),
            registry_paths=False,
        )
        != bound_artifacts
    ):
        return False
    unit = _registry_unit(registry)
    history = unit.get("candidate_history")
    if type(history) is not list or unit.get("active_candidate_id") != CANDIDATE_ID:
        return False
    active = [
        candidate
        for candidate in history
        if type(candidate) is dict and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    active_source = active[0].get("source_sha256") if len(active) == 1 else None
    if (
        len(active) != 1
        or type(active_source) is not dict
        or active_source.get("registry") != binding["review_source_registry_sha256"]
        or _bound_artifact_projection(
            active[0].get("artifacts"),
            registry_paths=True,
        )
        != bound_artifacts
    ):
        return False
    for artifact in bound_artifacts:
        if type(artifact) is not dict:
            return False
        path = output_root / str(artifact["path"])
        if (
            not path.is_file()
            or path.stat().st_size != artifact["bytes"]
            or _sha256(path) != artifact["sha256"]
        ):
            return False
    return True


def _candidate_metadata_from_payload(
    metadata: dict[str, object],
) -> CandidateMetadata:
    artifacts = metadata.get("artifacts")
    transform = metadata.get("transform")
    metrics = metadata.get("metrics")
    if (
        type(artifacts) is not list
        or type(transform) is not dict
        or type(metrics) is not dict
    ):
        raise ValueError("invalid_candidate_metadata")
    return CandidateMetadata(
        candidate_id=CANDIDATE_ID,
        transform=copy.deepcopy(transform),
        artifacts=copy.deepcopy(artifacts),
        metrics=copy.deepcopy(metrics),
    )


def _reuse_approved_candidate(
    inputs: BuildInputs,
    source_hashes: dict[str, object],
    registry: dict[str, object],
    approval_snapshot: dict[str, object],
) -> CandidateMetadata:
    registry_path = inputs.registry
    output_root = inputs.output_root
    if not _has_candidate_files(output_root):
        raise ValueError("approved_registry_requires_existing_candidate")
    metadata_path = output_root / "candidate-metadata.json"
    if not metadata_path.is_file():
        raise ValueError("approved_registry_requires_existing_candidate")
    try:
        metadata = _read_object(metadata_path)
    except (OSError, UnicodeError, ValueError):
        raise ValueError("approved_candidate_metadata_mismatch") from None
    registry_snapshot = metadata.get("registry_snapshot")
    if type(registry_snapshot) is not dict:
        raise ValueError("approved_candidate_metadata_mismatch")
    recorded_approval = _metadata_approval_snapshot(registry_snapshot)
    if recorded_approval == {"approval_status": "review", "approval_history": []}:
        raise ValueError("approved_candidate_requires_explicit_package_migration")
    if (
        recorded_approval != approval_snapshot
        or metadata.get("source_sha256") != source_hashes
        or not _approved_evidence_is_complete(output_root, metadata)
        or not _approved_binding_matches(
            registry,
            output_root,
            metadata,
            approval_snapshot,
        )
        or not _registered_candidate_matches_metadata(
            registry_path,
            output_root,
            metadata,
        )
    ):
        raise ValueError("approved_candidate_provenance_mismatch")
    return _candidate_metadata_from_payload(metadata)


def _assert_reusable_output(
    output_root: Path,
    source_hashes: dict[str, object],
    registry_path: Path,
) -> None:
    if not _has_candidate_files(output_root):
        return
    metadata_path = output_root / "candidate-metadata.json"
    if not metadata_path.is_file():
        raise ValueError("non_empty_output_missing_metadata")
    metadata = _read_object(metadata_path)
    if metadata.get("candidate_id") != CANDIDATE_ID:
        raise ValueError("candidate_id_mismatch")
    recorded_hashes = metadata.get("source_sha256")
    legacy_hashes = {
        key: value
        for key, value in source_hashes.items()
        if key not in {"card_font_regular", "card_font_bold"}
    }
    legacy_font_upgrade = (
        recorded_hashes == legacy_hashes and "card_rendering" not in metadata
    )
    if recorded_hashes == source_hashes or legacy_font_upgrade:
        return
    if isinstance(recorded_hashes, dict):
        recorded_without_registry = {
            key: value for key, value in recorded_hashes.items() if key != "registry"
        }
        current_without_registry = {
            key: value for key, value in source_hashes.items() if key != "registry"
        }
        registered_refresh = (
            recorded_without_registry == current_without_registry
            and recorded_hashes.get("registry") != source_hashes.get("registry")
            and _registered_candidate_matches_metadata(
                registry_path,
                output_root,
                metadata,
            )
        )
        if registered_refresh:
            return
    raise ValueError("source_hash_mismatch")


def _load_images(inputs: BuildInputs) -> tuple[Image.Image, Image.Image]:
    with Image.open(inputs.appearance_source) as opened:
        appearance = opened.convert("RGBA")
    with Image.open(inputs.niko_atlas) as opened:
        atlas = opened.convert("RGBA")
    if appearance.size != FRAME_SIZE:
        raise ValueError("appearance_dimensions")
    if atlas.size != ATLAS_SIZE:
        raise ValueError("atlas_dimensions")
    return appearance, atlas


def _build_anchors(checker: object, appearance: Image.Image, profile: dict[str, object]) -> dict[str, object]:
    rendered_appearance = _scaled_appearance(appearance)
    aperture = checker.find_largest_enclosed_transparent_region(rendered_appearance)
    aperture_center = (
        aperture.left + (aperture.right - aperture.left - 1) / 2,
        aperture.top + (aperture.bottom - aperture.top - 1) / 2,
    )
    frames = profile.get("frames")
    if not isinstance(frames, list) or len(frames) != 8:
        raise ValueError("rig_frame_count")
    anchor_frames: list[dict[str, object]] = []
    for index, frame in enumerate(frames):
        if not isinstance(frame, dict):
            raise ValueError("invalid_rig_frame")
        face_center = frame.get("face_center")
        if not isinstance(face_center, list) or len(face_center) != 2:
            raise ValueError("invalid_face_center")
        offset = [
            round(float(face_center[0]) - aperture_center[0]),
            round(float(face_center[1]) - aperture_center[1]),
        ]
        anchor_frames.append(
            {
                "depth": 40,
                "frame_index": index,
                "frame_name": f"walk_down_{index + 1:02d}",
                "offset": offset,
                "scale": SHARED_SCALE,
            }
        )
    return {
        "algorithm": {
            "feature": "largest four-connected enclosed transparent aperture in exact nearest-resized raster",
            "offset": "round(face_center - nearest-resized aperture_center)",
            "resampling": "nearest for QA composite only; source appearance remains unchanged",
        },
        "asset_id": ASSET_ID,
        "candidate_id": CANDIDATE_ID,
        "flip_behavior": "none",
        "frame_count": 8,
        "frames": anchor_frames,
        "occupied_slots": [],
        "pixel_contract": {
            "appearance_grid_scale": 2,
            "icon_grid_scale": 4,
            "logical_canvas": [64, 64],
            "outline_colors_rgb": [list(color) for color in OUTLINE_COLORS_RGB],
            "resampling": "nearest",
        },
        "schema_version": "gogobro-item-anchors-v1",
        "shared_scale": SHARED_SCALE,
        "slot": "head",
    }


def _scaled_appearance(appearance: Image.Image) -> Image.Image:
    size = (round(appearance.width * SHARED_SCALE), round(appearance.height * SHARED_SCALE))
    return appearance.resize(size, Image.Resampling.NEAREST)


def _compose_atlas(atlas: Image.Image, appearance: Image.Image, anchors: dict[str, object]) -> Image.Image:
    composite = atlas.copy()
    scaled = _scaled_appearance(appearance)
    for frame in anchors["frames"]:
        index = int(frame["frame_index"])
        offset_x, offset_y = (int(value) for value in frame["offset"])
        frame_image = composite.crop((index * 128, 0, (index + 1) * 128, 128))
        frame_image.alpha_composite(scaled, dest=(offset_x, offset_y))
        composite.paste(frame_image, (index * 128, 0))
    return composite


def _save_runtime_preview(composite: Image.Image, path: Path) -> None:
    canvas = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 760, 1919, 1079), fill=(33, 42, 52, 255))
    enlarged = composite.resize((1024 * 3, 128 * 3), Image.Resampling.NEAREST)
    frame = enlarged.crop((0, 0, 384, 384))
    canvas.alpha_composite(frame, dest=((1920 - 384) // 2, 520))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def _image_checks(image: Image.Image) -> dict[str, object]:
    pixels = list(image.get_flattened_data())
    alpha_values = sorted({pixel[3] for pixel in pixels})
    opaque_colors = sorted({pixel[:3] for pixel in pixels if pixel[3]})
    return {
        "alpha_values": alpha_values,
        "binary_alpha": all(value in (0, 255) for value in alpha_values),
        "opaque_color_count": len(opaque_colors),
        "transparent_rgb_zero": all(
            pixel[:3] == (0, 0, 0) for pixel in pixels if pixel[3] == 0
        ),
    }


def _effect_labels(effects: object) -> list[str]:
    labels: list[str] = []
    operations = {
        "armor": ("护甲", "Armor", ""),
        "move_speed_pct": ("移速", "Move Speed", "%"),
    }
    if not isinstance(effects, list):
        return labels
    for effect in effects:
        if not isinstance(effect, dict):
            continue
        operation = str(effect.get("operation", ""))
        value = effect.get("value")
        if operation not in operations or not isinstance(value, int | float):
            labels.append(json.dumps(effect, ensure_ascii=False, sort_keys=True))
            continue
        zh_name, en_name, suffix = operations[operation]
        sign = "+" if value > 0 else "−" if value < 0 else ""
        magnitude = abs(value)
        rendered = str(int(magnitude)) if float(magnitude).is_integer() else str(magnitude)
        labels.append(f"{sign}{rendered}{suffix} {zh_name} / {sign}{rendered}{suffix} {en_name}")
    return labels


def _registry_unit(registry: dict[str, object]) -> dict[str, object]:
    units = registry.get("units")
    if not isinstance(units, list):
        raise ValueError("registry_units_missing")
    matches = [unit for unit in units if isinstance(unit, dict) and unit.get("asset_id") == ASSET_ID]
    if len(matches) != 1:
        raise ValueError("registry_asset_missing")
    return matches[0]


def _font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    if not path.is_file():
        raise FileNotFoundError(path)
    return ImageFont.truetype(str(path), size)


def _draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int, int],
    max_width: int,
    line_gap: int = 8,
) -> int:
    words = text.split(" ")
    lines: list[str] = []
    current = ""
    for word in words:
        proposed = word if not current else f"{current} {word}"
        if current and draw.textbbox((0, 0), proposed, font=font)[2] > max_width:
            lines.append(current)
            current = word
        else:
            current = proposed
    if current:
        lines.append(current)
    x, y = xy
    height = draw.textbbox((0, 0), "Ag", font=font)[3] + line_gap
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        y += height
    return y


def _approval_card(
    icon: Image.Image,
    appearance: Image.Image,
    composite: Image.Image,
    unit: dict[str, object],
    report: object,
    font_regular: Path,
    font_bold: Path,
) -> Image.Image:
    card = Image.new("RGBA", (1800, 1200), (15, 19, 27, 255))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((48, 48, 1752, 1152), radius=28, fill=(25, 32, 44, 255), outline=(75, 94, 120, 255), width=3)
    title_font = _font(font_bold, 54)
    heading_font = _font(font_bold, 30)
    body_font = _font(font_regular, 25)
    small_font = _font(font_regular, 20)
    draw.text((92, 82), "Smoke-Shell Helmet / 封烟头盔", font=title_font, fill=(236, 242, 250, 255))
    unit_status = str(unit.get("approval_status", "review"))
    status_text = (
        f"Harmony gate: {report.verdict} | Unit approval status: {unit_status}"
    )
    draw.text((94, 154), f"{CANDIDATE_ID}  •  {status_text}", font=heading_font, fill=(113, 210, 182, 255))

    draw.rounded_rectangle((92, 220, 492, 680), radius=18, fill=(12, 16, 23, 255))
    draw.text((120, 248), "Canonical icon", font=heading_font, fill=(228, 235, 244, 255))
    card.alpha_composite(icon, dest=(164, 310))
    draw.text((120, 592), "256×256 at exact 1:1 — no resampling", font=small_font, fill=(177, 190, 208, 255))

    draw.rounded_rectangle((520, 220, 1708, 680), radius=18, fill=(12, 16, 23, 255))
    draw.text((552, 248), "8-frame Niko walk-down composite — exact 1:1", font=heading_font, fill=(228, 235, 244, 255))
    card.alpha_composite(composite, dest=(600, 300))
    draw.text((600, 450), "Appearance 128×128", font=small_font, fill=(177, 190, 208, 255))
    draw.text((600, 474), "exact 1:1 • unchanged", font=small_font, fill=(177, 190, 208, 255))
    card.alpha_composite(appearance, dest=(600, 500))
    draw.text((930, 450), "Runtime frame 001", font=small_font, fill=(177, 190, 208, 255))
    draw.text((930, 474), "128×128 actual 1:1", font=small_font, fill=(177, 190, 208, 255))
    card.alpha_composite(composite.crop((0, 0, 128, 128)), dest=(930, 500))
    draw.text((1110, 505), "True gameplay pixel size", font=heading_font, fill=(236, 198, 94, 255))
    draw.text((1110, 552), "Face aperture and shell hierarchy", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1110, 584), "are judged without display scaling.", font=small_font, fill=(177, 190, 208, 255))

    localization = unit.get("localization", {})
    zh = localization.get("zh_CN", {}) if isinstance(localization, dict) else {}
    en = localization.get("en", {}) if isinstance(localization, dict) else {}
    y = 726
    draw.text((92, y), "Approved copy", font=heading_font, fill=(228, 235, 244, 255))
    y += 48
    for text in (
        str(zh.get("description", "")),
        str(zh.get("flavor", "")),
        str(en.get("description", "")),
        str(en.get("flavor", "")),
    ):
        y = _draw_wrapped(draw, text, (92, y), body_font, (204, 214, 227, 255), 980)
        y += 4

    draw.text((1190, 726), "Structured effects", font=heading_font, fill=(228, 235, 244, 255))
    effect_y = 782
    for label in _effect_labels(unit.get("effects")):
        draw.text((1190, effect_y), label, font=body_font, fill=(246, 198, 94, 255))
        effect_y += 48
    metrics = report.metrics
    draw.text((1190, 914), f"Scale: {SHARED_SCALE}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 948), f"Outer ratio: {metrics['outer_width_ratio']:.6f}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 982), f"Feature error: {metrics['max_feature_center_error_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 1016), f"Residual jitter: {metrics['max_residual_jitter_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text(
        (92, 1092),
        REVIEW_FOOTER_TEXT,
        font=heading_font,
        fill=(239, 116, 116, 255),
    )
    return card


def _approval_card_evidence(unit: dict[str, object], report: object) -> dict[str, object]:
    unit_status = str(unit.get("approval_status", "review"))
    return {
        "appearance": {
            "box": [600, 500, 728, 628],
            "display_scale": 1,
            "resampling": "none",
            "source": "derived/appearance-128.png",
        },
        "composite": {
            "box": [600, 300, 1624, 428],
            "display_scale": 1,
            "resampling": "none",
            "source": "qa/composite-atlas-8x128.png",
        },
        "caption_boxes": {
            "appearance": [600, 450, 850, 496],
            "runtime_actual_size": [930, 450, 1140, 496],
        },
        "icon": {
            "box": [164, 310, 420, 566],
            "display_scale": 1,
            "resampling": "none",
            "source": "derived/icon-256.png",
        },
        "runtime_actual_size": {
            "box": [930, 500, 1058, 628],
            "display_scale": 1,
            "resampling": "none",
            "source": "qa/composite-frame-001.png",
        },
        "footer_text": REVIEW_FOOTER_TEXT,
        "status_text": (
            f"Harmony gate: {report.verdict} | Unit approval status: {unit_status}"
        ),
    }


def _default_visual_rubric() -> dict[str, object]:
    return {
        name: {"evidence": "", "score": 0}
        for name in RUBRIC_DIMENSIONS
    }


def _blank_visual_rubric_bytes() -> bytes:
    return _json_bytes(_default_visual_rubric())


def _committed_visual_rubric_bytes(output_root: Path) -> bytes | None:
    """Return rubric bytes only after all prior committed provenance agrees."""
    metadata_path = output_root / "candidate-metadata.json"
    if not metadata_path.is_file():
        return None
    rubric_path = output_root / "qa/visual-rubric.json"
    report_path = output_root / "qa/harmony-report.json"
    try:
        metadata = _read_object(metadata_path)
        report = _read_object(report_path)
        rubric_bytes = rubric_path.read_bytes()
    except (OSError, UnicodeError, ValueError):
        raise ValueError("visual_rubric_committed_state_mismatch") from None

    artifacts = metadata.get("artifacts")
    rubric_artifacts = (
        [
            artifact
            for artifact in artifacts
            if type(artifact) is dict
            and artifact.get("path") == "qa/visual-rubric.json"
        ]
        if type(artifacts) is list
        else []
    )
    input_sha256 = report.get("input_sha256")
    if (
        "visual_rubric_sha256" not in metadata
        or len(rubric_artifacts) != 1
        or type(input_sha256) is not dict
    ):
        raise ValueError("visual_rubric_committed_state_mismatch")

    committed_hash = metadata["visual_rubric_sha256"]
    artifact_hash = rubric_artifacts[0].get("sha256")
    actual_hash = hashlib.sha256(rubric_bytes).hexdigest()
    if committed_hash is None:
        valid = (
            rubric_bytes == _blank_visual_rubric_bytes()
            and artifact_hash == actual_hash
            and "visual_rubric" not in input_sha256
        )
    else:
        valid = (
            _is_lower_sha256(committed_hash)
            and actual_hash == committed_hash
            and artifact_hash == committed_hash
            and input_sha256.get("visual_rubric") == committed_hash
        )
    if not valid:
        raise ValueError("visual_rubric_committed_state_mismatch")
    return rubric_bytes


def _rubric_scores_for_evidence_revision(payload: bytes) -> dict[str, int]:
    rubric = json.loads(payload.decode("utf-8"))
    if not isinstance(rubric, dict) or set(rubric) != set(RUBRIC_DIMENSIONS):
        raise ValueError("visual_rubric_dimensions_changed")
    scores: dict[str, int] = {}
    for name in RUBRIC_DIMENSIONS:
        dimension = rubric.get(name)
        if not isinstance(dimension, dict) or set(dimension) != {"score", "evidence"}:
            raise ValueError("visual_rubric_dimensions_changed")
        score = dimension.get("score")
        evidence = dimension.get("evidence")
        if (
            not isinstance(score, int)
            or isinstance(score, bool)
            or score < 0
            or score > 2
            or not isinstance(evidence, str)
            or not evidence.strip()
        ):
            raise ValueError("visual_rubric_revision_invalid")
        scores[name] = score
    return scores


def _assert_evidence_only_rubric_revision(
    existing: bytes,
    supplied: bytes,
) -> None:
    if _rubric_scores_for_evidence_revision(existing) != _rubric_scores_for_evidence_revision(
        supplied
    ):
        raise ValueError("visual_rubric_scores_changed")


def _load_visual_rubric(checker: object, path: Path) -> object:
    return checker.load_visual_rubric(path)


def _artifact_manifest(stage: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for relative in ARTIFACT_PATHS:
        path = stage / relative
        entry: dict[str, object] = {
            "bytes": path.stat().st_size,
            "path": relative,
            "role": ARTIFACT_ROLES[relative],
            "sha256": _sha256(path),
        }
        if path.suffix.lower() == ".png":
            with Image.open(path) as opened:
                entry["dimensions"] = list(opened.size)
                entry["output_spec"] = {
                    "alpha": "A" in opened.getbands(),
                    "format": "PNG",
                    "height": opened.height,
                    "width": opened.width,
                }
        else:
            entry["output_spec"] = {"format": "JSON"}
            if relative == "appearance/anchors-walk-down.json":
                entry["output_spec"].update({"anchor_count": 8, "state": "walk_down"})
        artifacts.append(entry)
    return artifacts


def _replace_file(source: Path, target: Path) -> Path:
    return source.replace(target)


def _transaction_paths(output_root: Path) -> tuple[Path, Path]:
    marker = output_root / TRANSACTION_MARKER
    return marker, marker.with_name(f"{marker.name}.tmp")


@contextmanager
def _exclusive_approval_update_lock(output_root: Path):
    """Serialize cooperative approval writers for one candidate directory.

    The lock is deliberately fail-closed when left behind after a crash.  Recovery
    must be an explicit operator action because deleting an unknown lock could let
    two approval writers overlap.  This file transaction assumes all legitimate
    writers honor the lock; it cannot stop a malicious process from ignoring it
    and changing the filesystem after the final validation.
    """
    root_existed = output_root.exists()
    output_root.mkdir(parents=True, exist_ok=True)
    lock_path = output_root / APPROVAL_UPDATE_LOCK
    try:
        descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise RuntimeError("approval_update_locked") from None
    try:
        os.close(descriptor)
        yield
    finally:
        lock_path.unlink(missing_ok=True)
        if not root_existed and output_root.is_dir() and not any(output_root.iterdir()):
            output_root.rmdir()


def _atomic_transaction_marker(path: Path, payload: dict[str, object]) -> None:
    temporary = path.with_name(f"{path.name}.tmp")
    _write_json(temporary, payload)
    _replace_file(temporary, path)


def _validated_transaction(
    output_root: Path, payload: dict[str, object]
) -> tuple[Path, list[dict[str, object]]]:
    if payload.get("candidate_id") != CANDIDATE_ID:
        raise RuntimeError("invalid_transaction_marker")
    backup_name = payload.get("backup_dir")
    entries = payload.get("entries")
    if (
        not isinstance(backup_name, str)
        or Path(backup_name).name != backup_name
        or not backup_name.startswith(".candidate-002-txn-")
        or not isinstance(entries, list)
    ):
        raise RuntimeError("invalid_transaction_marker")
    backup_dir = (output_root.parent / backup_name).resolve()
    if backup_dir.parent != output_root.parent.resolve():
        raise RuntimeError("invalid_transaction_marker")
    allowed = {*ARTIFACT_PATHS, "candidate-metadata.json"}
    normalized: list[dict[str, object]] = []
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("relative") not in allowed:
            raise RuntimeError("invalid_transaction_marker")
        relative = str(entry["relative"])
        backup = entry.get("backup")
        staged = entry.get("staged")
        if backup is not None and (
            not isinstance(backup, str) or Path(backup).name != backup
        ):
            raise RuntimeError("invalid_transaction_marker")
        if staged is not None and (
            not isinstance(staged, str) or Path(staged).name != staged
        ):
            raise RuntimeError("invalid_transaction_marker")
        normalized.append({**entry, "relative": relative})
    return backup_dir, normalized


def _verify_transaction_targets(
    output_root: Path,
    entries: list[dict[str, object]],
    hash_field: str,
) -> None:
    for entry in entries:
        expected = entry.get(hash_field)
        target = output_root / str(entry["relative"])
        if expected is None:
            if target.exists():
                raise RuntimeError("transaction_target_mismatch")
        elif not target.is_file() or _sha256(target) != expected:
            raise RuntimeError("transaction_target_mismatch")


def _finish_transaction(output_root: Path, payload: dict[str, object]) -> None:
    backup_dir, entries = _validated_transaction(output_root, payload)
    phase = payload.get("phase")
    if phase == "committed":
        _verify_transaction_targets(output_root, entries, "new_sha256")
    elif phase == "rolled_back":
        _verify_transaction_targets(output_root, entries, "old_sha256")
    else:
        raise RuntimeError("invalid_transaction_phase")
    for entry in entries:
        backup = entry.get("backup")
        if isinstance(backup, str):
            (backup_dir / backup).unlink(missing_ok=True)
        staged = entry.get("staged")
        if isinstance(staged, str):
            (backup_dir / staged).unlink(missing_ok=True)
    if backup_dir.exists():
        backup_dir.rmdir()
    marker, marker_temporary = _transaction_paths(output_root)
    marker_temporary.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)


def _rollback_transaction(output_root: Path, payload: dict[str, object]) -> None:
    backup_dir, entries = _validated_transaction(output_root, payload)
    for entry in entries:
        target = output_root / str(entry["relative"])
        old_hash = entry.get("old_sha256")
        if old_hash is None:
            target.unlink(missing_ok=True)
            continue
        backup = entry.get("backup")
        if not isinstance(backup, str):
            raise RuntimeError("missing_transaction_backup")
        backup_path = backup_dir / backup
        if not backup_path.is_file() or _sha256(backup_path) != old_hash:
            raise RuntimeError("invalid_transaction_backup")
        target.parent.mkdir(parents=True, exist_ok=True)
        recovery = target.with_name(f"{target.name}.recovery.tmp")
        shutil.copyfile(backup_path, recovery)
        _replace_file(recovery, target)
    _verify_transaction_targets(output_root, entries, "old_sha256")
    rolled_back = {**payload, "phase": "rolled_back"}
    marker, _ = _transaction_paths(output_root)
    _atomic_transaction_marker(marker, rolled_back)
    _finish_transaction(output_root, rolled_back)


def _recover_transaction(output_root: Path) -> None:
    if (output_root / APPROVAL_UPDATE_LOCK).exists():
        raise RuntimeError("approval_update_locked")
    _recover_transaction_while_locked(output_root)


def _recover_transaction_while_locked(output_root: Path) -> None:
    marker, marker_temporary = _transaction_paths(output_root)
    if not marker.is_file():
        marker_temporary.unlink(missing_ok=True)
        return
    payload = _read_object(marker)
    phase = payload.get("phase")
    if phase == "prepared":
        _rollback_transaction(output_root, payload)
    elif phase in {"committed", "rolled_back"}:
        _finish_transaction(output_root, payload)
    else:
        raise RuntimeError("invalid_transaction_phase")


def _publish(stage: Path, output_root: Path) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    relatives = list(ARTIFACT_PATHS)
    relatives.append("candidate-metadata.json")
    backup_dir = Path(
        tempfile.mkdtemp(prefix=".candidate-002-txn-", dir=output_root.parent)
    )
    entries: list[dict[str, object]] = []
    for index, relative in enumerate(relatives):
        target = output_root / relative
        source = stage / relative
        had_original = target.is_file()
        backup_name = f"{index:02d}.backup" if had_original else None
        old_hash = _sha256(target) if had_original else None
        if backup_name is not None:
            shutil.copyfile(target, backup_dir / backup_name)
        entries.append(
            {
                "backup": backup_name,
                "new_sha256": _sha256(source),
                "old_sha256": old_hash,
                "relative": relative,
            }
        )
    marker, _ = _transaction_paths(output_root)
    transaction: dict[str, object] = {
        "backup_dir": backup_dir.name,
        "candidate_id": CANDIDATE_ID,
        "entries": entries,
        "phase": "prepared",
        "reader_contract": "candidate is invalid while this marker exists",
        "schema_version": "gogobro-candidate-transaction-v1",
    }
    try:
        _atomic_transaction_marker(marker, transaction)
        for relative in relatives:
            source = stage / relative
            target = output_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            _replace_file(source, target)
        committed = {**transaction, "phase": "committed"}
        _atomic_transaction_marker(marker, committed)
        _finish_transaction(output_root, committed)
    except Exception:
        if marker.is_file():
            _recover_transaction_while_locked(output_root)
        else:
            _, marker_temporary = _transaction_paths(output_root)
            marker_temporary.unlink(missing_ok=True)
            for entry in entries:
                backup = entry.get("backup")
                if isinstance(backup, str):
                    (backup_dir / backup).unlink(missing_ok=True)
            if backup_dir.exists():
                backup_dir.rmdir()
        raise


def build_candidate_002(
    inputs: BuildInputs,
    visual_rubric: Path | None = None,
    *,
    revise_rubric_evidence: bool = False,
) -> CandidateMetadata:
    with _exclusive_approval_update_lock(inputs.output_root):
        _recover_transaction_while_locked(inputs.output_root)
        return _build_candidate_002_locked(
            inputs,
            visual_rubric,
            revise_rubric_evidence=revise_rubric_evidence,
        )


def _build_candidate_002_locked(
    inputs: BuildInputs,
    visual_rubric: Path | None = None,
    *,
    revise_rubric_evidence: bool = False,
) -> CandidateMetadata:
    existing_rubric_path = inputs.output_root / "qa/visual-rubric.json"
    if (
        visual_rubric is not None
        and visual_rubric.resolve() == existing_rubric_path.resolve()
    ):
        raise ValueError("visual_rubric_aliases_output")
    candidate_001 = _validate_inputs(inputs)
    candidate_001_before = _tree_hashes(candidate_001)
    source_hashes = _source_hashes(inputs, candidate_001_before)
    registry = _read_object(inputs.registry)
    unit = _registry_unit(registry)
    if unit.get("active_candidate_id") != CANDIDATE_ID:
        raise ValueError("active_candidate_id_mismatch")
    approval_snapshot = _registry_approval_snapshot(unit)
    if approval_snapshot["approval_status"] == "approved":
        if visual_rubric is not None or revise_rubric_evidence:
            raise ValueError("approved_candidate_is_immutable")
        return _reuse_approved_candidate(
            inputs,
            source_hashes,
            registry,
            approval_snapshot,
        )

    checker = _load_checker()
    _assert_reusable_output(inputs.output_root, source_hashes, inputs.registry)
    registry_before = str(source_hashes["registry"])
    niko_before = _sha256(inputs.niko_atlas)
    font_regular_before = _sha256(inputs.card_font_regular)
    font_bold_before = _sha256(inputs.card_font_bold)
    existing_rubric_bytes = _committed_visual_rubric_bytes(inputs.output_root)
    supplied_rubric_bytes = visual_rubric.read_bytes() if visual_rubric else None
    blank_rubric_bytes = _blank_visual_rubric_bytes()
    existing_completed_rubric = (
        existing_rubric_bytes is not None
        and existing_rubric_bytes != blank_rubric_bytes
    )
    if revise_rubric_evidence and (
        supplied_rubric_bytes is None or not existing_completed_rubric
    ):
        raise ValueError("visual_rubric_revision_requires_existing")
    if (
        supplied_rubric_bytes is not None
        and existing_completed_rubric
        and supplied_rubric_bytes != existing_rubric_bytes
    ):
        if not revise_rubric_evidence:
            raise ValueError("visual_rubric_mismatch")
        _assert_evidence_only_rubric_revision(
            existing_rubric_bytes,
            supplied_rubric_bytes,
        )
    preserved_completed_rubric = (
        supplied_rubric_bytes is None
        and existing_completed_rubric
    )
    apply_rubric = supplied_rubric_bytes is not None or preserved_completed_rubric
    if supplied_rubric_bytes is not None:
        rubric_bytes = supplied_rubric_bytes
    elif existing_rubric_bytes is not None:
        rubric_bytes = existing_rubric_bytes
    else:
        rubric_bytes = blank_rubric_bytes
    rubric_hash = hashlib.sha256(rubric_bytes).hexdigest() if apply_rubric else None

    appearance, atlas = _load_images(inputs)
    profile = _read_object(inputs.rig_profile)
    anchors = _build_anchors(checker, appearance, profile)

    inputs.output_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="candidate-002-stage-", dir=inputs.output_root.parent
    ) as temporary:
        stage = Path(temporary)
        derived_appearance = stage / "derived/appearance-128.png"
        derived_icon = stage / "derived/icon-256.png"
        derived_appearance.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(inputs.appearance_source, derived_appearance)
        icon = checker.derive_nearest_2x_icon(appearance)
        icon.save(derived_icon)
        _write_json(stage / "appearance/anchors-walk-down.json", anchors)
        staged_rubric_path = stage / "qa/visual-rubric.json"
        staged_rubric_path.parent.mkdir(parents=True, exist_ok=True)
        staged_rubric_path.write_bytes(rubric_bytes)

        harmony_inputs = checker.HarmonyInputs(
            character_atlas=inputs.niko_atlas,
            appearance=derived_appearance,
            icon=derived_icon,
            anchors=stage / "appearance/anchors-walk-down.json",
            rig_profile=inputs.rig_profile,
            slot="head",
            out_dir=stage / "qa",
        )
        report = checker.analyze_harmony(harmony_inputs)
        if apply_rubric:
            rubric = _load_visual_rubric(checker, staged_rubric_path)
            report = checker.apply_visual_rubric(
                report,
                rubric,
                rubric_sha256=rubric_hash,
            )
            report_metrics = dict(report.metrics)
            report_metrics["visual_rubric_sha256"] = rubric_hash
            report = replace(report, metrics=report_metrics)
        checker.write_harmony_outputs(report, harmony_inputs)

        composite = _compose_atlas(atlas, appearance, anchors)
        (stage / "qa").mkdir(parents=True, exist_ok=True)
        composite.crop((0, 0, 128, 128)).save(stage / "qa/composite-frame-001.png")
        composite.save(stage / "qa/composite-atlas-8x128.png")
        _save_runtime_preview(composite, stage / "qa/runtime-size-1920x1080.png")

        appearance_checks = _image_checks(appearance)
        icon_checks = _image_checks(icon)
        pixel_qa = {
            "approval_card_evidence": _approval_card_evidence(unit, report),
            "candidate_id": CANDIDATE_ID,
            "checks": {
                "appearance_binary_alpha": appearance_checks["binary_alpha"],
                "appearance_bytes_unchanged": derived_appearance.read_bytes()
                == inputs.appearance_source.read_bytes(),
                "appearance_dimensions": list(appearance.size) == list(FRAME_SIZE),
                "appearance_transparent_rgb_zero": appearance_checks["transparent_rgb_zero"],
                "icon_binary_alpha": icon_checks["binary_alpha"],
                "icon_dimensions": list(icon.size) == list(ICON_SIZE),
                "icon_nearest_2x": icon.tobytes()
                == checker.derive_nearest_2x_icon(appearance).tobytes(),
                "icon_transparent_rgb_zero": icon_checks["transparent_rgb_zero"],
                "no_crop": all(
                    0 <= left < right <= 128 and 0 <= top < bottom <= 128
                    for left, top, right, bottom in report.metrics.get("frame_boxes", [])
                ),
                "protected_eye_occlusion_zero": report.metrics.get(
                    "max_protected_occlusion_ratio"
                )
                == 0,
            },
            "metrics": {
                "appearance_opaque_color_count": appearance_checks["opaque_color_count"],
                "icon_opaque_color_count": icon_checks["opaque_color_count"],
            },
            "passed": False,
        }
        pixel_qa["passed"] = all(pixel_qa["checks"].values())
        _write_json(stage / "qa/pixel-qa-report.json", pixel_qa)
        card = _approval_card(
            icon,
            appearance,
            composite,
            unit,
            report,
            inputs.card_font_regular,
            inputs.card_font_bold,
        )
        card.save(stage / "qa/approval-card.png")

        artifacts = _artifact_manifest(stage)
        metadata = CandidateMetadata(
            candidate_id=CANDIDATE_ID,
            transform={
                "aperture_box": report.metrics.get("aperture_box"),
                "integer_offsets": [frame["offset"] for frame in anchors["frames"]],
                "shared_scale": SHARED_SCALE,
            },
            artifacts=artifacts,
            metrics=dict(report.metrics),
        )
        metadata_payload = {
            **asdict(metadata),
            "asset_id": ASSET_ID,
            "card_rendering": {
                "evidence": pixel_qa["approval_card_evidence"],
                "fonts": {
                    "bold": {
                        "path": str(inputs.card_font_bold.resolve()),
                        "sha256": font_bold_before,
                    },
                    "regular": {
                        "path": str(inputs.card_font_regular.resolve()),
                        "sha256": font_regular_before,
                    },
                },
            },
            "harmony_verdict": report.verdict,
            "publication": {
                "transaction_marker": TRANSACTION_MARKER,
                "valid_when_marker_absent": True,
            },
            "reason_codes": list(report.reason_codes),
            "registry_snapshot": {
                "approval_status": "review",
                "approval_history": [],
                "effects": unit.get("effects", []),
                "localization": unit.get("localization", {}),
            },
            "source_sha256": source_hashes,
            "visual_rubric_sha256": rubric_hash,
        }
        registry_snapshot = metadata_payload["registry_snapshot"]
        if not isinstance(registry_snapshot, dict):
            raise RuntimeError("invalid_registry_snapshot")
        registry_snapshot["refresh_guard"] = _registry_refresh_guard(
            registry,
            metadata_payload,
        )
        _write_json(stage / "candidate-metadata.json", metadata_payload)

        try:
            current_source_hashes = _source_hashes(
                inputs,
                _tree_hashes(candidate_001),
            )
        except OSError as error:
            raise RuntimeError("source_changed") from error
        if (
            current_source_hashes["card_font_regular"] != font_regular_before
            or current_source_hashes["card_font_bold"] != font_bold_before
        ):
            raise RuntimeError("card_font_changed")
        source_unchanged = (
            current_source_hashes == source_hashes
            and current_source_hashes["niko_atlas"]
            == niko_before
            == LOCKED_NIKO_HASH
            and current_source_hashes["registry"] == registry_before
        )
        if not source_unchanged:
            raise RuntimeError("source_changed")
        try:
            supplied_rubric_unchanged = (
                supplied_rubric_bytes is None
                or (
                    visual_rubric is not None
                    and visual_rubric.read_bytes() == supplied_rubric_bytes
                )
            )
            existing_rubric_unchanged = (
                existing_rubric_path.read_bytes() == existing_rubric_bytes
                if existing_rubric_bytes is not None
                else not existing_rubric_path.exists()
            )
        except OSError as error:
            raise RuntimeError("visual_rubric_changed") from error
        if not supplied_rubric_unchanged or not existing_rubric_unchanged:
            raise RuntimeError("visual_rubric_changed")
        _publish(stage, inputs.output_root)
    return metadata


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appearance-source", type=Path, required=True)
    parser.add_argument("--niko-atlas", type=Path, required=True)
    parser.add_argument("--rig-profile", type=Path, required=True)
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--visual-rubric", type=Path)
    parser.add_argument("--revise-rubric-evidence", action="store_true")
    parser.add_argument("--card-font-regular", type=Path, default=DEFAULT_CARD_FONT_REGULAR)
    parser.add_argument("--card-font-bold", type=Path, default=DEFAULT_CARD_FONT_BOLD)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    metadata = build_candidate_002(
        BuildInputs(
            appearance_source=arguments.appearance_source,
            niko_atlas=arguments.niko_atlas,
            rig_profile=arguments.rig_profile,
            registry=arguments.registry,
            output_root=arguments.output_root,
            card_font_regular=arguments.card_font_regular,
            card_font_bold=arguments.card_font_bold,
        ),
        visual_rubric=arguments.visual_rubric,
        revise_rubric_evidence=arguments.revise_rubric_evidence,
    )
    verdict = json.loads(
        (arguments.output_root / "candidate-metadata.json").read_text(encoding="utf-8")
    )["harmony_verdict"]
    print(
        json.dumps(
            {
                "candidate_id": metadata.candidate_id,
                "metrics": metadata.metrics,
                "verdict": verdict,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 2 if verdict == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
