# GOGOBRO item–character harmony design

## Purpose

Create Smoke-Shell Helmet candidate 002 from the approved correction direction, and add a reusable Codex skill that catches item/character scale, alignment, occlusion, pixel-style, and multi-frame stability problems before an approval card is shown.

Candidate 001 proved why the extra gate is needed: its ordinary sprite QA passed, but the worn helmet was visibly too large and offset. The measured outer helmet width was about 76 px against a 58 px head width (1.31×). Its face aperture center also differed from the outer-silhouette center by about 5 px, while the original anchoring centered the outer silhouette.

## Scope

This change will:

- preserve candidate 001 and all of its provenance;
- create exactly one targeted candidate 002 without new AI generation;
- derive the 256×256 icon directly from the existing 128×128 transparent appearance using nearest-neighbor 2× scaling;
- reduce and realign the worn appearance using the face aperture rather than the outer helmet bounds;
- create and test a reusable personal skill named `checking-gogobro-item-harmony`;
- update the registry so candidate 002 is the active `review` candidate while candidate 001 remains in history;
- produce a new approval card, actual-size preview, diagnostic overlay, and deterministic QA/harmony reports.

This change will not:

- generate or redesign helmet art;
- modify, resample, or replace the Niko base atlas;
- create a new animation state;
- export anything into `curated`;
- integrate the item into runtime content or change the startup chain;
- advance the item beyond `review` without explicit user approval.

## Chosen approach

Use a hybrid gate:

1. A deterministic checker enforces measurable constraints such as scale, anchor drift, protected-region occlusion, cropping, palette, alpha, and pixel density.
2. A short visual rubric checks qualities that geometry cannot prove: identity readability, material fit, value hierarchy, functional silhouette, and original tactical-community flavor.
3. Human approval remains the final authority. The skill may return `harmony_pass`, `review`, or `hard_fail`; it may never mark an asset `approved`.

Pure visual judgment is not reproducible, while purely numeric checks cannot judge material and silhouette character. The hybrid gate keeps hard failures deterministic without pretending that visual harmony is entirely numerical.

## Candidate 002 transformation

### Icon

Use the candidate 001 cleaned appearance as the single source. Scale its full 128×128 canvas to 256×256 with nearest-neighbor sampling. Preserve binary alpha, clear RGB under transparent pixels, and do not crop, redraw, recolor, or add a separate icon silhouette. This makes the approval card's second image the canonical icon, as requested.

### Worn appearance

Keep the cleaned 128×128 appearance file unchanged and change only its per-frame transform metadata:

- initial shared scale: `0.625` instead of `0.75`;
- alignment feature: largest enclosed transparent face aperture;
- target: each Niko frame's face center from the rig profile;
- offsets: integer pixels only;
- target helmet/head outer-width ratio: `1.05–1.15` for this candidate;
- target aperture-center error: at most 1 px per frame;
- target residual frame jitter after following the face anchor: at most 1 px;
- no opaque helmet pixels may cover the protected eye region;
- the appearance must remain fully inside the 128×128 frame.

The checker may suggest a neighboring pixel-safe scale in 1/16 increments if `0.625` cannot meet all hard gates, but it must record the reason and may not overwrite source files. Candidate 002 will still contain only one chosen transform.

## Skill package

Create the personal skill at:

```text
C:/Users/18421/.codex/skills/checking-gogobro-item-harmony/
├── SKILL.md
├── agents/openai.yaml
├── references/slot-profiles.md
├── scripts/check_item_harmony.py
└── tests/test_check_item_harmony.py
```

The skill automatically applies when reviewing or integrating GOGOBRO item icons, character appearance layers, anchor manifests, composites, or approval cards for visual harmony.

### Checker interface

The deterministic script accepts:

```text
check_item_harmony.py
  --character-atlas <1024x128 PNG>
  --appearance <128x128 PNG>
  --icon <PNG>
  --anchors <JSON>
  --rig-profile <JSON>
  --slot <slot-name>
  --out-dir <directory>
  [--suggest-transform]
```

Check mode is read-only with respect to source assets. `--suggest-transform` may write a separate suggestion JSON and diagnostic image, never mutate the input appearance or anchors.

### Required outputs

- `harmony-report.json`: input hashes, measured values, thresholds, reasons, and verdict;
- `harmony-overlay.png`: per-frame protected regions, feature centers, bounding boxes, and errors;
- `harmony-actual-size.png`: 1920×1080 actual-size context;
- optional `transform-suggestion.json`: scale and integer offsets with objective measurements.

All outputs are deterministic for identical inputs and configuration.

## Rig and slot profiles

The checker consumes an explicit rig profile instead of guessing semantic body regions from alpha alone. The Niko profile records, per frame:

- head center and robust head width;
- face center;
- protected eye and face regions;
- torso, wrist, foot, back, side, and trinket attachment regions;
- front/back depth expectations.

`references/slot-profiles.md` defines defaults for `head`, `face`, `torso`, `back`, `wrist`, `feet`, `side_left`, `side_right`, `trinket_left`, and `trinket_right`. An asset may narrow a range in its candidate contract, but it may not silently relax a hard safety gate.

## Harmony checks

### Deterministic hard gates

- expected canvas and atlas dimensions;
- nearest-compatible pixel grid;
- binary alpha and RGB zero under transparent pixels;
- no chroma residue;
- configured palette range and outline continuity;
- unique appearance slot and valid depth expectation;
- no frame cropping;
- feature-center alignment within the slot threshold;
- silhouette scale within the candidate/slot threshold;
- protected-region visibility and occlusion limits;
- residual multi-frame anchor jitter within threshold;
- icon/source derivation contract when direct reuse is requested;
- unchanged character atlas hash;
- complete provenance for every generated report or preview.

Any hard-gate failure returns `hard_fail` and a non-zero process exit. It also reports an actionable correction such as “reduce shared scale” or “align aperture center +3 px on X”; it does not repair the asset automatically.

### Visual rubric

After hard gates pass, the skill requires an evidence-based 0–2 score for each dimension:

- character identity remains immediately readable;
- item silhouette communicates its function;
- material and outline language belong with the character;
- value and color hierarchy do not overpower the face/body;
- tactical-community flavor is original and commercially isolated.

A total below 8/10 or any zero returns `review`. A total of at least 8/10 with no hard failure returns `harmony_pass`. Neither result changes registry approval status automatically.

## Candidate and registry data flow

```text
candidate 001 preserved
→ derive candidate 002 icon from appearance
→ generate transform suggestion
→ choose one integer-pixel transform
→ build 8 composites and actual-size preview
→ run pixel QA and harmony checker
→ record all paths, sizes, hashes, metrics, and reports
→ set candidate 002 as active review candidate
→ show approval card and stop
```

The registry keeps candidate 001 with decision `revision_requested` and the user's reasons `icon_reuse`, `appearance_offset`, and `appearance_oversized`. Candidate 002 becomes the active candidate. The unit-level status remains `review`; the global state vocabulary is unchanged.

## Error handling

The checker fails without partial approval output when:

- an input path, hash, frame, rig profile, or required region is missing;
- the appearance has no alpha silhouette;
- a required aperture/feature cannot be identified unambiguously;
- anchor count differs from the character frame count;
- source assets change during execution;
- a suggested transform would crop the item or violate a protected region.

Diagnostic files may still be emitted on failure, clearly marked `hard_fail`. Source and prior-candidate files remain untouched.

## Test strategy

Follow RED–GREEN–REFACTOR for both the script and the skill instructions.

### Baseline failure

Use candidate 001 as the real regression: ordinary sprite QA passes while the harmony test must fail for the 1.31× helmet ratio and aperture-based center error. A no-skill behavioral evaluation documents that an evaluator can approve candidate 001 by focusing only on alpha, palette, and hash checks.

### Script tests

- centered, correctly scaled head item passes;
- oversized item fails with the measured ratio;
- aperture/face offset fails with X/Y evidence;
- protected-eye occlusion fails;
- cropped appearance fails;
- two-frame and eight-frame jitter failures are detected;
- correct nearest 2× icon reuse passes and any pixel difference fails;
- slot profiles apply distinct regions and depth expectations;
- identical runs produce byte-identical JSON metrics and diagnostic rasters;
- candidate 001 fails for the expected reasons;
- candidate 002 passes every hard gate.

### Skill tests

- validate the skill package with `quick_validate.py`;
- run realistic no-skill and with-skill evaluation scenarios;
- verify the with-skill evaluator identifies candidate 001's size and aperture-alignment defects;
- independently forward-test the skill on at least one non-head synthetic item so it does not overfit the helmet.

## Acceptance criteria

- candidate 001 is byte-preserved and remains auditable;
- candidate 002 uses the second transparent image as its icon with exact nearest 2× derivation;
- candidate 002 meets the 1.05–1.15 helmet/head width target;
- every frame's aperture center error and residual jitter are at most 1 px;
- protected eyes remain visible and no frame is cropped;
- pixel QA and harmony hard gates pass;
- visual rubric is at least 8/10 with no zero;
- Niko atlas hash remains `FBC10108D9A665B14DCC376DA54BBBF66D89B931AE1189E69FE1C45B31FE579D`;
- the new skill passes structural, script, behavioral, and forward tests;
- registry history preserves candidate 001 and activates candidate 002 at `review` only;
- no `curated` or runtime integration occurs before explicit approval.
