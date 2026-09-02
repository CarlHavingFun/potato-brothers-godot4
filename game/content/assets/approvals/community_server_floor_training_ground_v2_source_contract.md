# Training-ground arena base v2 — shipping source contract

- Logical asset ID: `community_server_floor`
- Raw provenance path: `res://game/assets/gogobro_static/world/community_server_floor_training_ground_v2_1448x1086.png`
- Shipping path: `res://game/assets/gogobro_static/world/community_server_floor_training_ground_v2_2048x1536_rgba8.png`
- Raw generated source: `exec-392ba628-94e8-4c08-80af-77ae96296fd5.png`
- Source PNG SHA-256: `FA7EF4C76185BC321F182D0838701AB4BB171E72CD936A3CC45296A62F3C70AA`
- Source size: `1448 × 1086`, opaque RGB PNG
- Shipping PNG SHA-256: `AFD075592C1C7E6EC5423E2C63E09454C7222F4DAD23FFAD841B3F96708A0EEC`
- Shipping decoded RGBA8 SHA-256: `C7641010C8FF6CD45C703C605FF734E6AF49F65937B3E6794BB9BF9ABB427917`
- Shipping and runtime size: `2048 × 1536`, RGBA8 PNG
- Runtime sampling: nearest, no mipmaps
- Raw prompt: `community_server_floor_training_ground_v2_prompt.md`

The raw generated source is preserved byte-for-byte. The shipping output is a
deterministic, no-crop resize made with Pillow `12.2.0`,
`Image.Resampling.LANCZOS`, RGBA8 conversion, `optimize=False` and PNG
`compress_level=9`. Two independent encodes in the same process were byte
identical. The prior `community_server_floor.png` and its approval records
remain in place and are not overwritten. Runtime must mount exactly one centered
`Sprite2D` for the whole arena: no tile grid, no repeated seams, and no
ordinary-run props. The image-owned perimeter supplies the visible boundary;
its central play area does not introduce interaction semantics or collision.

Authority is limited to the current art-v2 goal: the user authorized the
supervisor to make ordinary visual choices. This is not a per-image explicit
user approval, and it does not authorize any other static asset or path.
