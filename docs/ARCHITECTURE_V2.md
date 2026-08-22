# GOGOBRO v2 architecture

## Clean-room boundary

外部恢复工程只用于观察公开可见的职责与行为，保持在仓库外并只读。GOGOBRO 不导入其代码、字符串、资源、ID 或数据表。

## Ownership

- `AppKernel` owns boot services and the current session.
- `SceneFlow` owns route changes and the current flow scene.
- `GameSession` owns the run RNG, immutable content snapshot and mutable run state.
- `ContentPackCatalog` owns installed/enabled pack state; `ContentSnapshot` is immutable once sealed.
- `CombatWorld` owns active actors, waves and projectile/effect hosts.
- UI owns no gameplay state.

## Deterministic stat order

```text
base definition
→ character modifiers
→ weapon/item/tag modifiers
→ temporary modifiers
→ difficulty/wave modifiers
→ final clamps
```

## Safe reload boundary

Content packs, workshop state and Mod profiles may change only while the main-menu route is active and no `GameSession` exists. The next run receives the newly built snapshot; live entities never observe a registry mutation.
