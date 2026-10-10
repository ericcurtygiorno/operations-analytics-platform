from __future__ import annotations

import re
import unittest
from pathlib import Path
from urllib.parse import unquote

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


class DocumentationTests(unittest.TestCase):
    def test_local_markdown_links_resolve(self) -> None:
        markdown_files = [REPOSITORY_ROOT / "README.md"]
        markdown_files.extend(sorted((REPOSITORY_ROOT / "docs").rglob("*.md")))
        markdown_files.append(REPOSITORY_ROOT / "dashboard" / "README.md")

        broken_links: list[str] = []
        for markdown_file in markdown_files:
            for target in MARKDOWN_LINK.findall(markdown_file.read_text(encoding="utf-8")):
                clean_target = target.strip().split("#", maxsplit=1)[0]
                if not clean_target or clean_target.startswith(("http://", "https://", "mailto:")):
                    continue

                resolved = (markdown_file.parent / unquote(clean_target)).resolve()
                if not resolved.exists():
                    relative_file = markdown_file.relative_to(REPOSITORY_ROOT)
                    broken_links.append(f"{relative_file}: {target}")

        self.assertEqual([], broken_links, "Broken local Markdown links were found")


if __name__ == "__main__":
    unittest.main()
