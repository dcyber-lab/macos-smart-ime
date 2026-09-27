#!/usr/bin/env python3
"""Regenerate the Chinese-to-English translation table from CC-CEDICT.

Usage:
    python3 scripts/english/build-translations.py [--cedict path/to/cedict_ts.u8]

Without --cedict, the latest CC-CEDICT release is downloaded from MDBG.
Output lines are `simplified<TAB>gloss1[<TAB>gloss2]`, sorted by headword. The
table is derived from CC-CEDICT and is licensed CC-BY-SA 4.0; see
packages/english-engine/DATA_LICENSE.md.
"""

import argparse
import gzip
import re
import sys
import urllib.request
from pathlib import Path

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
MAX_GLOSSES = 2
MAX_GLOSS_WORDS = 3

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = (
    REPO_ROOT / "packages/english-engine/Sources/EnglishEngine/Resources/zh-en.tsv"
)

ENTRY_PATTERN = re.compile(r"(\S+) (\S+) \[(.*?)\] /(.*)/")
HEADWORD_PATTERN = re.compile(r"[一-鿿]{2,}")
GLOSS_PATTERN = re.compile(r"[A-Za-z][A-Za-z '\-]*")
PARENTHETICAL_PATTERN = re.compile(r"\([^()]*\)")
LEADING_WORD_PATTERN = re.compile(r"^(to|a|an|the) ", re.IGNORECASE)
# Cross-references, classifiers, and placeholders that are not usable as a translation.
REJECTED_GLOSS_PATTERN = re.compile(
    r"\b(CL|variant of|surname|abbr|see|used in|pr|also written|lit|fig|sb|sth|onom|interj|erhua)\b",
    re.IGNORECASE,
)


def clean_gloss(raw: str) -> str | None:
    gloss = PARENTHETICAL_PATTERN.sub("", raw)
    gloss = gloss.split(",")[0]
    gloss = " ".join(gloss.split())
    gloss = LEADING_WORD_PATTERN.sub("", gloss).strip(" .")
    if not gloss or REJECTED_GLOSS_PATTERN.search(raw):
        return None
    if not GLOSS_PATTERN.fullmatch(gloss) or len(gloss.split()) > MAX_GLOSS_WORDS:
        return None
    return gloss


def build_table(lines) -> tuple[dict[str, list[str]], str]:
    release = "unknown"
    # headword -> (common-noun glosses, proper-noun glosses)
    glosses: dict[str, tuple[list[str], list[str]]] = {}
    for line in lines:
        if line.startswith("#! date="):
            release = line.split("=", 1)[1].strip()
        if line.startswith("#"):
            continue
        match = ENTRY_PATTERN.match(line)
        if not match:
            continue
        simplified, pinyin, raw_glosses = match.group(2), match.group(3), match.group(4)
        if not HEADWORD_PATTERN.fullmatch(simplified):
            continue

        common, proper = glosses.setdefault(simplified, ([], []))
        target = proper if pinyin[:1].isupper() else common
        for raw in re.split(r"/|; ", raw_glosses):
            gloss = clean_gloss(raw)
            if gloss:
                target.append(gloss)

    table: dict[str, list[str]] = {}
    for simplified, (common, proper) in glosses.items():
        unique: list[str] = []
        for gloss in common + proper:
            if gloss.lower() not in (existing.lower() for existing in unique):
                unique.append(gloss)
        if unique:
            table[simplified] = unique[:MAX_GLOSSES]
    return table, release


def read_cedict(path: Path | None) -> list[str]:
    if path is not None:
        return path.read_text(encoding="utf-8").splitlines()
    print(f"downloading {CEDICT_URL}", file=sys.stderr)
    with urllib.request.urlopen(CEDICT_URL) as response:
        return gzip.decompress(response.read()).decode("utf-8").splitlines()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Regenerate the Chinese-to-English translation table from CC-CEDICT."
    )
    parser.add_argument("--cedict", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    table, release = build_table(read_cedict(args.cedict))
    with args.output.open("w", encoding="utf-8") as output:
        for simplified in sorted(table):
            output.write("\t".join([simplified, *table[simplified]]) + "\n")

    print(f"wrote {len(table)} entries from CC-CEDICT {release} to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
