#!/usr/bin/env python3
"""Regenerate the English-to-Chinese gloss table shown next to English candidates.

Usage:
    python3 scripts/english/build-glosses.py [--ecdict path/to/ecdict.csv]

Without --ecdict, ecdict.csv is downloaded from a pinned ECDICT commit and
verified by SHA-256. Output lines are `key<TAB>gloss` for every key in
wordlist.txt and supplement.txt. Supplement glosses (second column of
supplement.txt) are hand-written and take precedence. ECDICT is MIT licensed;
see packages/english-engine/DATA_LICENSE.md.
"""

import argparse
import csv
import hashlib
import re
import sys
import urllib.request
from pathlib import Path

ECDICT_COMMIT = "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
ECDICT_URL = f"https://raw.githubusercontent.com/skywind3000/ECDICT/{ECDICT_COMMIT}/ecdict.csv"
ECDICT_SHA256 = "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf"
MAX_SENSES = 2
SHORT_SENSE_LENGTH = 6
# Everyone knows "the" or "good", and ECDICT orders their senses poorly; gloss only less common words.
SKIP_MOST_COMMON = 2000

REPO_ROOT = Path(__file__).resolve().parents[2]
RESOURCES = REPO_ROOT / "packages/english-engine/Sources/EnglishEngine/Resources"

POS_LINE = re.compile(r"^([a-z]+)\.\s*(.*)$")
# Function-word roles win whenever a word has them (he: pron. 他, not n. 男孩).
FUNCTION_POS = ("pron", "prep", "conj", "aux", "art")
NOTES = re.compile(r"（[^）]*）|\([^)]*\)|\[[^\]]*\]|<[^>]*>|【[^】]*】")


def key(text: str) -> str:
    return re.sub(r"[^a-z]", "", text.lower())


def senses(text: str) -> list[str]:
    text = NOTES.sub("", text)
    return [s.strip(" .…") for s in re.split(r"[；;，,]", text) if s.strip(" .…")]


def gloss(translation: str) -> str | None:
    """Gloss from the part-of-speech lines (or [计] lines); None for bare inflection notes."""
    lines = [line.strip() for line in translation.replace("\\n", "\n").split("\n") if line.strip()]
    candidates = []
    for line in lines:
        match = POS_LINE.match(line)
        if match and senses(match.group(2)):
            candidates.append((match.group(1), senses(match.group(2))))
    if not candidates:
        # Computing senses are the only useful tagged lines ("download": [计] 下载).
        computing = [senses(line[3:]) for line in lines if line.startswith("[计]")]
        candidates = [("", c) for c in computing if c]
    if not candidates:
        return None
    function_roles = [c for c in candidates if c[0] in FUNCTION_POS]
    # Otherwise the part of speech with the most senses tracks the common usage (good: a. over n.).
    best = function_roles[0][1] if function_roles else max((c[1] for c in candidates), key=len)
    short = [s for s in best if len(s) <= SHORT_SENSE_LENGTH]
    chosen = (short or best)[:MAX_SENSES]
    return "，".join(dict.fromkeys(chosen))


def read_ecdict(path: Path | None) -> str:
    if path is not None:
        data = path.read_bytes()
    else:
        print(f"downloading ECDICT {ECDICT_COMMIT[:10]}", file=sys.stderr)
        with urllib.request.urlopen(ECDICT_URL) as response:
            data = response.read()
    if hashlib.sha256(data).hexdigest() != ECDICT_SHA256:
        sys.exit("error: ecdict.csv does not match the pinned SHA-256")
    return data.decode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Regenerate en-zh.tsv from ECDICT and the supplement.")
    parser.add_argument("--ecdict", type=Path)
    parser.add_argument("--output", type=Path, default=RESOURCES / "en-zh.tsv")
    args = parser.parse_args()

    words = (RESOURCES / "wordlist.txt").read_text(encoding="utf-8").split()
    supplement = {}
    # Word-like supplement terms whose inflections should share the gloss; acronyms are excluded
    # because "AI" + "d" would turn "aid" into 人工智能.
    inflectable = set()
    for line in (RESOURCES / "supplement.txt").read_text(encoding="utf-8").splitlines():
        display, _, supplement_gloss = line.partition("\t")
        if display and supplement_gloss:
            supplement[key(display)] = supplement_gloss.strip()
            if not display.isupper() and len(key(display)) >= 3:
                inflectable.add(key(display))
    wanted = {key(w) for w in words[SKIP_MOST_COMMON:]} | set(supplement)

    csv.field_size_limit(10**8)
    # Only the exact lowercase entry counts: "gets" must not pick up the acronym "GETS".
    rows: dict[str, dict] = {}
    for row in csv.DictReader(read_ecdict(args.ecdict).splitlines()):
        if row["word"] in wanted and row["translation"]:
            rows[row["word"]] = row

    glosses: dict[str, str] = {}
    for k, row in rows.items():
        g = gloss(row["translation"])
        if g:
            glosses[k] = g
    # Inflections borrow their lemma's gloss (exchange "0:lemma"): always from the supplement
    # ("deploying" -> 部署), otherwise only when they have none of their own ("gave" note only).
    for k, row in rows.items():
        lemma = key(next((part[2:] for part in row["exchange"].split("/") if part.startswith("0:")), ""))
        if lemma in inflectable:
            glosses[k] = supplement[lemma]
        elif k not in glosses and lemma in glosses:
            glosses[k] = glosses[lemma]
    # Regular inflections of supplement terms keep the workplace gloss even when ECDICT has an
    # unrelated entry for the inflected form ("emails" is listed as a name).
    for k in list(glosses):
        for suffix in ("s", "es", "ed", "d", "ing"):
            if k.endswith(suffix) and k[: -len(suffix)] in inflectable:
                glosses[k] = supplement[k[: -len(suffix)]]
                break
    glosses.update(supplement)

    with args.output.open("w", encoding="utf-8") as output:
        for k in sorted(glosses):
            output.write(f"{k}\t{glosses[k]}\n")
    print(f"wrote {len(glosses)} glosses ({len(supplement)} hand-written) to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
