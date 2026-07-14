#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="full"

case "${1:-}" in
  "") ;;
  --changed) MODE="changed" ;;
  *) echo "usage: $0 [--changed]" >&2; exit 2 ;;
esac

python3 - "$ROOT" "$MODE" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
mode = sys.argv[2]

external_roots = set()
for skill in root.glob("*/SKILL.md"):
    lines = skill.read_text(errors="replace").splitlines()
    if any(line.startswith("source:") for line in lines[:30]):
        external_roots.add(skill.parent.name)

def is_in_scope(path: Path) -> bool:
    try:
        relative = path.resolve().relative_to(root)
    except (OSError, ValueError):
        return False
    if path.suffix.lower() != ".md" or not path.is_file():
        return False
    if relative == Path("STYLE.md"):
        return False
    if relative.parts and relative.parts[0] in {
        ".git", ".claude", ".codex", ".agents", ".cursor", "_archive"
    }:
        return False
    if relative.parts and relative.parts[0] in external_roots:
        return False
    if len(relative.parts) >= 2 and relative.parts[:2] == ("docs", "superpowers"):
        return False
    if len(relative.parts) >= 2 and relative.parts[:2] == ("docs", "skills-reorg"):
        return False
    if len(relative.parts) >= 2 and relative.parts[:2] == ("journey-evals", "runs"):
        return False
    return True

def git_paths(*args: str) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        stdout=subprocess.PIPE,
    )
    return [root / raw.decode() for raw in result.stdout.split(b"\0") if raw]

if mode == "changed":
    candidates = {
        *git_paths("diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD", "--", "*.md"),
        *git_paths("ls-files", "--others", "--exclude-standard", "-z", "--", "*.md"),
    }
else:
    candidates = set(git_paths(
        "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.md"
    ))

files = sorted(path for path in candidates if is_in_scope(path))

denylist = (
    "質量", "信息", "軟件", "硬件", "網絡", "視頻", "服務器", "數據庫",
    "代碼", "調用", "缺省", "交互", "組件", "文檔", "屏幕",
    "內存", "變量", "函數", "接口", "循環", "支持", "打印",
)
emoji = re.compile(
    "[\U0001F300-\U0001FAFF\u2600-\u27BF\uFE0F]"
)
contrast = re.compile(r"(?:不是|並非).{0,80}而是")

violations = []
for path in files:
    relative = path.relative_to(root)
    for line_number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        match = emoji.search(line)
        if match:
            violations.append((relative, line_number, "emoji", match.group(0)))
        for token in denylist:
            if token in line:
                violations.append((relative, line_number, "taiwan-terms", token))
        match = contrast.search(line)
        if match:
            violations.append((relative, line_number, "contrast-template", match.group(0)))

for relative, line_number, rule, token in violations:
    print(f"{relative}:{line_number}: {rule}: {token}")

if violations:
    print(f"docs lint failed: {len(violations)} violation(s) in {len(files)} file(s)")
    raise SystemExit(1)

print(f"docs lint passed: {len(files)} file(s), mode={mode}")
PY
