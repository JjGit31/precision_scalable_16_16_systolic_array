#!/usr/bin/env python3
"""Basic sanity check for a generated VCD file (not a power-annotation check)."""
from __future__ import annotations
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <trace.vcd>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file() or path.stat().st_size == 0:
        print(f"FAIL: VCD missing or empty: {path}", file=sys.stderr)
        return 1

    header_done = False
    var_count = 0
    value_changes = 0
    timestamps = 0
    scalar_re = re.compile(r"^[01xXzZ][^\s]+$")
    vector_re = re.compile(r"^[bB][01xXzZ]+\s+\S+$")
    real_re = re.compile(r"^[rR][^\s]+\s+\S+$")

    try:
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            for raw in stream:
                line = raw.strip()
                if not header_done:
                    if line.startswith("$var "):
                        var_count += 1
                    if line.startswith("$enddefinitions"):
                        header_done = True
                    continue

                if line.startswith("#"):
                    timestamps += 1
                elif scalar_re.match(line) or vector_re.match(line) or real_re.match(line):
                    value_changes += 1
    except OSError as exc:
        print(f"FAIL: cannot read VCD: {exc}", file=sys.stderr)
        return 1

    if not header_done:
        print("FAIL: VCD header has no $enddefinitions.", file=sys.stderr)
        return 1
    if var_count == 0 or value_changes == 0 or timestamps == 0:
        print(
            f"FAIL: incomplete VCD (variables={var_count}, timestamps={timestamps}, "
            f"value_changes={value_changes}).",
            file=sys.stderr,
        )
        return 1

    print(
        f"VCD OK: {path} | {path.stat().st_size} bytes | "
        f"{var_count} variables | {timestamps} timestamps | {value_changes} value changes"
    )
    print("NOTE: this checks VCD structure/activity only; it does not prove functional correctness or Genus annotation coverage.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
