#!/usr/bin/env python3
"""引き継ぎ用のダイジェストを 2 本作る。

NORI_DOCS.md   — 文書だけ。「まず全体を理解させる」用。
NORI_SOURCE.md — 全ソース。「実際に手を入れさせる」用。
どちらも 1 ファイルなので、チャット AI にそのまま投げられる。
"""
import subprocess
import sys
from pathlib import Path

root, stage = Path(sys.argv[1]), Path(sys.argv[2])
files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True).stdout.split()

SKIP_EXT = {".png", ".ico", ".icns", ".jpg", ".xcstrings", ".resx"}
DOC_FILES = [
    "CLAUDE.md", "docs/HANDOFF.md", "docs/DESIGN.md", "docs/WINDOWS_DESIGN.md",
    "docs/REVIEW_LOG.md", "README.md", "windows/README.md",
    "docs/zenn/nori-clipboard-manager.md",
]

def lang(path):
    return {".swift": "swift", ".cs": "csharp", ".yml": "yaml", ".yaml": "yaml",
            ".sh": "bash", ".py": "python", ".json": "json", ".md": "markdown",
            ".csproj": "xml", ".sln": "text", ".plist": "xml",
            ".entitlements": "xml", ".slnx": "xml"}.get(path.suffix, "")

def emit(out, paths, title, intro):
    parts = [f"# {title}\n", intro, "\n---\n"]
    for rel in paths:
        p = root / rel
        if not p.is_file():
            continue
        try:
            body = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        parts.append(f"\n## `{rel}`\n\n```{lang(p)}\n{body.rstrip()}\n```\n")
    out.write_text("".join(parts), encoding="utf-8")
    return len(parts) - 3

docs_n = emit(
    stage / "NORI_DOCS.md",
    DOC_FILES,
    "Nori — 引き継ぎ文書一式",
    "\nこのファイルは Nori の文書だけを 1 つにまとめたもの。まずこれを読めば全体像がつかめる。\n"
    "ソースコードは同じ zip の `NORI_SOURCE.md`、または `repo/` 以下の実ファイルにある。\n"
    "リポジトリ: https://github.com/hocky0301/Nori\n",
)

src = [f for f in files
       if Path(f).suffix not in SKIP_EXT
       and not f.startswith("docs/screenshots/")
       and f not in DOC_FILES]
src.sort(key=lambda f: (not f.startswith("Nori/"), not f.startswith("windows/"), f))
src_n = emit(
    stage / "NORI_SOURCE.md",
    src,
    "Nori — 全ソースコード",
    "\nNori の全ソース（macOS/Swift と Windows/C#）を 1 ファイルにまとめたもの。\n"
    "文書は `NORI_DOCS.md`。翻訳ファイル（.xcstrings / .resx）と画像は分量の都合で省いてあるので、\n"
    "必要なら `repo/` 以下の実ファイルを見ること。\n"
    "リポジトリ: https://github.com/hocky0301/Nori\n",
)
print(f"  NORI_DOCS.md: {docs_n} files / NORI_SOURCE.md: {src_n} files")
