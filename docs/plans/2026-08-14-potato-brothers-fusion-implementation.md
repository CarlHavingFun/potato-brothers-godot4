# Potato Brothers Fusion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a tested, ten-wave Godot 4.7.1 game combining the local Godot tutorial and Unity/Tuanjie reproduction.

**Architecture:** Preserve the runnable Godot scene layer while replacing mutable global state with immutable content definitions, per-run state, and focused services. Migrate Unity content once into Godot resources and keep all runtime dependencies project-local.

**Tech Stack:** Godot 4.7.1, GDScript, GdUnit4 6.2.0, Godot MCP/CLI 0.8.2, GitHub Actions.

---

## Execution batches

1. Copy the tutorial project into an independent repository, remove generated caches, import it with Godot 4.7.1, and capture a clean baseline.
2. Install pinned GdUnit4 and Godot MCP addons. Add a headless test command and export exclusions.
3. Write failing tests for immutable stats, run state, inventory transactions, difficulty scaling, and save recovery; implement the corresponding core types and services.
4. Normalize the existing Godot resources, migrate the Unity-only character, items, enemies, boss media, and audio, and validate all content IDs and references.
5. Replace global runtime mutation in player, spawner, shop, rewards, and arena flow. Keep each vertical slice runnable.
6. Implement the ten wave definitions, five difficulty profiles, MouseDog boss, win/loss settlement, unlocks, local saves, settings, and translations.
7. Complete scene, flow, stress, export, and CI verification; publish the private repository and provide the phase-1 build for playtesting.

Every behavioral change follows red-green-refactor with GdUnit4. Commit after each green batch.
