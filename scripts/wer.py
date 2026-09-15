#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def words(path: str) -> list[str]:
    return re.findall(r"\w+", Path(path).read_text(encoding="utf-8").casefold())


def distance(reference: list[str], hypothesis: list[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for row, expected in enumerate(reference, 1):
        current = [row]
        for column, actual in enumerate(hypothesis, 1):
            current.append(
                min(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + (expected != actual),
                )
            )
        previous = current
    return previous[-1]


if len(sys.argv) != 3:
    raise SystemExit(f"Usage: {sys.argv[0]} REFERENCE.txt HYPOTHESIS.txt")

reference = words(sys.argv[1])
hypothesis = words(sys.argv[2])
errors = distance(reference, hypothesis)
print(f"Reference words:  {len(reference)}")
print(f"Hypothesis words: {len(hypothesis)}")
print(f"Word errors:      {errors}")
print(f"WER:              {errors / len(reference):.2%}")
