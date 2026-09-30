#!/usr/bin/env python3
"""Regenerate the Chinese-to-English translation table.

Usage:
    python3 scripts/english/build-translations.py [--cedict path/to/cedict_ts.u8] [--ecdict path/to/ecdict.csv]

Each headword takes its translations from the first of these layers that has it:
1. packages/english-engine/Data/zh-en-supplement.tsv, hand-written developer terms.
2. CC-CEDICT, with "(computing)" glosses ahead of general ones. Without --cedict, the
   latest release is downloaded from MDBG.
3. ECDICT's [计] (computing) senses, reversed, for headwords CC-CEDICT lacks. Without
   --ecdict, ecdict.csv is downloaded from the pinned commit.

Output lines are `simplified<TAB>gloss1[<TAB>gloss2]`, sorted by headword. The table is
derived from CC-CEDICT and is licensed CC-BY-SA 4.0; see packages/english-engine/DATA_LICENSE.md.
No GPL-licensed data (such as the rime-ice tables) may be read here.
"""

import argparse
import gzip
import math
import re
import sys
import urllib.request
from pathlib import Path

from ecdict_source import ecdict_rows

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
MAX_GLOSSES = 2
MAX_GLOSS_WORDS = 3
# ECDICT fills use only English whose every word is this common in wordfreq.
FILL_MAX_RANK = 50_000

REPO_ROOT = Path(__file__).resolve().parents[2]
ENGLISH_ENGINE = REPO_ROOT / "packages/english-engine"
RESOURCES = ENGLISH_ENGINE / "Sources/EnglishEngine/Resources"
DEFAULT_OUTPUT = RESOURCES / "zh-en.tsv"
DEFAULT_SUPPLEMENT = ENGLISH_ENGINE / "Data/zh-en-supplement.tsv"

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
# "(computing) kernel", "(computer networking) ...", "(software) ...", "(Internet) ..."; not "(Internet slang)".
COMPUTING_MARKER = re.compile(r"^\((?:(?:computing|computer|software)[^)]*|Internet)\)")

ECDICT_ENGLISH = re.compile(r"[a-z]+(?: [a-z]+){0,%d}" % (MAX_GLOSS_WORDS - 1))
ECDICT_NOTES = re.compile(r"（[^）]*）|\([^)]*\)|\[[^\]]*\]|<[^>]*>|【[^】]*】")
ECDICT_COMPUTING_SENSES = 2
# 有效的, 完成了: a grammatical ending, not a term.
PARTICLE_ENDING = re.compile(r"[的了着过地得]$")


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


def build_cedict_table(lines) -> tuple[dict[str, list[str]], str]:
    release = "unknown"
    # headword -> (common-noun glosses, proper-noun glosses), each gloss with whether it is a computing sense
    glosses: dict[str, tuple[list[tuple[str, bool]], list[tuple[str, bool]]]] = {}
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
        for sense in raw_glosses.split("/"):
            computing = bool(COMPUTING_MARKER.match(sense.strip()))
            for raw in sense.split("; "):
                gloss = clean_gloss(raw)
                if gloss:
                    target.append((gloss, computing))

    table: dict[str, list[str]] = {}
    for simplified, (common, proper) in glosses.items():
        # A gloss listed both plainly and as a computing sense ("process") counts as a computing sense.
        unique: dict[str, tuple[str, bool]] = {}
        for gloss, computing in common + proper:
            first = unique.get(gloss.lower())
            unique[gloss.lower()] = (first[0], first[1] or computing) if first else (gloss, computing)
        ordered = [g for g, computing in unique.values() if computing] + [
            g for g, computing in unique.values() if not computing
        ]
        if ordered:
            table[simplified] = ordered[:MAX_GLOSSES]
    return table, release


def ecdict_senses(text: str) -> list[str]:
    text = ECDICT_NOTES.sub("", text)
    return [s.strip(" .…") for s in re.split(r"[；;，,、]", text) if s.strip(" .…")]


def build_ecdict_table(rows, ranks: dict[str, int]) -> dict[str, list[str]]:
    """Headword -> [English] from the leading senses of ECDICT's [计] lines, reversed."""
    best: dict[str, tuple[str, float]] = {}
    for row in rows:
        word = row["word"].strip()
        if not ECDICT_ENGLISH.fullmatch(word) or not row["translation"]:
            continue
        # Inflections ("processes") repeat their lemma's senses.
        if any(part.startswith("0:") for part in row["exchange"].split("/")):
            continue
        parts = word.split()
        if any(ranks.get(part, FILL_MAX_RANK) >= FILL_MAX_RANK for part in parts):
            continue
        # Geometric mean of the words' frequency weights, less for each extra word.
        weight = math.prod(1 / math.log2(ranks[part] + 2) for part in parts) ** (1 / len(parts))
        weight *= 0.7 ** (len(parts) - 1)
        for line in row["translation"].replace("\\n", "\n").split("\n"):
            line = line.strip()
            if not line.startswith("[计]"):
                continue
            for index, sense in enumerate(ecdict_senses(line[3:])[:ECDICT_COMPUTING_SENSES]):
                if not HEADWORD_PATTERN.fullmatch(sense) or PARTICLE_ENDING.search(sense):
                    continue
                score = weight / (1 + 0.5 * index)
                if score > best.get(sense, ("", 0.0))[1]:
                    best[sense] = (word, score)
    return {headword: [word] for headword, (word, _) in best.items()}


def read_supplement(path: Path) -> dict[str, list[str]]:
    table: dict[str, list[str]] = {}
    errors = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        headword, *translations = line.split("\t")
        where = f"{path.name}:{number}: {headword}"
        if not HEADWORD_PATTERN.fullmatch(headword):
            errors.append(f"{where}: headword must be two or more Han characters")
        elif headword in table:
            errors.append(f"{where}: duplicate headword")
        if not translations or any(not t or t != t.strip() for t in translations):
            errors.append(f"{where}: empty field or surrounding spaces")
        elif len(translations) > MAX_GLOSSES:
            errors.append(f"{where}: more than {MAX_GLOSSES} translations")
        table.setdefault(headword, translations)
    if errors:
        sys.exit("error: invalid supplement\n" + "\n".join(errors))
    return table


def read_cedict(path: Path | None) -> list[str]:
    if path is not None:
        return path.read_text(encoding="utf-8").splitlines()
    print(f"downloading {CEDICT_URL}", file=sys.stderr)
    with urllib.request.urlopen(CEDICT_URL) as response:
        return gzip.decompress(response.read()).decode("utf-8").splitlines()


def main() -> int:
    parser = argparse.ArgumentParser(description="Regenerate the Chinese-to-English translation table.")
    parser.add_argument("--cedict", type=Path)
    parser.add_argument("--ecdict", type=Path)
    parser.add_argument("--supplement", type=Path, default=DEFAULT_SUPPLEMENT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    supplement = read_supplement(args.supplement)
    cedict, release = build_cedict_table(read_cedict(args.cedict))
    words = (RESOURCES / "wordlist.txt").read_text(encoding="utf-8").split()
    ecdict = build_ecdict_table(ecdict_rows(args.ecdict), {w: i for i, w in enumerate(words)})

    table = {**ecdict, **cedict, **supplement}
    with args.output.open("w", encoding="utf-8") as output:
        for simplified in sorted(table):
            output.write("\t".join([simplified, *table[simplified]]) + "\n")

    from_cedict = len(cedict.keys() - supplement.keys())
    from_ecdict = len(ecdict.keys() - cedict.keys() - supplement.keys())
    print(
        f"wrote {len(table)} entries to {args.output}: {len(supplement)} from the supplement, "
        f"{from_cedict} from CC-CEDICT {release}, {from_ecdict} from ECDICT"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
