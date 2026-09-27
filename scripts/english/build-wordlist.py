#!/usr/bin/env python3
"""Regenerate the English completion lexicon from wordfreq.

Usage:
    python3 -m venv /tmp/wordfreq-venv
    /tmp/wordfreq-venv/bin/pip install wordfreq==3.1.1
    /tmp/wordfreq-venv/bin/python scripts/english/build-wordlist.py

Output is one lowercase word per line, most frequent first. The engine uses
line order as the frequency rank. The generated list is derived from wordfreq
data and is licensed CC-BY-SA 4.0; see packages/english-engine/DATA_LICENSE.md.
"""

import argparse
import importlib.metadata
import re
import sys
from pathlib import Path

import wordfreq

EXPECTED_WORDFREQ_VERSION = "3.1.1"
DEFAULT_SIZE = 30000
SCAN_SIZE = 80000

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = (
    REPO_ROOT / "packages/english-engine/Sources/EnglishEngine/Resources/wordlist.txt"
)

WORD_PATTERN = re.compile(r"[a-z]+")
SINGLE_LETTER_WORDS = {"a", "i"}

# Profanity, slurs, and explicit slang that should never be offered as a
# completion. Users can still type these words literally.
EXCLUDED_WORDS = {
    "asshole", "assholes", "bitch", "bitches", "bitchy", "blowjob", "boobs",
    "bullshit", "cock", "cocks", "cum", "cunt", "cunts", "dick", "dicks",
    "dildo", "dyke", "fag", "faggot", "faggots", "fags", "fuck", "fucked",
    "fucker", "fuckers", "fuckin", "fucking", "fucks", "hentai", "milf",
    "motherfucker", "motherfuckers", "motherfucking", "nigga", "niggas",
    "nigger", "niggers", "porn", "porno", "pussy", "retard", "retarded",
    "retards", "shit", "shits", "shitty", "slut", "sluts", "tits", "tranny",
    "twat", "whore", "whores", "xxx",
}


def build_wordlist(size: int) -> list[str]:
    words: list[str] = []
    for word in wordfreq.top_n_list("en", SCAN_SIZE):
        if not WORD_PATTERN.fullmatch(word):
            continue
        if len(word) == 1 and word not in SINGLE_LETTER_WORDS:
            continue
        if word in EXCLUDED_WORDS:
            continue
        words.append(word)
        if len(words) == size:
            break
    return words


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Regenerate the English completion lexicon from wordfreq."
    )
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    installed_version = importlib.metadata.version("wordfreq")
    if installed_version != EXPECTED_WORDFREQ_VERSION:
        print(
            f"warning: expected wordfreq {EXPECTED_WORDFREQ_VERSION}, "
            f"found {installed_version}; output may differ",
            file=sys.stderr,
        )

    words = build_wordlist(args.size)
    if len(words) < args.size:
        print(f"error: only {len(words)} words available", file=sys.stderr)
        return 1

    args.output.write_text("\n".join(words) + "\n", encoding="utf-8")
    print(f"wrote {len(words)} words to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
