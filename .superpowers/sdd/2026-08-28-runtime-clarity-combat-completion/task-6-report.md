# Task 6 Report — Static Release Promotion

## Outcome

- Implementation commit: `2a1b23c` (`feat: promote accepted static assets to release`)
- Promoted the exact accepted union: 65 candidate-preview units + 5 retained shipping-only units = 70 stable IDs.
- The exact four overlaps (`ballistic_liner`, `service_pistol`, `smoke_shell_helmet`, `warmup_shiv`) now use the newer accepted preview bytes in shipping. Preview copies remain intact.
- Canonical registry: 70 `approved`; shipping manifest: 70 `requested_active`; runtime: 70 ready, 0 fallback, no issues, `release_ready == true`.
- Release content now loads 12 weapons, 30 items, and 6 upgrades under their existing IDs. Release definitions omit the `candidate_preview` tag, while debug still creates the candidate overlay.

## Deterministic build and evidence

The builder now validates the candidate manifest header and exact 65-unit identity set; external accepted source and in-project preview byte hashes; decoded dimensions; display dimensions; pivots; anchors; selector order; nearest filtering; and mipmap policy. It unions those units with the exact five shipping-only IDs and refuses any set other than the canonical 70.

The approval record binds the user-authorized scope, source design, three final actual-size review reports, accepted source hashes, exact shipping byte/RGBA8 hashes, selector RGBA8 hashes, and generated runtime bindings.

- Approval record SHA-256: `04DAD044C3EEC2EF349C7AA8FE224203D15590AC3E87B2AD67C48EAD020B897A`
- Review-board SHA-256: `76870F81D749BED544214FA844819E157B0DBA7A346DA5FF3B84AC3F6B8EDAC2`
- Canonical registry SHA-256: `33D1EA1D276ED5FB862075B28A9A88451DAE518BDBE28CE217266A570E9321C2`
- Neither the new approval nor registry evidence uses the old Wave033 approval/review evidence hashes.

Builder proof:

```text
python tools/build_static_shipping_install.py
PASS static shipping plan: 70 active / 0 inactive; pending=3; registry=33D1EA1D276ED5FB862075B28A9A88451DAE518BDBE28CE217266A570E9321C2

python tools/build_static_shipping_install.py --apply
PASS static shipping plan: 70 active / 0 inactive; pending=0; registry=33D1EA1D276ED5FB862075B28A9A88451DAE518BDBE28CE217266A570E9321C2

python tools/build_static_shipping_install.py
PASS static shipping plan: 70 active / 0 inactive; pending=0; registry=33D1EA1D276ED5FB862075B28A9A88451DAE518BDBE28CE217266A570E9321C2
```

The final three pending files above were the deliberately refreshed approval timestamp and its two derived hash-bound JSON documents. The earlier full media application was also followed by a zero-pending dry-run.

## TDD and verification

RED was recorded before implementation:

- Registry expected 70 approved, observed 9 approved / 61 planned.
- Runtime expected 70 ready / 0 fallback, observed 9 ready / 61 fallback.
- Release content expected 12 weapons / 30 items / 6 upgrades, observed 2 / 6 / 6.
- Builder test expected `70 active / 0 inactive`, observed `9 active / 61 inactive`.
- Godot RED report: `reports/task6-red-focused/report_1/results.xml`.

Final GREEN verification:

- `python -m unittest discover -s tests/python -p test_build_static_shipping_install.py -v` — 1/1 passed. This verifies idempotent `pending=0`, 65+5 identity union, preview preservation, four overlap hashes, new evidence hashes, all 70 registry/manifest/approval bindings, and actual shipping bytes.
- Focused registry/runtime/release-content suites — 47/47 passed, 0 failures (`reports/task6-final-focused/report_1/results.xml`).
- Candidate preview/overlay/coverage suites — 25/25 passed, 0 failures (`reports/task6-green-preview-coverage-final/report_1/results.xml`).
- Static consumer and modifier suites — 12/12 passed, 0 failures (`reports/task6-green-consumers/report_1/results.xml`).
- Shipping visual smoke — passed with `STATIC_SHIPPING_RUNTIME_VISUAL_V1_OK`; asserted 70 ready, 0 fallback, no issues, release-ready, and no development preview overlay.
- Smoke capture SHA-256: `36FF6F8B6F23D5F5115E0D38CF0CBB093181833AF02E2709CF8154B5070F8B84`.
- Windows `--export-release` — passed without launching the exported game. Export proof: `GOGOBRO.exe` SHA-256 `04BAF75CC1D69DD93EB709533ECAB4FD7770BB8A530645717017A06A9D9809FC`; `GOGOBRO.pck` SHA-256 `BFD6A02ED0EDF113D4BAC36C6276085719105C6562BAA371AD6657D811BDFEBC`.
- `git diff --check` / staged-path audit — clean; all 173 implementation files were Task 6 paths. Task 2 UI changes and editor-created preview `.import` / unrelated `.uid` noise were excluded.

## Implementation note

The accepted variant sources for `community_server_decor_pack`, `card_and_rarity_frame_kit`, and `four_state_button` contain soft alpha or non-zero transparent RGB. Their exact accepted bytes are retained as shipping sibling source files and fully hash-bound in the approval record. The runtime atlas alone is deterministically normalized to binary alpha with zeroed transparent RGB, and the approval record separately binds every normalized selector RGBA8 hash. No coarse asset was upscaled; runtime display sizes follow the accepted current dimensions.

## Remaining concerns

No Task 6 failures remain. Two pre-existing candidate-manifest tests emit Godot warnings because they use `Image.load()` on source PNGs; both tests pass, and the warnings are unrelated to the shipping runtime or release export.
