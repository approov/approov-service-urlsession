#!/usr/bin/env python3

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: write-junit-report.py <fixture-report.json> <output.xml>", file=sys.stderr)
        return 1

    fixture_report_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    with fixture_report_path.open() as handle:
        report = json.load(handle)

    fixtures = report.get("fixtures", [])
    suites_by_name: dict[str, list[dict]] = {}
    for fixture in fixtures:
        suites_by_name.setdefault(fixture["suite"], []).append(fixture)

    testsuites = ET.Element(
        "testsuites",
        attrib={
            "tests": str(len(fixtures)),
            "failures": str(sum(1 for fixture in fixtures if fixture["status"] != "passed")),
            "errors": "0",
        },
    )

    for suite_name, suite_fixtures in sorted(suites_by_name.items()):
        testsuite = ET.SubElement(
            testsuites,
            "testsuite",
            attrib={
                "name": suite_name,
                "tests": str(len(suite_fixtures)),
                "failures": str(sum(1 for fixture in suite_fixtures if fixture["status"] != "passed")),
                "errors": "0",
                "time": f"{sum(fixture['durationSeconds'] for fixture in suite_fixtures):.6f}",
            },
        )

        for fixture in sorted(suite_fixtures, key=lambda item: item["fixture"]):
            testcase = ET.SubElement(
                testsuite,
                "testcase",
                attrib={
                    "classname": fixture["harness"],
                    "name": fixture["fixture"],
                    "time": f"{fixture['durationSeconds']:.6f}",
                },
            )
            if fixture["status"] != "passed":
                failure = ET.SubElement(
                    testcase,
                    "failure",
                    attrib={"message": fixture["failures"][0] if fixture["failures"] else "Fixture failed"},
                )
                failure.text = "\n".join(fixture["failures"])

    ET.indent(testsuites, space="  ")
    tree = ET.ElementTree(testsuites)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(output_path, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
