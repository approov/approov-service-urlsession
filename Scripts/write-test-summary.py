#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from pathlib import Path


def run_xcresulttool(*args: str) -> dict:
    output = subprocess.check_output(
        ["xcrun", "xcresulttool", *args],
        text=True,
    )
    return json.loads(output)


def format_seconds(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes, remainder = divmod(seconds, 60)
    return f"{int(minutes)}m {remainder:.1f}s"


def flatten_test_cases(nodes: list[dict]) -> list[dict]:
    test_cases: list[dict] = []

    def visit(node: dict, ancestors: list[str]) -> None:
        node_type = node.get("nodeType")
        name = node.get("name", "")
        next_ancestors = ancestors + ([name] if name else [])
        if node_type == "Test Case":
            suite_name = ancestors[-1] if ancestors else ""
            test_cases.append(
                {
                    "suite": suite_name,
                    "name": name,
                    "result": node.get("result", "unknown"),
                    "duration": node.get("duration", ""),
                }
            )
        for child in node.get("children", []):
            visit(child, next_ancestors)

    for node in nodes:
        visit(node, [])
    return test_cases


def load_fixture_counts(repo_root: Path) -> tuple[int, list[tuple[str, int]]]:
    fixture_root_override = os.environ.get("APPROOV_SHARED_TESTS_PATH")
    if fixture_root_override:
        fixture_root = Path(fixture_root_override)
    else:
        fixture_root = repo_root / "Tests" / "ApproovURLSessionPackageTests" / "Fixtures"

    if not fixture_root.exists():
        return 0, []

    counts: list[tuple[str, int]] = []
    total = 0
    for fixture_file in sorted(fixture_root.glob("*.json")):
        with fixture_file.open() as handle:
            data = json.load(handle)
        case_count = len(data.get("cases", []))
        counts.append((fixture_file.name, case_count))
        total += case_count
    return total, counts


def load_fixture_report(report_path: Path | None) -> dict:
    if report_path is None or not report_path.exists():
        return {"fixtures": []}
    with report_path.open() as handle:
        return json.load(handle)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("Usage: write-test-summary.py <xcresult-path> [fixture-report.json]", file=sys.stderr)
        return 1

    xcresult_path = Path(sys.argv[1])
    fixture_report_path = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    if not xcresult_path.exists():
        print(f"xcresult bundle not found at {xcresult_path}", file=sys.stderr)
        return 1

    repo_root = Path(__file__).resolve().parents[1]
    summary = run_xcresulttool(
        "get",
        "test-results",
        "summary",
        "--path",
        str(xcresult_path),
        "--compact",
    )
    tests = run_xcresulttool(
        "get",
        "test-results",
        "tests",
        "--path",
        str(xcresult_path),
        "--compact",
    )

    duration = float(summary["finishTime"]) - float(summary["startTime"])
    total_fixture_cases, fixture_counts = load_fixture_counts(repo_root)
    fixture_report = load_fixture_report(fixture_report_path)
    fixture_entries = fixture_report.get("fixtures", [])
    fixture_passed = sum(1 for fixture in fixture_entries if fixture.get("status") == "passed")
    fixture_failed = sum(1 for fixture in fixture_entries if fixture.get("status") != "passed")
    test_cases = flatten_test_cases(tests.get("testNodes", []))
    failures = [case for case in test_cases if case["result"] != "Passed"]

    print("## Package Test Results")
    print()
    print("| Result | XCTest Cases | Fixture Cases | Passed | Failed | Skipped | Duration |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    print(
        f"| {summary['result']} | {summary['totalTestCount']} | {total_fixture_cases} | "
        f"{summary['passedTests']} | {summary['failedTests']} | {summary['skippedTests']} | "
        f"{format_seconds(duration)} |"
    )
    print()

    devices = summary.get("devicesAndConfigurations", [])
    if devices:
        print("### Destinations")
        print()
        print("| Device | Platform | OS | Passed | Failed | Skipped |")
        print("| --- | --- | --- | ---: | ---: | ---: |")
        for item in devices:
            device = item.get("device", {})
            print(
                f"| {device.get('deviceName', 'Unknown')} | {device.get('platform', 'Unknown')} | "
                f"{device.get('osVersion', 'Unknown')} | {item.get('passedTests', 0)} | "
                f"{item.get('failedTests', 0)} | {item.get('skippedTests', 0)} |"
            )
        print()

    if fixture_counts:
        print("### Fixture Suites")
        print()
        print("| Fixture File | Cases |")
        print("| --- | ---: |")
        for file_name, case_count in fixture_counts:
            print(f"| `{file_name}` | {case_count} |")
        print()

    if fixture_entries:
        print("### Fixture Results")
        print()
        print("| Passed | Failed | Recorded |")
        print("| ---: | ---: | ---: |")
        print(f"| {fixture_passed} | {fixture_failed} | {len(fixture_entries)} |")
        print()

        print("<details>")
        print("<summary>Fixture cases</summary>")
        print()
        print()
        print("| Suite | Fixture | Status | Duration |")
        print("| --- | --- | --- | ---: |")
        for fixture in fixture_entries:
            print(
                f"| `{fixture['suite']}` | {fixture['fixture']} | {fixture['status']} | "
                f"{format_seconds(float(fixture['durationSeconds']))} |"
            )
        print()
        print("</details>")
        print()

        failed_fixtures = [fixture for fixture in fixture_entries if fixture.get("status") != "passed"]
        if failed_fixtures:
            print("### Failing Fixtures")
            print()
            for fixture in failed_fixtures:
                message = fixture.get("failures", ["Fixture failed"])[0]
                print(f"- `{fixture['suite']}` / `{fixture['fixture']}`: {message}")
            print()

    if test_cases:
        print("### XCTest Harness")
        print()
        print("| Suite | Test | Result | Duration |")
        print("| --- | --- | --- | ---: |")
        for case in test_cases:
            print(
                f"| {case['suite']} | `{case['name']}` | {case['result']} | {case['duration'] or '-'} |"
            )
        print()

    if failures:
        print("### Failing Harness Cases")
        print()
        for case in failures:
            print(f"- {case['suite']} `{case['name']}`: {case['result']}")
        print()

    print(f"Result bundle: `{xcresult_path}`")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
