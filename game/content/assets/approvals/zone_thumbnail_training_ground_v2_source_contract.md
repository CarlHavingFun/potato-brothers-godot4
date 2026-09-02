# Training-ground task art v2 — shipping source contract

- Logical asset ID: `zone_thumbnail`
- Raw provenance path: `res://game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_1672x941.png`
- Shipping path: `res://game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_256x144_rgba8.png`
- Raw generated source: `exec-ed6f3d07-e44b-4375-aece-7d5bb800156e.png`
- Source PNG SHA-256: `47FA7559B0774D5E514D9149464B1BC76BBE9DC33058FB4B2959A1620CEC00F8`
- Source size: `1672 × 941`, opaque RGB PNG
- Shipping PNG SHA-256: `FB341F882F46D9EAD7C3D1601814481B9F4A090156B4DEFD5726569A98746584`
- Shipping decoded RGBA8 SHA-256: `86A91AAB941868EB6EEF590D819FFD80199EB8174391FA1A7CBC721D198B3A7F`
- Shipping and runtime size: `256 × 144`, RGBA8 PNG
- Runtime sampling: nearest, no mipmaps
- Raw prompt: `zone_thumbnail_training_ground_v2_prompt.md`

The raw generated source is preserved byte-for-byte. The shipping output is a
deterministic, no-crop resize made with Pillow `12.2.0`,
`Image.Resampling.LANCZOS`, RGBA8 conversion, `optimize=False` and PNG
`compress_level=9`. Two independent encodes in the same process were byte
identical. The previous `zone_thumbnail.png` remains in place and is not
overwritten. The logical asset ID remains stable so the training-ground release
definition keeps one real task-art binding while old saves and content IDs
remain compatible.

Authority is limited to the current art-v2 goal: the user authorized the
supervisor to make ordinary visual choices. This is not a per-image explicit
user approval, and it does not authorize any other static asset or path.
