# GOGOBRO Item–Character Harmony Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce Smoke-Shell Helmet candidate 002 with a directly reused appearance icon and corrected worn scale/alignment, plus a reusable tested Codex skill that rejects visually disharmonious GOGOBRO item appearances before user review.

**Architecture:** A versioned skill source under `tools/codex_skills/` contains a deterministic Pillow checker, slot contracts, tests, and Codex instructions; an installer copies that exact package into the user's discoverable Codex skill directory and verifies hash parity. A separate deterministic candidate builder preserves candidate 001, derives candidate 002, runs pixel and harmony checks, and emits provenance consumed by the existing Godot registry validator.

**Tech Stack:** Python 3.11+, Pillow, pytest, PowerShell 7/Windows PowerShell, Godot 4.7.1, GdUnit4, Codex skill-creator validation.

**Spec:** `docs/superpowers/specs/2026-08-23-gogobro-item-harmony-design.md`

## Global Constraints

- Preserve candidate 001 and all existing files byte-for-byte.
- Candidate 002 uses no AI generation; its icon is the candidate 001 cleaned 128×128 appearance scaled to 256×256 with nearest-neighbor sampling.
- Keep the existing Niko walk-down atlas byte-identical at SHA-256 `FBC10108D9A665B14DCC376DA54BBBF66D89B931AE1189E69FE1C45B31FE579D`.
- Candidate 002 starts at shared appearance scale `0.625`; only a documented 1/16-step adjustment may replace it if a hard gate cannot otherwise pass.
- Use integer per-frame offsets and align the largest enclosed transparent face aperture to the Niko face center.
- Candidate 002's outer helmet/head width ratio must be `1.05–1.15`; aperture-center error and residual frame jitter must each be at most 1 px.
- Keep protected eyes visible, keep every appearance fully inside its 128×128 frame, and preserve binary alpha with RGB zero under transparent pixels.
- The skill may output `hard_fail`, `review`, or `harmony_pass`; it may never set content to `approved`.
- Candidate 002 remains `review`; do not create `curated` files, runtime integration, animation states, or startup changes.
- Use exact file sizes and SHA-256 values emitted by deterministic build metadata; never hand-copy a second effect-value string.
- All file edits use `apply_patch`; bulk deterministic image generation and exact package synchronization may use their dedicated scripts.
- Every task that runs Python first sets `$harmonyPython = 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe'`; do not rely on an ambient `python` command.

## File Map

| Path | Responsibility |
|---|---|
| `tools/codex_skills/checking-gogobro-item-harmony/SKILL.md` | Skill routing, workflow, verdict contract, and visual rubric. |
| `tools/codex_skills/checking-gogobro-item-harmony/agents/openai.yaml` | Discoverable skill UI metadata. |
| `tools/codex_skills/checking-gogobro-item-harmony/references/slot-profiles.md` | Slot-specific regions, scale bands, occlusion, and depth rules. |
| `tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py` | Deterministic checker CLI and importable measurement functions. |
| `tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py` | Synthetic and real-candidate checker regression tests. |
| `tools/codex_skills/checking-gogobro-item-harmony/tests/behavioral-evidence.md` | No-skill RED and with-skill GREEN evaluation evidence. |
| `tools/assets/rig_profiles/niko_walk_down_v1.json` | Explicit eight-frame Niko semantic regions and locked atlas hash. |
| `tools/assets/build_smoke_shell_helmet_candidate_002.py` | Deterministic icon, anchor, composite, preview, card, and metadata builder. |
| `tests/python/test_smoke_shell_helmet_candidate_002.py` | Candidate derivation, preservation, geometry, and determinism tests. |
| `tools/install_gogobro_item_harmony_skill.ps1` | Safe explicit-file deployment into `C:/Users/18421/.codex/skills/`. |
| `tests/python/test_install_gogobro_item_harmony_skill.py` | Installer manifest and source/installed hash-parity tests. |
| `game/content/assets/gogobro_static_assets_v1.json` | Candidate history, active candidate 002 provenance, and review status. |
| `game/content/assets/static_asset_registry.gd` | Candidate-history and active-review validation. |
| `tests/unit/test_static_asset_registry.gd` | GdUnit regression coverage for candidate history/provenance. |
| `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/qa_profiles/niko-walk-down-v1.json` | Built copy of the versioned Niko rig profile used by candidate QA. |
| `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/` | Generated review-only candidate artifacts and reports. |

---

### Task 1: Capture the Behavioral RED and Scaffold the Versioned Skill

**Files:**
- Create: `tools/codex_skills/checking-gogobro-item-harmony/SKILL.md`
- Create: `tools/codex_skills/checking-gogobro-item-harmony/agents/openai.yaml`
- Create: `tools/codex_skills/checking-gogobro-item-harmony/references/slot-profiles.md`
- Create: `tools/codex_skills/checking-gogobro-item-harmony/tests/behavioral-evidence.md`

**Interfaces:**
- Consumes: candidate 001 approval card, composite atlas, actual-size preview, and QA report.
- Produces: a documented no-skill failure, initialized skill package, and the invocation name `checking-gogobro-item-harmony` used by all later tasks.

- [ ] **Step 1: Read the required skill-authoring instructions**

Read completely before creating files:

```text
C:/Users/18421/.codex/skills/.system/skill-creator/SKILL.md
C:/Users/18421/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0/skills/writing-skills/SKILL.md
C:/Users/18421/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0/skills/test-driven-development/SKILL.md
C:/Users/18421/.codex/skills/.system/skill-creator/references/openai_yaml.md
C:/Users/18421/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0/skills/writing-skills/testing-skills-with-subagents.md
```

- [ ] **Step 2: Run the no-skill behavioral evaluation before scaffolding**

Dispatch a fresh subagent without the proposed skill and give it only this request and the four candidate paths:

```text
Review Smoke-Shell Helmet candidate 001 for approval. Decide whether its icon and worn appearance are harmonious with Niko. Use the approval card, 8-frame composite, actual-size preview, and QA JSON. Return approve/revise with concrete visual reasons.
```

Expected RED: the evaluator approves or focuses on palette/alpha/hash while failing to identify both measured defects: outer helmet/head ratio `1.31` and aperture-based center misalignment.

- [ ] **Step 3: Record the exact RED evidence outside the future instructions**

Create `E:/01_gobro/.codex-temp/checking-gogobro-item-harmony-red/behavioral-evidence.md` with a `RED — without skill` section. Record `candidate-001`, paste the evaluator's complete verdict and reasoning verbatim, and mark each required defect as `identified` or `missed`:

```markdown
# Behavioral evidence

## RED — without skill
- Candidate: `candidate-001`
- Required defect result: `scale_ratio_high` — identified or missed
- Required defect result: `feature_center_offset` — identified or missed
```

Place the verbatim evaluator verdict and reasoning directly beneath these fields. The committed file contains the actual observed output and no empty evidence fields.

- [ ] **Step 4: Initialize the canonical skill source after RED exists**

Run:

```powershell
$skillCreatorPython = 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe'
& $skillCreatorPython 'C:\Users\18421\.codex\skills\.system\skill-creator\scripts\init_skill.py' `
  checking-gogobro-item-harmony `
  --path 'tools\codex_skills' `
  --resources scripts,references
```

Create the initialized skill's `tests/` directory, add the exact recorded evidence as `tests/behavioral-evidence.md` with `apply_patch`, and delete the temporary evidence file with `apply_patch`. Remove every initializer scaffold marker before the task ends.

- [ ] **Step 5: Write the minimal discovery contract**

Set the frontmatter and UI metadata to:

```yaml
---
name: checking-gogobro-item-harmony
description: Use when reviewing or integrating GOGOBRO item icons and character appearance layers for scale, anchor alignment, protected-region occlusion, pixel density, palette fit, depth, or multi-frame visual harmony.
---
```

```yaml
interface:
  display_name: GOGOBRO Item Harmony
  short_description: Validate item and character visual harmony
  default_prompt: Check this GOGOBRO item icon and character appearance for deterministic geometry and visual harmony.
```

The body at this stage names the checker output contract and states that hard failures block approval; detailed workflow arrives only after checker behavior exists.

- [ ] **Step 6: Verify package scope and commit**

Run:

```powershell
rg -n -i 'replace me|example content|fill in|unfinished scaffold' tools/codex_skills/checking-gogobro-item-harmony
git diff --check
git status --short
```

Expected: the search returns no unresolved scaffold markers; only Task 1 files are changed.

```powershell
git add tools/codex_skills/checking-gogobro-item-harmony
git commit -m "test: capture item harmony baseline"
```

---

### Task 2: Build the Deterministic Harmony Checker with TDD

**Files:**
- Create: `tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py`
- Create: `tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py`

**Interfaces:**
- Consumes: RGBA icon/appearance PNGs, character atlas, anchor JSON, rig-profile JSON, slot name, output directory.
- Produces: `analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport`, `apply_visual_rubric(report: HarmonyReport, rubric: VisualRubric) -> HarmonyReport`, CLI exit `0` for `harmony_pass`/`review`, CLI exit `2` for `hard_fail`, and deterministic report/overlay/preview files.

- [ ] **Step 1: Write failing geometry and pixel-contract tests**

Define public types and expected reason codes in the tests before implementation:

```python
from check_item_harmony import HarmonyInputs, analyze_harmony, derive_nearest_2x_icon


def test_oversized_head_item_is_hard_fail(head_fixture):
    report = analyze_harmony(head_fixture.with_outer_width(76).with_head_width(58))
    assert report.verdict == "hard_fail"
    assert "scale_ratio_high" in report.reason_codes
    assert report.metrics["outer_width_ratio"] == pytest.approx(76 / 58)


def test_aperture_offset_is_reported_in_pixels(head_fixture):
    report = analyze_harmony(head_fixture.with_aperture_center((58, 71)).with_face_center((62, 71)))
    assert "feature_center_offset" in report.reason_codes
    assert report.metrics["max_feature_center_error_px"] == 4


def test_direct_icon_contract_is_exact_nearest_2x(appearance_image):
    icon = derive_nearest_2x_icon(appearance_image)
    assert icon.size == (256, 256)
    assert list(icon.getdata()) == list(appearance_image.resize((256, 256), Image.Resampling.NEAREST).getdata())
```

Add separate failures for binary alpha, transparent RGB, chroma, palette limits, crop, protected-eye occlusion, wrong depth, duplicate slot, anchor count, and two-frame/eight-frame residual jitter.

Add exact-rendering and provenance regressions:

- scale `.597` measures the Pillow nearest raster as `60/58`, not the continuous projection `61/58`;
- protected-region occlusion samples the actual resized layer, including a pixel missed by inverse-floor lookup;
- canonical atlas hash format/mismatch and exact-boolean `direct_icon_reuse` are enforced;
- formal 64×64 logical contracts reject nonuniform 2×/4× blocks, unapproved boundary colors, and excess source/rendered four-connected components;
- malformed rubric root/dimension shapes, strings/floats/bools as scores, and non-string evidence are rejected without coercion;
- report/source-integrity/suggestion schemas retain per-path hashes, thresholds, objective metrics, and truthful status.

Add rubric-state tests:

```python
assert analyze_harmony(valid_inputs).verdict == "review"
assert apply_visual_rubric(valid_report, rubric(scores=[2, 2, 2, 1, 1])).verdict == "harmony_pass"
assert apply_visual_rubric(valid_report, rubric(scores=[2, 2, 1, 1, 1])).verdict == "review"
assert apply_visual_rubric(valid_report, rubric(scores=[2, 2, 2, 2, 0])).verdict == "review"
```

The test helper `rubric(scores)` maps the five ordered scores to `VisualRubric(identity, function, material, hierarchy, originality)` and supplies a non-empty evidence string for every dimension.

- [ ] **Step 2: Run the checker tests to prove RED**

Run:

```powershell
$harmonyPython = 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe'
& $harmonyPython -m pytest tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py -q
```

Expected: test collection fails because `check_item_harmony` and its public types do not exist.

- [ ] **Step 3: Implement focused data types and pure measurements**

Implement these stable interfaces:

```python
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class Box:
    left: int
    top: int
    right: int
    bottom: int


@dataclass(frozen=True)
class HarmonyInputs:
    character_atlas: Path
    appearance: Path
    icon: Path
    anchors: Path
    rig_profile: Path
    slot: str
    out_dir: Path


@dataclass(frozen=True)
class HarmonyReport:
    verdict: str
    reason_codes: Sequence[str]
    metrics: dict[str, object]
    input_sha256: dict[str, str | None]
    atlas_sha256: dict[str, str | None] = field(default_factory=dict)
    slot: str | None = None
    thresholds: dict[str, object] = field(default_factory=dict)
    source_integrity: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class VisualRubric:
    identity: tuple[int, str]
    function: tuple[int, str]
    material: tuple[int, str]
    hierarchy: tuple[int, str]
    originality: tuple[int, str]


def derive_nearest_2x_icon(appearance: Image.Image) -> Image.Image:
    return appearance.resize((256, 256), Image.Resampling.NEAREST)


def placed_feature_center(source_center: tuple[float, float], scale: float, offset: tuple[int, int]) -> tuple[float, float]:
    return (offset[0] + source_center[0] * scale, offset[1] + source_center[1] * scale)
```

Also implement `find_largest_enclosed_transparent_region(image) -> Box`, `analyze_harmony(inputs) -> HarmonyReport`, `load_visual_rubric(path) -> VisualRubric`, `apply_visual_rubric(report, rubric) -> HarmonyReport`, and `write_harmony_outputs(report, inputs) -> None`. Use four-connected flood fill for enclosed transparency. For every anchor, resize the full appearance canvas with Pillow nearest sampling to `round(source_size × scale)` and use that same layer for alpha bounds, resized feature center, crop, occlusion, diagnostics, and compositing. Compute residual jitter from those raster feature deltas. A hard-pass report remains `review` until a complete strict rubric is applied.

Formal `gogobro-item-anchors-v1` data includes a `pixel_contract` with logical canvas `[64,64]`, appearance/icon scales `2/4`, `nearest`, and a frozen outline RGB list. Validate exact nearest down/up RGBA block round trips, four-connected component counts, and source/rendered opaque-boundary coverage. Canonical slot coverage is non-relaxable at `1.0`; head permits one opaque component.

- [ ] **Step 4: Implement deterministic output and CLI behavior**

The JSON writer uses `sort_keys=True`, UTF-8, two-space indentation, and a terminal newline. PNG diagnostics use fixed colors, nearest sampling, and no timestamps. Hash each source independently before and after processing and return `hard_fail` if any source changes. The report includes slot, metrics, thresholds, reasons/verdict, complete input hashes, atlas expected/actual, and source-integrity before/after/changed keys. A used rubric is a hashed input. A transform suggestion includes current scales, integer offsets, objective measurements, thresholds, reasons, and a truthful status; failing geometry without a measured passing alternative is `manual_correction_required`.

CLI parser:

```python
parser.add_argument("--character-atlas", type=Path, required=True)
parser.add_argument("--appearance", type=Path, required=True)
parser.add_argument("--icon", type=Path, required=True)
parser.add_argument("--anchors", type=Path, required=True)
parser.add_argument("--rig-profile", type=Path, required=True)
parser.add_argument("--slot", required=True)
parser.add_argument("--out-dir", type=Path, required=True)
parser.add_argument("--suggest-transform", action="store_true")
parser.add_argument("--visual-rubric", type=Path)
```

- [ ] **Step 5: Run tests GREEN and verify determinism**

Run the focused suite twice and hash its golden temporary outputs:

```powershell
& $harmonyPython -m pytest tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py -q
& $harmonyPython -m pytest tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py -q
```

Expected both times: all tests pass; the determinism test confirms byte-identical JSON and diagnostic rasters.

- [ ] **Step 6: Commit the checker**

```powershell
git add tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py `
        tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py
git commit -m "feat: add deterministic item harmony checker"
```

---

### Task 3: Add Niko Rig Data, Slot Contracts, Skill Instructions, and Safe Installation

**Files:**
- Create: `tools/assets/rig_profiles/niko_walk_down_v1.json`
- Modify: `tools/codex_skills/checking-gogobro-item-harmony/references/slot-profiles.md`
- Modify: `tools/codex_skills/checking-gogobro-item-harmony/SKILL.md`
- Modify: `tools/codex_skills/checking-gogobro-item-harmony/agents/openai.yaml`
- Create: `tools/install_gogobro_item_harmony_skill.ps1`
- Create: `tests/python/test_install_gogobro_item_harmony_skill.py`
- Test: `tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py`

**Interfaces:**
- Consumes: checker reason codes and Niko atlas geometry.
- Produces: rig-profile schema `gogobro-rig-profile-v1`, slot threshold lookup, complete skill instructions, and `Install-GogobroItemHarmonySkill -SourceRoot -TargetRoot`.

- [ ] **Step 1: Add failing rig-profile and slot-contract tests**

Add tests asserting:

```python
assert profile["schema_version"] == "gogobro-rig-profile-v1"
assert profile["character_atlas_sha256"] == "FBC10108D9A665B14DCC376DA54BBBF66D89B931AE1189E69FE1C45B31FE579D"
assert len(profile["frames"]) == 8
assert [frame["face_center"][0] for frame in profile["frames"]] == [62, 62, 62, 62, 64, 64, 62, 62]
assert all(frame["face_center"][1] == 71 for frame in profile["frames"])
assert profile["slot_profiles"]["head"]["outer_width_ratio"] == [1.05, 1.15]
assert profile["slot_profiles"]["head"]["max_feature_center_error_px"] == 1
assert profile["slot_profiles"]["head"]["max_residual_jitter_px"] == 1
assert profile["slot_profiles"]["head"]["max_opaque_components"] == 1
assert all(
    slot["min_outline_boundary_coverage"] == 1.0
    for slot in profile["slot_profiles"].values()
)
```

The Niko profile uses frame X shifts from the existing alpha geometry, face ROI `[44, 50, 80, 92]`, and protected-eye ROI `[48, 64, 78, 80]`, shifting both regions +2 px for frames 4 and 5. Store torso, back, wrist, feet, side, and trinket regions for future item checks as explicit integer boxes.

The candidate-002 anchor builder freezes `pixel_contract` to logical `[64,64]`, scales `2/4`, nearest sampling, and outline colors `[[8,5,3],[9,0,0],[21,13,6],[29,27,24],[34,34,31]]`; the checker never derives this accepted palette from submitted pixels.

- [ ] **Step 2: Run tests to verify the missing profile fails**

```powershell
& $harmonyPython -m pytest tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py -q
```

Expected: profile tests fail because the file/schema and slot contracts are absent.

- [ ] **Step 3: Write the profile and slot reference**

Document for each slot:

```text
feature anchor | allowed silhouette ratio | protected ROI | maximum occlusion | depth band | flip behavior
```

For `head`, use aperture-to-face alignment, width ratio `1.05–1.15`, eye occlusion `0`, center error `≤1`, jitter `≤1`, and front depth. For non-head slots, define explicit geometry in the reference and matching JSON rather than inheriting the head rules.

- [ ] **Step 4: Complete the skill's decision recipe**

Keep `SKILL.md` under 500 words. Require this output order:

```text
1. Run deterministic checker.
2. If hard_fail: report reason codes and stop before approval.
3. If geometry passes: inspect overlay and actual-size preview.
4. Score identity, function, material, hierarchy, and originality from 0–2.
5. Return review below 8/10 or with any zero; otherwise harmony_pass.
6. Never mutate sources or advance registry approval automatically.
```

Link `references/slot-profiles.md` only when choosing or reviewing a slot profile.

- [ ] **Step 5: Write the installer test first**

Test against a temporary target directory:

```python
def test_installer_copies_only_manifest_files_and_preserves_hashes(tmp_path):
    result = run_installer(source=SKILL_SOURCE, target=tmp_path / "checking-gogobro-item-harmony")
    assert result.returncode == 0
    assert manifest_hashes(SKILL_SOURCE) == manifest_hashes(tmp_path / "checking-gogobro-item-harmony")
    assert not any(path.name == "__pycache__" for path in tmp_path.rglob("*"))
```

The test helper `manifest_hashes(root)` hashes only the four explicit installer-manifest paths. `run_installer` invokes PowerShell non-interactively with resolved temporary source and target roots.

Expected RED: PowerShell installer path does not exist.

- [ ] **Step 6: Implement safe explicit-file installation**

The installer accepts only explicit source/target roots, resolves both, rejects identical roots, creates the target if missing, and copies a fixed manifest:

```powershell
$manifest = @(
  'SKILL.md',
  'agents\openai.yaml',
  'references\slot-profiles.md',
  'scripts\check_item_harmony.py'
)
```

It does not recursively delete or mirror directories. After copying, compute SHA-256 for every manifest file and fail if source/target hashes differ.

- [ ] **Step 7: Run GREEN tests and validate the canonical skill**

```powershell
& $harmonyPython -m pytest `
  tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py `
  tests/python/test_install_gogobro_item_harmony_skill.py -q
& $harmonyPython 'C:\Users\18421\.codex\skills\.system\skill-creator\scripts\quick_validate.py' `
  'tools\codex_skills\checking-gogobro-item-harmony'
```

Expected: all Python tests pass and `quick_validate.py` reports a valid skill.

- [ ] **Step 8: Commit profile, instructions, and installer**

```powershell
git add tools/assets/rig_profiles/niko_walk_down_v1.json `
        tools/codex_skills/checking-gogobro-item-harmony `
        tools/install_gogobro_item_harmony_skill.ps1 `
        tests/python/test_install_gogobro_item_harmony_skill.py
git commit -m "feat: define GOGOBRO item harmony skill"
```

---

### Task 4: Build and Validate Smoke-Shell Helmet Candidate 002

**Files:**
- Create: `tools/assets/build_smoke_shell_helmet_candidate_002.py`
- Create: `tests/python/test_smoke_shell_helmet_candidate_002.py`
- Generate: `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/qa_profiles/niko-walk-down-v1.json`
- Generate: `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/**`

**Interfaces:**
- Consumes: candidate 001 cleaned appearance, candidate 001 copy/effects, Niko atlas, rig profile, `analyze_harmony()`.
- Produces: `build_candidate_002(BuildInputs) -> CandidateMetadata`, `candidate-metadata.json`, derived icon, unchanged appearance copy, integer anchors, composites, actual-size preview, approval card, pixel QA, and harmony reports.

- [ ] **Step 1: Write failing preservation and derivation tests**

Tests take before-hashes of every candidate 001 file and the Niko atlas, run the builder into a temporary directory, then assert:

```python
assert after_hashes(CANDIDATE_001) == before_hashes
assert sha256(NIKO_ATLAS) == LOCKED_NIKO_HASH
assert output.icon.tobytes() == source_appearance.resize((256, 256), Image.Resampling.NEAREST).tobytes()
assert metadata["transform"]["shared_scale"] == 0.625
assert metadata["metrics"]["outer_width_ratio"] >= 1.05
assert metadata["metrics"]["outer_width_ratio"] <= 1.15
assert metadata["metrics"]["max_feature_center_error_px"] <= 1
assert metadata["metrics"]["max_residual_jitter_px"] <= 1
```

Also assert eight anchors, integer image offsets, no crop, zero protected-eye occlusion, binary alpha, transparent RGB zero, exact output dimensions, deterministic hashes, and no `curated` directory.

- [ ] **Step 2: Run tests to prove the builder is missing**

```powershell
& $harmonyPython -m pytest tests/python/test_smoke_shell_helmet_candidate_002.py -q
```

Expected: import fails because `build_smoke_shell_helmet_candidate_002.py` is absent.

- [ ] **Step 3: Implement exact candidate derivation**

Use these functions:

```python
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BuildInputs:
    appearance_source: Path
    niko_atlas: Path
    rig_profile: Path
    registry: Path
    output_root: Path


@dataclass(frozen=True)
class CandidateMetadata:
    candidate_id: str
    transform: dict[str, object]
    artifacts: Sequence[dict[str, object]]
    metrics: dict[str, object]


```

Implement `build_candidate_002(inputs: BuildInputs) -> CandidateMetadata`. Find the appearance aperture by four-connected enclosed-transparency flood fill. For each frame, compute integer offsets by rounding `face_center - aperture_center × 0.625`; verify the resulting measurement before accepting it. If hard gates fail, write diagnostics with `hard_fail` and exit without registry changes.

Load the canonical checker module from `tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py` with `importlib.util.spec_from_file_location`; do not duplicate checker logic in the builder. The builder CLI also accepts optional `--visual-rubric path/to/visual-rubric.json` and passes it through `apply_visual_rubric` during finalization.

The builder writes only its explicit artifact manifest and never recursively clears `output_root`. A finalization run reads and hashes `visual-rubric.json` before replacing generated report/metadata files, loads it through the checker's strict public loader, leaves the rubric unchanged, and refuses to reuse a non-empty directory whose `candidate_id` or source hashes differ. Immediately before atomic publication it rehashes every recorded source, including the rig profile. The checker is the sole writer of `harmony-overlay.png` and `harmony-actual-size.png`.

- [ ] **Step 4: Produce review artifacts from structured data**

Create:

```text
derived/icon-256.png
derived/appearance-128.png
appearance/anchors-walk-down.json
qa/composite-frame-001.png
qa/composite-atlas-8x128.png
qa/runtime-size-1920x1080.png
qa/harmony-overlay.png
qa/harmony-actual-size.png
qa/harmony-report.json
qa/visual-rubric.json
qa/pixel-qa-report.json
qa/approval-card.png
candidate-metadata.json
```

The approval card labels effects by reading the registry's structured `effects`; copy the already-approved bilingual description/flavor without embedding text into runtime sprites.

- [ ] **Step 5: Run candidate 001 regression and candidate 002 GREEN**

Run the checker against candidate 001 using its existing 0.75 anchors. Expected: `hard_fail` containing `scale_ratio_high` and `feature_center_offset`.

Run the builder/checker in a temporary directory. Expected preliminary candidate 002 checker verdict: `review`, with every deterministic hard gate passing and no hard-failure reason codes.

- [ ] **Step 6: Build the real candidate 002 once**

```powershell
& $harmonyPython tools/assets/build_smoke_shell_helmet_candidate_002.py `
  --appearance-source 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-001\cleaned\smoke-shell-helmet-appearance-128.png' `
  --niko-atlas 'game\content\packs\characters\niko\animations\walk_down\sprite-sheet-alpha.png' `
  --rig-profile 'tools\assets\rig_profiles\niko_walk_down_v1.json' `
  --registry 'game\content\assets\gogobro_static_assets_v1.json' `
  --output-root 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002'
```

Copy the rig profile to the asset-inbox QA profile path and verify its hash matches the versioned source.

- [ ] **Step 7: Inspect the generated visual evidence**

Use `view_image` on the preliminary approval card, 8-frame composite, harmony overlay, and actual-size preview. Confirm the face aperture tracks the face, the outer helmet no longer dominates the head, and no new pixel resampling is visible. A visual defect returns to Step 3 with one documented deterministic transform correction; it does not trigger image generation.

Write `qa/visual-rubric.json` with the five named dimensions, integer scores from 0–2, and one concrete evidence sentence per dimension. The total must be at least 8 and no dimension may be zero before finalization.

- [ ] **Step 8: Finalize the candidate with the rubric, run GREEN tests, and commit the builder**

Run the builder a second time with:

```powershell
& $harmonyPython tools/assets/build_smoke_shell_helmet_candidate_002.py `
  --appearance-source 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-001\cleaned\smoke-shell-helmet-appearance-128.png' `
  --niko-atlas 'game\content\packs\characters\niko\animations\walk_down\sprite-sheet-alpha.png' `
  --rig-profile 'tools\assets\rig_profiles\niko_walk_down_v1.json' `
  --registry 'game\content\assets\gogobro_static_assets_v1.json' `
  --visual-rubric 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002\qa\visual-rubric.json' `
  --output-root 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002'
```

Expected: final `harmony-report.json` and `candidate-metadata.json` record `harmony_pass` and the rubric hash.

```powershell
& $harmonyPython -m pytest `
  tests/python/test_smoke_shell_helmet_candidate_002.py `
  tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py -q
git add tools/assets/build_smoke_shell_helmet_candidate_002.py `
        tests/python/test_smoke_shell_helmet_candidate_002.py
git commit -m "feat: build corrected helmet review candidate"
```

---

### Task 5: Preserve Candidate History and Activate Candidate 002 in the Registry

**Files:**
- Modify: `game/content/assets/gogobro_static_assets_v1.json`
- Modify: `game/content/assets/static_asset_registry.gd`
- Modify: `tests/unit/test_static_asset_registry.gd`

**Interfaces:**
- Consumes: candidate 002 `candidate-metadata.json` with exact artifact roles, specs, byte sizes, hashes, metrics, and reports.
- Produces: one `smoke_shell_helmet` unit whose `active_candidate_id` is `candidate-002`, whose history contains preserved candidates 001/002, and whose unit status remains `review`.

- [ ] **Step 1: Write failing candidate-history tests**

Add assertions equivalent to:

```gdscript
assert_str(str(helmet["active_candidate_id"])).is_equal("candidate-002")
assert_int((helmet["candidate_history"] as Array).size()).is_equal(2)
var old_candidate := _candidate_history_entry(helmet, "candidate-001")
assert_str(str(old_candidate["decision"])).is_equal("revision_requested")
assert_array(old_candidate["reasons"]).contains_exactly([
    "icon_reuse",
    "appearance_offset",
    "appearance_oversized",
])
var active_candidate := _candidate_history_entry(helmet, "candidate-002")
assert_str(str(active_candidate["decision"])).is_equal("review")
assert_str(str(active_candidate["harmony_verdict"])).is_equal("harmony_pass")
assert_str(str(helmet["approval_status"])).is_equal("review")
```

Malformed fixtures must reject missing active candidate, duplicate candidate IDs, an active ID that does not resolve, multiple history entries marked `review`, missing candidate 001 artifacts, missing harmony/pixel reports, invalid hashes/bytes/specs, runtime paths, and `/curated/` paths.

- [ ] **Step 2: Run GdUnit to prove RED**

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/unit/test_static_asset_registry.gd"
```

Expected: new history assertions fail because only candidate 001 is represented by the old single-candidate fields.

- [ ] **Step 3: Implement the history schema and validator**

Move candidate 001's current provenance/artifacts unchanged into the first history entry. Load candidate 002's exact generated metadata for the second entry. Validate:

```text
active_candidate_id resolves exactly once
exactly one history decision is review
revision_requested entries retain artifacts and non-empty reasons
active entry contains pixel_qa_report and harmony_report roles
active harmony_verdict is harmony_pass or review, never approved
unit approval_status stays review
```

Keep compatibility only where the canonical file still needs it; remove obsolete single-candidate fields once tests no longer consume them so the registry has one source of truth.

- [ ] **Step 4: Run GREEN and inspect the actual candidate hashes**

Run the same focused GdUnit command. Expected: all registry cases pass.

Run a read-only Python audit that resolves every `workspace://` candidate 002 path, checks file existence, byte size, SHA-256, image dimensions, and report verdicts against `candidate-metadata.json`.

- [ ] **Step 5: Commit registry history**

```powershell
git add game/content/assets/gogobro_static_assets_v1.json `
        game/content/assets/static_asset_registry.gd `
        tests/unit/test_static_asset_registry.gd
git commit -m "feat: register corrected helmet review candidate"
```

---

### Task 6: Forward-Test and Deploy the Skill

**Files:**
- Modify: `tools/codex_skills/checking-gogobro-item-harmony/tests/behavioral-evidence.md`
- Install exact package files to: `C:/Users/18421/.codex/skills/checking-gogobro-item-harmony/`

**Interfaces:**
- Consumes: validated canonical skill source, installer, candidate 001/002 evidence.
- Produces: discoverable installed skill with source/installed hash parity and behavioral evidence proving the intended decision change.

- [ ] **Step 1: Install to an isolated temporary path**

```powershell
$skillTestTarget = 'E:\01_gobro\.codex-temp\skill-forward-test\checking-gogobro-item-harmony'
.\tools\install_gogobro_item_harmony_skill.ps1 `
  -SourceRoot (Resolve-Path 'tools\codex_skills\checking-gogobro-item-harmony').Path `
  -TargetRoot $skillTestTarget
```

The installer prints the manifest and verified hash for each file. It does not remove unrelated target files or directories and does not touch the personal skill directory during forward testing.

- [ ] **Step 2: Validate the temporary installed skill**

```powershell
& $harmonyPython 'C:\Users\18421\.codex\skills\.system\skill-creator\scripts\quick_validate.py' `
  $skillTestTarget
& $harmonyPython -m pytest `
  tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py `
  tests/python/test_install_gogobro_item_harmony_skill.py -q
```

Expected: structural validation and all focused tests pass.

- [ ] **Step 3: Run behavioral GREEN on candidate 001**

Dispatch a fresh evaluator, instruct it to read the temporary `$skillTestTarget/SKILL.md`, and give it the same candidate 001 prompt/paths used in Task 1.

Expected GREEN: verdict is revise or hard fail, with both `scale_ratio_high` and `feature_center_offset`, measured ratio near `1.31`, and no approval recommendation.

- [ ] **Step 4: Run forward test on candidate 002 and a non-head fixture**

Candidate 002 expected: deterministic hard gates pass; evaluator cites the smaller scale, aperture alignment, stable eight frames, and final human approval gate.

Synthetic back-slot expected: the evaluator uses back depth/region rules and does not apply the head aperture or eye-occlusion rules.

- [ ] **Step 5: Append verbatim GREEN evidence**

Append a `GREEN — with skill` section to `tests/behavioral-evidence.md` with evaluator verdicts, measured reason codes, and the non-head routing result.

- [ ] **Step 6: Install the verified package to the personal skill directory**

Only after Steps 2–5 pass, run:

```powershell
.\tools\install_gogobro_item_harmony_skill.ps1 `
  -SourceRoot (Resolve-Path 'tools\codex_skills\checking-gogobro-item-harmony').Path `
  -TargetRoot 'C:\Users\18421\.codex\skills\checking-gogobro-item-harmony'

& $harmonyPython 'C:\Users\18421\.codex\skills\.system\skill-creator\scripts\quick_validate.py' `
  'C:\Users\18421\.codex\skills\checking-gogobro-item-harmony'
```

Compare the four installed manifest hashes to canonical source hashes. Expected: exact equality.

- [ ] **Step 7: Commit behavioral evidence**

```powershell
git add tools/codex_skills/checking-gogobro-item-harmony/tests/behavioral-evidence.md
git commit -m "test: verify item harmony skill behavior"
```

---

### Task 7: Final Verification and Candidate 002 Approval Handoff

**Files:**
- Verify: all files from Tasks 1–6
- Present: `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/approval-card.png`

**Interfaces:**
- Consumes: committed implementation, installed skill, candidate 002 metadata, registry, and QA reports.
- Produces: evidence-backed approval request; no integration or further asset generation.

- [ ] **Step 1: Run every focused automated check fresh**

```powershell
& $harmonyPython -m pytest `
  tools/codex_skills/checking-gogobro-item-harmony/tests/test_check_item_harmony.py `
  tests/python/test_install_gogobro_item_harmony_skill.py `
  tests/python/test_smoke_shell_helmet_candidate_002.py -q

cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/unit/test_static_asset_registry.gd"

& $harmonyPython 'C:\Users\18421\.codex\skills\.system\skill-creator\scripts\quick_validate.py' `
  'C:\Users\18421\.codex\skills\checking-gogobro-item-harmony'
```

Expected: zero failures and valid installed skill.

- [ ] **Step 2: Run artifact and immutability audits fresh**

Verify:

```text
candidate 001 file hashes unchanged
candidate 002 artifact bytes/SHA match registry and candidate metadata
candidate 002 icon equals appearance nearest 2× pixel-for-pixel
candidate 002 pixel QA status pass
candidate 002 harmony verdict harmony_pass
outer ratio 1.05–1.15
center error ≤1 px
jitter ≤1 px
Niko atlas SHA equals the locked value
no candidate-002/curated directory
no runtime or startup file changed
installed skill hashes equal canonical source hashes
```

- [ ] **Step 3: Inspect all final visuals**

Use `view_image` on the candidate 002 approval card, composite atlas, actual-size preview, and harmony overlay. Confirm the visual result agrees with numeric evidence and the requested correction.

- [ ] **Step 4: Verify Git scope and working-tree cleanliness**

```powershell
git diff --check 26f66b7..HEAD
git status --short
git diff --name-status 26f66b7..HEAD
git diff --exit-code 26f66b7..HEAD -- game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png
```

Expected: clean worktree; only planned skill/tool/test/registry files changed; Niko diff exit `0`.

- [ ] **Step 5: Present candidate 002 and stop**

Show the approval card and summarize the exact icon derivation, before/after scale ratio, alignment/jitter metrics, test counts, Niko hash, skill path, and `review` status. Ask for `批准封烟头盔 002` or one targeted correction. Do not export, integrate, or begin the next asset until explicit approval.

## Execution Handoff

Plan execution should use **superpowers:subagent-driven-development** so the checker, candidate builder, registry schema, and skill behavior receive independent review gates. Inline execution remains possible with **superpowers:executing-plans** if the user prefers checkpointed batches in the current session.
