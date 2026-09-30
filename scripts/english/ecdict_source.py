"""The pinned ECDICT release shared by the English data scripts.

ECDICT (https://github.com/skywind3000/ECDICT) is MIT licensed; see
packages/english-engine/DATA_LICENSE.md.
"""

import csv
import hashlib
import sys
import urllib.request
from pathlib import Path

ECDICT_COMMIT = "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
ECDICT_URL = f"https://raw.githubusercontent.com/skywind3000/ECDICT/{ECDICT_COMMIT}/ecdict.csv"
ECDICT_SHA256 = "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf"


def read_ecdict(path: Path | None) -> str:
    """ecdict.csv from `path`, or downloaded from the pinned commit; verified by SHA-256 either way."""
    if path is not None:
        data = path.read_bytes()
    else:
        print(f"downloading ECDICT {ECDICT_COMMIT[:10]}", file=sys.stderr)
        with urllib.request.urlopen(ECDICT_URL) as response:
            data = response.read()
    if hashlib.sha256(data).hexdigest() != ECDICT_SHA256:
        sys.exit("error: ecdict.csv does not match the pinned SHA-256")
    return data.decode("utf-8")


def ecdict_rows(path: Path | None) -> csv.DictReader:
    csv.field_size_limit(10**8)
    return csv.DictReader(read_ecdict(path).splitlines())
