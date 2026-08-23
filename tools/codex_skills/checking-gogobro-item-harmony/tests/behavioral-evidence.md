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

## GREEN — final a0bc44b skill

Fresh forward evaluation used the exact temporary-installed four-file skill at
`E:/01_gobro/.codex-temp/checking-gogobro-item-harmony-a0bc44b-root`.

- Candidate `candidate-001`: `hard_fail`; retained measured `scale_ratio_high` and `feature_center_offset`, and added `formal_pixel_contract_required`; approval blocked.
- Fresh candidate `candidate-002`: deterministic `review` with no hard-fail reasons; independent visual rubric produced `harmony_pass` at 9/10; ratio `1.0689655172413792`, feature error `1.0 px`, jitter `0.0 px`, occlusion `0.0`.
- The committed external review candidate separately uses the five-score 10/10 rubric at SHA-256 `617b7c1a95917a9a8f903a54a5be68cc49b6162c9593c8f73960450e5cad0c6b`; its hierarchy evidence records the current exact-raster `62/58 = 1.0689655172413792`. The independent 9/10 rubric below is forward-test evidence, not the committed artifact.
- Formal pixel evidence: appearance/icon exact 2x/4x grid round-trips, exact direct-icon reuse, 18 opaque colors, binary alpha, transparent RGB cleared, source outline `563/563`, and all eight rendered outlines `329/329`.
- Synthetic `back` fixture: back-region/depth rules applied; no head aperture or protected-eye rule; deterministic geometry passed while a 3/10 visual rubric correctly kept it in `review`.
- Candidate 002 remains explicitly human-gated: approval status `review`, with no `curated/` output.

Evaluator report SHA-256:
`86bbc319a4bdb0b84277075e8c583bacc9d97d5fbdd0cb99b5ba79f45e3bacbc`.

### Verbatim fresh evaluator report

<!-- BEGIN VERBATIM final-a0bc44b -->
~~~markdown
# a0bc44b item-harmony fresh forward behavioral evaluation

## 结论

评估对象为提交 `a0bc44b` 的 canonical builder，以及完整读取后执行的临时安装 skill：

- Skill：`E:/01_gobro/.codex-temp/checking-gogobro-item-harmony-a0bc44b-root/SKILL.md`
- Checker：`E:/01_gobro/.codex-temp/checking-gogobro-item-harmony-a0bc44b-root/scripts/check_item_harmony.py`
- Fresh 输出根：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001`

三例结果符合预期：

| 用例 | Deterministic gate | 完整视觉 verdict | 结论 |
| --- | --- | --- | --- |
| `candidate-001` 旧 anchors | `hard_fail` | 因 hard gate 失败而停止，不打视觉分 | 正确保留实际几何并阻止审批 |
| Fresh `candidate-002` | `review`, `reason_codes: []` | `harmony_pass`, 9/10 | 几何、像素、轮廓与视觉和谐门均通过 |
| Synthetic `back` | `review`, `reason_codes: []` | `review`, 3/10, `visual_rubric_review` | 正确走 back 规则；测试矩形不是可批准美术 |

`candidate-002` 的 `harmony_pass` 只通过和谐门。最终审批卡仍明确显示 `Unit approval status: review`，注册表审批状态仍为 `review`，fresh 输出中没有 `curated/`；因此仍必须由用户明确审批。

## 1. Candidate 001：旧 anchors 的可测 hard fail

- Checker 退出码：`2`
- Verdict：`hard_fail`
- Reason codes：
  - `feature_center_offset`
  - `formal_pixel_contract_required`
  - `icon_not_nearest_2x`
  - `protected_region_occlusion`
  - `scale_ratio_high`
- 旧 shared scale：`0.75`
- 实际 raster 外宽比：`1.3103448275862069`，即每帧 `76 / 58`
- 实际最大 feature-center error：`6.0 px`
- 实际 residual jitter：`0.0 px`
- 实际 protected-eye occlusion：`0.04791666666666667`
- 实际 frame boxes：前四帧及第七、八帧 `[24,26,100,108]`；第五、六帧 `[26,26,102,108]`
- Aperture box：`[28,58,90,98]`
- Atlas expected/actual SHA-256 均为 `fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d`
- `source_integrity.changed_keys: []`

这证明 canonical v1 rig 不再让整数 schema `1` 绕过正式 pixel contract，同时 checker 仍继续测量并报告旧候选的真实 scale、feature、occlusion 与 frame geometry。

报告：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-001/qa/harmony-report.json`

## 2. Fresh Candidate 002：通过正式像素与和谐门

### 几何

- Builder preliminary：`review`, `reason_codes: []`
- Temp checker deterministic：`review`, `reason_codes: []`
- Temp checker + 独立 rubric：`harmony_pass`, `reason_codes: []`, `9/10`
- Shared scale：`0.625`
- 实际 raster 外宽比：`1.0689655172413792`，即 `62 / 58`，位于 `[1.05,1.15]`
- 最大 feature-center error：`1.0 px`，等于允许上限
- Residual jitter：`0.0 px`
- Protected-eye occlusion：`0.0`
- Aperture box：`[28,58,90,98]`
- 实际 rendered alpha box：每帧 `[9,6,71,74]`
- 实际 frame boxes：前四帧及第七、八帧 `[34,29,96,97]`；第五、六帧 `[36,29,98,97]`
- Depth：每帧 `40`，允许 `[1,99]`，expected `40`

### 正式 pixel / outline / component contract

- Formal contract：logical canvas `64×64`；appearance scale `2`；icon scale `4`；`nearest`
- Appearance：`128×128`，精确 2× grid round-trip：`true`
- Icon：`256×256`，精确 4× grid round-trip：`true`
- Direct icon reuse：icon 等于 appearance 的精确 nearest 2×：`true`
- Appearance/Icon opaque palette：各 `18` 色，允许上限 `18`
- Alpha values：两图均仅 `{0,255}`
- Transparent RGB cleared：两图均 `true`
- Frozen outline palette：`[[8,5,3],[9,0,0],[21,13,6],[29,27,24],[34,34,31]]`
- Source opaque components：`1`，允许最大 `1`
- Source outline boundary：`563 / 563 = 1.0`
- Rendered opaque components：八帧全部 `1`
- Rendered outline boundary：八帧全部 `329 / 329 = 1.0`
- `source_integrity.changed_keys: []`
- Atlas expected/actual SHA-256 均为 `fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d`

### 独立视觉 rubric

| Dimension | Score | 证据摘要 |
| --- | ---: | --- |
| Identity | 2 | 八帧中眼、眉、鼻、胡须与 Niko 轮廓保持可辨，眼区 occlusion 为零 |
| Function | 2 | 分段冠壳、眉板、开放面孔、下颚边与侧烟模块共同读成防护头盔 |
| Material | 2 | 暖暗轮廓、阶梯金属块面和克制高光与 Niko 的像素处理一致 |
| Hierarchy | 2 | 深色壳体围住更亮的脸，人物身份仍为第一视觉层级 |
| Originality | 1 | 青绿色烟模块与开槽眉板有差异化，但基础仍是熟悉的开放式战术头盔 |

Rubric SHA-256：`1aabf9cfd42c4df0ff0d96dff592a7fd5a6aa97d6e78e18af83a470a6152a1eb`。

关键输出：

- Final report：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-002/temp-checker-qa/harmony-report.json`
- Deterministic report：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-002/temp-checker-deterministic/harmony-report.json`
- Overlay：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-002/temp-checker-qa/harmony-overlay.png`
- Actual size：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-002/temp-checker-qa/harmony-actual-size.png`
- Approval card：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/candidate-002/qa/approval-card.png`
- Independent rubric input：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/rubric-input/candidate-002-reviewed.json`

## 3. Synthetic back：非 head 路由可审计

该 fixture 刻意使用非 canonical、schema-less rig，专门测试 slot 路由；它不是生产素材，因此 `pixel_contract` 为 `null`。

- Back feature anchor：`attachment_regions.back`
- Back protected region：`protected_regions.face`
- Back ratio band：`[0.6,1.2]`
- Back protected-face occlusion limit：`0.25`
- Back depth band：`[-99,-1]`；expected / actual：`-10`
- 实际 ratio：八帧均 `1.0`
- Feature-center error：`0.0 px`
- Residual jitter：`0.0 px`
- Protected-face occlusion：`0.0`
- Aperture box：`null`
- Frame boxes：前四帧及第七、八帧 `[38,76,86,109]`；第五、六帧 `[40,76,88,109]`

为使路由可证伪，fixture 将 `protected_regions.eyes` 刻意设为 item bbox。若错误套用 eye 规则，理论 occlusion 会是 `817 / 1584 = 0.5157828282828283`；实际报告是 protected-face `0.0`。同理，若错误套用 head ratio，结果会是 `48 / 58 = 0.8275862068965517`，低于 head band；实际 back ratio `1.0` 正常通过。`aperture_box: null` 且没有 `missing_feature_aperture`，进一步确认未执行 head aperture 规则。

视觉检查后给测试矩形 `3/10`（Identity 2、Function 0、Material 0、Hierarchy 1、Originality 0），因此最终正确保持 `review`，reason 为 `visual_rubric_review`。

关键输出：

- Deterministic report：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/synthetic-back/qa-deterministic/harmony-report.json`
- Rubric report：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/synthetic-back/qa/harmony-report.json`
- Overlay：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/synthetic-back/qa/harmony-overlay.png`
- Actual size：`E:/01_gobro/.codex-temp/harmony-behavioral-a0bc44b-20260824-001/synthetic-back/qa/harmony-actual-size.png`

## 复现命令

Python：`C:/Users/18421/.codex/skills/sprite-gen/.venv/Scripts/python.exe`

```powershell
$python = 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe'
$checker = 'E:\01_gobro\.codex-temp\checking-gogobro-item-harmony-a0bc44b-root\scripts\check_item_harmony.py'
$repo = 'E:\01_gobro\potato-brothers-godot4\.worktrees\gogobro-static-assets'
$out = 'E:\01_gobro\.codex-temp\harmony-behavioral-a0bc44b-20260824-001'
$atlas = "$repo\game\content\packs\characters\niko\animations\walk_down\sprite-sheet-alpha.png"
$rig = "$repo\tools\assets\rig_profiles\niko_walk_down_v1.json"
$appearance = 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-001\cleaned\smoke-shell-helmet-appearance-128.png'

& $python "$out\prepare_fixtures.py"

& $python $checker --character-atlas $atlas --appearance $appearance `
  --icon 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-001\icon\run\frames\icon\frame-0.png' `
  --anchors "$out\candidate-001\normalized-legacy-anchors.json" `
  --rig-profile $rig --slot head --out-dir "$out\candidate-001\qa"

Push-Location $repo
& $python 'tools\assets\build_smoke_shell_helmet_candidate_002.py' `
  --appearance-source $appearance --niko-atlas $atlas --rig-profile $rig `
  --registry 'game\content\assets\gogobro_static_assets_v1.json' `
  --output-root "$out\candidate-002"
& $python 'tools\assets\build_smoke_shell_helmet_candidate_002.py' `
  --appearance-source $appearance --niko-atlas $atlas --rig-profile $rig `
  --registry 'game\content\assets\gogobro_static_assets_v1.json' `
  --visual-rubric "$out\rubric-input\candidate-002-reviewed.json" `
  --output-root "$out\candidate-002"
Pop-Location

& $python $checker --character-atlas $atlas `
  --appearance "$out\candidate-002\derived\appearance-128.png" `
  --icon "$out\candidate-002\derived\icon-256.png" `
  --anchors "$out\candidate-002\appearance\anchors-walk-down.json" `
  --rig-profile $rig --slot head `
  --visual-rubric "$out\rubric-input\candidate-002-reviewed.json" `
  --out-dir "$out\candidate-002\temp-checker-qa"

& $python $checker --character-atlas $atlas `
  --appearance "$out\synthetic-back\appearance.png" `
  --icon "$out\synthetic-back\icon.png" `
  --anchors "$out\synthetic-back\anchors.json" `
  --rig-profile "$out\synthetic-back\rig.json" --slot back `
  --visual-rubric "$out\rubric-input\synthetic-back-reviewed.json" `
  --out-dir "$out\synthetic-back\qa"
```

所有 evaluator 自身的写入均限制在上述 fresh temp 根。未写外部 `candidate-001/002`、个人 skill 或审批状态；运行过程中观察到共享 worktree 的 registry 被根任务并发刷新，本 evaluator 未参与、未回滚该修改。
~~~
<!-- END VERBATIM final-a0bc44b -->
