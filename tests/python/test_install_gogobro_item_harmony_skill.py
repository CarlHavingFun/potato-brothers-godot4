from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).parents[2]
INSTALLER = REPO_ROOT / "tools" / "install_gogobro_item_harmony_skill.ps1"
SKILL_SOURCE = REPO_ROOT / "tools" / "codex_skills" / "checking-gogobro-item-harmony"
MANIFEST = (
    Path("SKILL.md"),
    Path("agents/openai.yaml"),
    Path("references/slot-profiles.md"),
    Path("scripts/check_item_harmony.py"),
)


def manifest_hashes(root: Path) -> dict[str, str]:
    return {
        path.as_posix(): hashlib.sha256((root / path).read_bytes()).hexdigest()
        for path in MANIFEST
    }


def run_installer(
    source: Path, target: Path, *, resolve_arguments: bool = True
) -> subprocess.CompletedProcess[str]:
    powershell = shutil.which("pwsh") or shutil.which("powershell")
    assert powershell is not None
    source_argument = source.resolve() if resolve_arguments else source
    target_argument = target.resolve() if resolve_arguments else target
    return subprocess.run(
        [
            powershell,
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(INSTALLER.resolve()),
            "-SourceRoot",
            str(source_argument),
            "-TargetRoot",
            str(target_argument),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_installer_copies_only_manifest_files_and_preserves_hashes(tmp_path: Path) -> None:
    target = tmp_path / "checking-gogobro-item-harmony"
    sentinel = target / "unrelated" / "sentinel.txt"
    sentinel.parent.mkdir(parents=True)
    sentinel.write_text("preserve me", encoding="utf-8")
    result = run_installer(source=SKILL_SOURCE, target=target)
    assert result.returncode == 0, result.stdout + result.stderr
    assert manifest_hashes(SKILL_SOURCE) == manifest_hashes(target)
    assert sentinel.read_text(encoding="utf-8") == "preserve me"
    assert {
        path.relative_to(target).as_posix() for path in target.rglob("*") if path.is_file()
    } == {path.as_posix() for path in MANIFEST} | {"unrelated/sentinel.txt"}
    assert not any(path.name == "__pycache__" for path in tmp_path.rglob("*"))


def test_installer_prints_each_manifest_path_and_verified_sha256(tmp_path: Path) -> None:
    target = tmp_path / "checking-gogobro-item-harmony"
    result = run_installer(source=SKILL_SOURCE, target=target)

    assert result.returncode == 0, result.stdout + result.stderr
    output_lines = {line.strip() for line in result.stdout.splitlines()}
    expected_lines = {
        f"Verified {relative_path} SHA-256={sha256}"
        for relative_path, sha256 in manifest_hashes(SKILL_SOURCE).items()
    }
    assert expected_lines <= output_lines


def test_installer_rejects_identical_resolved_roots() -> None:
    aliased_target = SKILL_SOURCE / "agents" / ".."
    result = run_installer(
        source=SKILL_SOURCE,
        target=aliased_target,
        resolve_arguments=False,
    )
    assert result.returncode != 0
    assert "SourceRoot and TargetRoot must differ" in result.stdout + result.stderr
    assert str(aliased_target) in result.args
