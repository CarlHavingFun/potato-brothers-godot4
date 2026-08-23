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
