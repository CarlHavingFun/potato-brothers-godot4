# Behavioral evidence

## RED — without skill

- Candidate: `candidate-001`
- Required defect result: `scale_ratio_high` — missed
- Required defect result: `feature_center_offset` — missed

### Verbatim evaluator verdict and reasoning

**Verdict: REVISE**

The worn helmet integrates technically and stylistically with Niko: his face, beard, warm skin tones, and compact pixel treatment remain clear; the eight walk-down frames are stable without visible clipping or jitter; and it stays legible at runtime scale.

The key visual issue is icon-to-worn consistency. The icon’s most conspicuous accent is a bright orange illuminated strip on its right side, while the worn helmet instead presents a prominent teal-green side attachment. That makes them read as adjacent variants rather than the same item. The icon’s three-quarter silhouette is also more dense and armored than the cleaner front-facing worn version.

Revise the icon or worn asset so the same side module/accent color and material cues appear in both—preferably carry the teal attachment into the icon, or make the worn version retain the orange indicator. Keep the existing worn scale and face opening; those are harmonious with Niko.

## GREEN — with skill

- Candidate `candidate-001`: `hard_fail`; `scale_ratio_high` identified; `feature_center_offset` identified; measured ratio `1.3103448275862069`; approval blocked.
- Candidate `candidate-002`: `harmony_pass`; shared scale `0.625`; measured ratio `1.103448275862069`; aperture error `0.4375 px`; residual jitter `0.0 px`; explicit human approval still required.
- Synthetic `back` fixture: routed through `attachment_regions.back`, behind-depth, protected-face, and back-ratio rules; no head aperture or protected-eye rule was applied.

### Candidate 001 — verbatim evaluator output

<!-- BEGIN VERBATIM candidate-001 -->
~~~markdown
# Verdict: REVISE

**Checker verdict:** `hard_fail`
**Approval permitted:** **No.** The harmony hard gate blocks approval; the visual rubric is not scored after a hard failure.

| Reason code | Measurement | Required limit | Finding |
|---|---:|---:|---|
| `scale_ratio_high` | `1.3103448275862069` | `1.05–1.15` | The worn shell is 76 px wide against Niko’s 58 px head—visibly oversized and top-heavy in every frame. |
| `feature_center_offset` | `6.125 px` | `≤1 px` | The aperture is consistently about 4.125 px left and 6.125 px below `face_center`, placing the opening too low-left around Niko’s face. |
| `protected_region_occlusion` | `0.09583333333333334` (`9.5833%`) | `0` | The helmet intrudes into the protected eye ROI; the upper opening/brim visibly crowds the brow and eye line. |
| `icon_not_nearest_2x` | Pixel mismatch | Exact nearest-neighbor 2× derivation required | The icon is a separate three-quarter rendering, not a pixel-exact 2× version of the frontal worn appearance. |

**Residual jitter:** `0.0 px` against a `≤1 px` limit. Placement is stable across all eight frames, but it repeats the same incorrect scale and low-left alignment.

## Visual evidence

- **Approval card:** The icon and appearance share a coherent charcoal/olive palette, cream vent plate, heavy outline, and reinforced-shell function. However, their silhouettes do not match closely: the icon emphasizes a compact three-quarter dome, orange latch, and right-side mechanism, while the worn asset presents a broad frontal ring, large chin guard, and teal side module.
- **Eight-frame composite:** The helmet tracks Niko consistently, confirming the zero-jitter result. It nevertheless dominates his head in every frame, compresses the visible face opening, and crowds the eyes.
- **Actual-size preview:** At 1:1 runtime scale, the broad side pods and chin bar remain disproportionately prominent, weakening Niko’s recognizable head and face silhouette.
- **QA JSON:** Its `status: pass` confirms production hygiene—correct dimensions, binary alpha, cleared transparent RGB, no chroma remnants, safe margins, 18-color cleaned palette, eight anchors, and eight changed composite frames. Those checks do not evaluate head-slot scale, feature alignment, eye occlusion, or exact icon derivation, so they do not override the harmony checker.

Revise the worn geometry to the `1.05–1.15` width band, re-anchor the aperture to `face_center` within 1 px, eliminate all eye-region occlusion, and derive the icon as the required nearest-neighbor 2× representation of the finalized appearance. Re-run the checker before reconsidering approval.
~~~
<!-- END VERBATIM candidate-001 -->

### Candidate 002 — verbatim evaluator output

<!-- BEGIN VERBATIM candidate-002 -->
~~~markdown
# Smoke-Shell Helmet — Candidate 002 Harmony Review

**Final gate verdict: `harmony_pass`**
**Reason codes: `[]`**
**Explicit human approval still required: Yes.** The approval card still shows unit approval status `review`; this harmony result must not advance approval automatically.

## Deterministic gate

The prescribed checker completed with exit code `0`. Its raw verdict was `review` because no visual-rubric file was supplied; geometry passed with no hard-fail reason codes.

- Outer-width ratio: `1.103448275862069` in every frame, inside the head-slot range `1.05–1.15`.
- Scale comparison: shared scale is `0.625`; the placed shell is 64 px wide over Niko’s 58 px head, giving `64 / 58 = 1.103448`.
- Feature-center error: `0.4375 px`, below the `1 px` limit.
- Residual jitter: `0.0 px`, below the `1 px` limit.
- Protected-region occlusion: `0.0`, exactly satisfying the zero-occlusion requirement for `protected_regions.eyes`.
- Depth: `40` in all frames, matching the expected front depth and lying within `[1, 99]`.
- Aperture box: `[28, 58, 90, 98]`.
- Frame count: `8`.
- All five source hashes still match the checker report after verification.

## Aperture alignment and eight-frame stability

The aperture center is `(58.5, 77.5)`. At scale `0.625` and offset `(25, 23)`, it lands at `(61.5625, 71.4375)` against `face_center (62, 71)`, producing the reported `0.4375 px` maximum component error. Frames 5–6 use offset `(27, 23)` while the face center shifts to `(64, 71)`, preserving the same residual.

Placed boxes are:

- Frames 1–4 and 7–8: `[33, 29, 97, 97]`
- Frames 5–6: `[35, 29, 99, 97]`

Thus every box remains 64×68 px; frames 5–6 correctly follow Niko’s two-pixel horizontal shift. The eight-frame composite visibly confirms that the shell, brow vent, face aperture, and side module remain locked to the head without popping, crawling, or scale variation.

The freshly generated `harmony-overlay.png` is a box-only diagnostic and shows the same stable rectangles. Its `harmony-actual-size.png` supplies the base-atlas true-size reference. The supplied QA overlay, actual-size composite, eight-frame atlas, and approval card show the helmet composited on the same hash-matched inputs.

## Scale comparison

The 256×256 icon is the exact nearest-neighbor 2× derivative of the 128×128 appearance; the checker emitted no `icon_not_nearest_2x` code. At icon scale, the segmented shell, tan brow vent, dark aperture, and teal side apparatus are distinct. At the 0.625 gameplay placement, those principal forms remain readable while fine detail simplifies cleanly and the face remains dominant.

## Visual rubric

| Dimension | Score | Visible evidence |
| --- | ---: | --- |
| Character identity | 2/2 | Niko’s eyes, brows, nose, facial coloration, and expression remain clearly exposed through the aperture. The shell frames the face without replacing or obscuring the identifying facial read. |
| Item function | 2/2 | The reinforced segmented dome, enclosed jaw rim, brow vent, and asymmetric side apparatus immediately read as a heavy sealed protective helmet, matching the armor-plus-movement-penalty concept. |
| Material/outline fit | 2/2 | Dark stepped outlines, compact pixel clusters, muted metal greys/browns, and restrained highlights match the character’s pixel density and outline language. No alpha, palette, crop, or chroma hard-gate issue was reported. |
| Value/color hierarchy | 2/2 | The warm, brighter face remains the focal point; the dark neutral shell recedes around it. The tan vent is a clear secondary landmark and the teal side element works as a limited accent without competing with the face. |
| Originality | 2/2 | The combination of a sealed open-face shell, centered slotted brow plate, layered lower rim, and asymmetric teal smoke-control apparatus gives it a specific “smoke-shell” identity beyond a generic helmet. |

**Visual total: `10/10`.** No dimension is zero, and the total exceeds the required `8/10`; therefore the manual visual stage converts the raw geometry `review` into **`harmony_pass`** with no added reason codes.

Only the designated checker output directory was written. No source asset, source JSON, canonical skill, registry, visual-rubric file, or approval state was changed.
~~~
<!-- END VERBATIM candidate-002 -->

### Synthetic back slot — verbatim evaluator output

<!-- BEGIN VERBATIM synthetic-back -->
~~~markdown
# Item Harmony Verdict — Synthetic Niko Back Slot

**Final verdict: `review`**

The deterministic geometry gates passed, but the visual score is **3/10**, below the required 8/10 and containing zero scores. This candidate must not receive `harmony_pass` or advance approval.

## Checker result

- Checker verdict: `review`
- Exit code: `0`
- Reason codes: `[]`
- Frame count: `8`
- Frame boxes:
  - Frames 0–3: `[42, 84, 82, 101]`
  - Frames 4–5: `[44, 84, 84, 101]`
  - Frames 6–7: `[42, 84, 82, 101]`
- Outer-width ratio: `0.8333333333333334`
- Per-frame ratios: `0.8333333333333334` for all eight frames
- Maximum feature-center error: `0.0 px`
- Maximum residual jitter: `0.0 px`
- Maximum protected-region occlusion: `0.19047619047619047`
- Aperture box: `null`

No deterministic hard-fail reason was produced.

## Back-slot profile application

- Attachment anchor: center of `attachment_regions.back`
- Allowed silhouette-width ratio: back width × `0.60–1.20`
  - Measured: `0.8333333333333334`, within bounds
- Protected region: `protected_regions.face`
- Maximum permitted occlusion: `0.25`
  - Measured: `0.19047619047619047`, within limit
- Feature-center tolerance: `2 px`
  - Measured: `0.0 px`
- Residual-jitter limit: `1 px`
  - Measured: `0.0 px`
- Depth band: behind character, `-99–-1`
- Expected depth: `-10`
  - Actual anchor depth: `-10` in every frame
- Flip behavior: `none`

The **head aperture rule was not applied**; `aperture_box` is `null`. The **protected-eye rule was also not applied**. Those are head/face-slot rules; this back-slot review correctly used the protected `face` region and back attachment boxes.

## Visual rubric

Both [harmony-overlay.png](E:\01_gobro\.codex-temp\skill-forward-test\evaluator-runs\synthetic-back-slot\harmony-overlay.png) and [harmony-actual-size.png](E:\01_gobro\.codex-temp\skill-forward-test\evaluator-runs\synthetic-back-slot\harmony-actual-size.png) were inspected.

| Category | Score | Visible evidence |
|---|---:|---|
| Character identity | **2/2** | Niko’s hair, face, eyes, beard, white clothing, and walking-frame identity remain clearly readable across all eight frames. |
| Item function | **0/2** | The appearance is only a flat brown rectangle. In the actual-size composite it is almost entirely buried behind Niko, leaving at most tiny dark edge pixels; no recognizable backpack, cape, sheath, or other back-item function is communicated. |
| Material/outline fit | **0/2** | The candidate has one flat fill with no authored outline, internal shading, highlights, texture, or pixel clusters matching Niko’s outlined, multi-tone sprite treatment. |
| Value/color hierarchy | **1/2** | Its muted brown does not compete with Niko’s face, but the low contrast and behind-character placement make it effectively disappear instead of forming a useful secondary read. |
| Originality | **0/2** | The worn asset is a primitive rectangle, and the icon presents the same generic rectangle enlarged without a distinct silhouette or authored design language. |

**Total: 3/10**

Geometry, anchoring, depth, and occlusion are valid, but visual harmony is not. The item lacks recognizable function, runtime readability, material treatment, and originality. The correct final state is therefore **`review`**.

All supplied input SHA-256 hashes still match those recorded by the checker; no source input, canonical skill, registry, or approval state was changed.
~~~
<!-- END VERBATIM synthetic-back -->

## GREEN — diagnostic compositing regression

These fresh independent evaluations exercise the compositing diagnostics added by the checker. The evaluator source files contained no trailing spaces or tabs, so no Markdown hard-break normalization was necessary. For each block below, the UTF-8 bytes between the fenced block delimiters are identical to the corresponding evaluator source file, including its final newline.

- Candidate-002 source SHA-256: `c673316a2d7ce10b0ad0574f846198f2e54830c9a98c464b332cf20d3e45e396`; normalized embedded payload SHA-256: `c673316a2d7ce10b0ad0574f846198f2e54830c9a98c464b332cf20d3e45e396`; normalized lines: `0`.
- Synthetic-back source SHA-256: `b2ab5a0d86dcfc75a50d9207171dd0269091a1b58d7ef17688bb8aff2cb3bca6`; normalized embedded payload SHA-256: `b2ab5a0d86dcfc75a50d9207171dd0269091a1b58d7ef17688bb8aff2cb3bca6`; normalized lines: `0`.

### Candidate 002 visible diagnostics — verbatim evaluator output

<!-- BEGIN VERBATIM diagnostic-candidate-002 -->
~~~markdown
# Verdict: `harmony_pass`

The checker exited `0`. Its deterministic stage returned `review` only because no visual rubric was supplied; `reason_codes: []`. Applying the required visual rubric gives **9/10 with no zero score**, advancing the evaluator verdict to `harmony_pass`.

## Hard-gate measurements

| Check | Result | Limit | Status |
|---|---:|---:|---|
| Outer-width ratio | `1.103448` in all 8 frames | `1.05–1.15` | Pass |
| Max center error | `0.4375 px` | `≤1 px` | Pass |
| Residual jitter | `0.0 px` | `≤1 px` | Pass |
| Eye occlusion | `0.0` | `0` | Pass |
| Depth | `40` in all frames | Front `1–99`, expected `40` | Pass |
| Frame count | `8` | `8` | Pass |

The geometric boxes reconstructed from pixels matched the report in all frames: `[33,29,97,97]` except frames 5–6, which correctly shift to `[35,29,99,97]`.

## Eight-frame pixel evidence

| Frame | Helmet pixels present | Eye ROI | Overlay visibility |
|---:|---:|---:|---:|
| 1 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 2 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 3 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 4 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 5 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 6 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 7 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |
| 8 | `2559/2559` exact | `480/480` unchanged | `2524/2559` retained |

An independent base-then-item front-depth reconstruction differed from `harmony-actual-size.png` by **0 pixels**. The crown plate, side shells, open aperture, and chin rim are visibly worn in every frame. Eyes, brows, nose, and beard remain readable. Diagnostics annotate only `35/2559` item pixels per frame—about `1.37%`—so they do not hide the helmet.

## Visual rubric

| Dimension | Score | Evidence |
|---|---:|---|
| Character identity | 2/2 | Niko’s face and animation remain recognizable; eyes are completely unobstructed. |
| Item function | 2/2 | Clearly reads as a protective open-face shell helmet in every frame. |
| Material/outline fit | 2/2 | Chunky pixel clusters, dark outline, and muted shell shading match the character’s rendering density. |
| Value/color hierarchy | 2/2 | Light forehead plate provides focus while the dark shell frames rather than overwhelms the face. |
| Originality | 1/2 | Conventional helmet foundation, differentiated by the asymmetric teal shell detail and rectangular crown plate. |
| **Total** | **9/10** | **Pass** |

Source hashes still match the checker report. Only the three fresh evidence files were written:

- [harmony-report.json](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/candidate-002/harmony-report.json)
- [harmony-overlay.png](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/candidate-002/harmony-overlay.png)
- [harmony-actual-size.png](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/candidate-002/harmony-actual-size.png)

`harmony_pass` clears this harmony gate only. Registry state and approval state were not changed; explicit human approval is still required before canonical adoption.
~~~
<!-- END VERBATIM diagnostic-candidate-002 -->

### Synthetic back-slot visible diagnostics — verbatim evaluator output

<!-- BEGIN VERBATIM diagnostic-back -->
~~~markdown
# Verdict: `review`

The deterministic `back`-slot gate passes, but the visual rubric scores **5/10**, so the final verdict remains `review`. No approval state was advanced.

Artifacts: [overlay](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/synthetic-back-slot/harmony-overlay.png) · [actual size](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/synthetic-back-slot/harmony-actual-size.png) · [report](E:/01_gobro/.codex-temp/skill-forward-test/fix-round-2-fresh-evaluator-runs/synthetic-back-slot/harmony-report.json)

## Checker result and metrics

| Measurement | Result | Back-slot limit |
|---|---:|---:|
| Reason codes | none | — |
| Frames | 8 | 8 |
| Width ratio, every frame | `0.833333` | `0.60–1.20` |
| Feature-center error | `0 px` | ≤ `2 px` |
| Residual jitter | `0 px` | ≤ `1 px` |
| Protected-face occlusion | `0.190476` (`288/1512`) | ≤ `0.25` |
| Depth, every frame | `-10` | `-99…-1`; expected `-10` |
| Aperture box | `null` | Correct for non-head slot |

Placed boxes are `[42,84,82,101]` in frames 0–3 and 6–7, and `[44,84,84,101]` in frames 4–5.

## Pixel evidence

The supplied item is a fully opaque `40×17` rectangle: 680/680 bbox pixels, color RGBA `(63,48,35,255)`.

| Frame | Exterior item pixels visibly preserved | Overlap pixels occluded by Niko |
|---:|---:|---:|
| 0 | 16/16 | 664/664 |
| 1 | 20/20 | 660/660 |
| 2 | 24/24 | 656/656 |
| 3 | 20/20 | 660/660 |
| 4 | 24/24 | 656/656 |
| 5 | 32/32 | 648/648 |
| 6 | 32/32 | 648/648 |
| 7 | 20/20 | 660/660 |

All eight actual-size frames exactly match an item-first/Niko-second composite. A hypothetical front-layer composite differs at every overlap pixel—5,252 pixels total—while 188 exterior brown pixels remain visible. This confirms genuine composition in every frame and correct negative-depth ordering.

## Slot-rule evidence

- The diagnostic target centers are at rounded `(62,92)` or `(64,92)`, exactly matching `attachment_regions.back`; they are not at the face/head center near `y=71`.
- Cyan protected guides span the full face ROI (`x=44…79` or `46…81`, `y=50…91`). Zero of the 88 eye-boundary pixels per frame are cyan.
- The measured `0.190476` occlusion is exactly the face intersection. Eye overlap is `0`, further proving protected-face—not protected-eye—logic.
- The item ratio is `40/48 = 0.833333`, inside the back range. A head calculation would be `40/58 = 0.689655`, outside the head range `1.05–1.15`.
- The appearance bbox is completely opaque and has no enclosed aperture; nevertheless geometry passes and `aperture_box` is `null`. No head-aperture logic was applied.

## Visual rubric

| Dimension | Score | Visible evidence |
|---|---:|---|
| Character identity | 2 | Niko’s face and silhouette remain dominant and correctly occlude the item. |
| Item function | 0 | The few exposed pixels form only a plain rectangle; no recognizable back-item function reads. |
| Material/outline fit | 1 | Dark brown is broadly palette-compatible, but the item has no outline, texture, or shading. |
| Value/color hierarchy | 2 | Its dark value stays subordinate and does not compete with Niko’s face. |
| Originality | 0 | Single-color rectangular construction has no distinctive motif. |
| **Total** | **5/10** | Below the required 8/10, with zero scores. |

Fresh verification found exactly the three expected output files, and all five input hashes still match the report.
~~~
<!-- END VERBATIM diagnostic-back -->
