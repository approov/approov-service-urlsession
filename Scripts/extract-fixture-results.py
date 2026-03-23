#!/usr/bin/env python3

import json
import sys
from pathlib import Path


OUTPUT_PREFIX = "APPROOV_FIXTURE_RESULT "


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: extract-fixture-results.py <test-log-path> <output.json>", file=sys.stderr)
        return 1

    log_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    fixtures = []
    with log_path.open() as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith(OUTPUT_PREFIX):
                continue
            fixtures.append(json.loads(line[len(OUTPUT_PREFIX):]))

    fixtures.sort(key=lambda item: (item["suite"], item["fixture"]))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps({"fixtures": fixtures}, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
