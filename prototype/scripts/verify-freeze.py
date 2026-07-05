#!/usr/bin/env python3
"""Compare generated prototype assets with a frozen PrototypeMap JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", dest="map_path", type=Path, required=True)
    parser.add_argument("--html", type=Path, required=True)
    parser.add_argument("--assets-dir", type=Path)
    args = parser.parse_args()

    errors: list[str] = []
    try:
        frozen = json.loads(args.map_path.read_text(encoding="utf-8"))
        html = args.html.read_text(encoding="utf-8", errors="replace")
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2

    if not isinstance(frozen, dict):
        print("FAIL frozen map must be an object", file=sys.stderr)
        return 1
    meta = frozen.get("meta", {})
    routes = frozen.get("routes", {})
    pages = frozen.get("pages", {})
    if not isinstance(meta, dict) or not isinstance(routes, dict) or not isinstance(pages, dict):
        print("FAIL meta/routes/pages must be objects", file=sys.stderr)
        return 1
    if not html.strip():
        fail("index.html is empty", errors)
    if not routes:
        fail("frozen map has no routes", errors)
    if not pages:
        fail("frozen map has no pages", errors)
    if not meta.get("frozenAt"):
        fail("meta.frozenAt is missing", errors)
    if not isinstance(meta.get("coverageRate"), (int, float)):
        fail("meta.coverageRate must be numeric", errors)
    if not isinstance(meta.get("gaps", []), list):
        fail("meta.gaps must be an array", errors)

    assets = args.assets_dir or args.html.parent / "assets"
    shell = str(meta.get("shellType", "standard"))
    if shell not in {"standard", "flow"}:
        fail(f"unsupported shellType: {shell}", errors)
    required_assets = {
        "engine.js",
        "shell-common.css",
        f"shell-{shell}.css",
        "component-library.css",
        "print-report.css",
    }
    for name in sorted(required_assets):
        path = assets / name
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing or empty asset: {name}", errors)
    if "assets/component-library.css" not in html:
        fail("index.html does not load assets/component-library.css", errors)
    for token in ("PROTOTYPE_MAP", "FRAME_REGISTRY", "SCENARIO_STATE"):
        if token not in html:
            fail(f"index.html missing runtime data: {token}", errors)

    for route_id, route in routes.items():
        if f"scenario-{route_id}" not in html:
            fail(f"missing route panel: {route_id}", errors)
        if not isinstance(route, dict):
            fail(f"route is not an object: {route_id}", errors)
            continue
        route_pages = route.get("pages", [])
        if not isinstance(route_pages, list):
            fail(f"route pages must be an array: {route_id}", errors)
            continue
        for page_id in route_pages:
            if not isinstance(page_id, str) or not page_id:
                fail(f"route page id must be a string: {route_id}", errors)
                continue
            if page_id not in pages:
                fail(f"route {route_id} references unknown page: {page_id}", errors)
            if f"{route_id}-{page_id}" not in html:
                fail(f"missing page container: {route_id}-{page_id}", errors)

    for page_id, page in pages.items():
        if not isinstance(page, dict):
            fail(f"page is not an object: {page_id}", errors)
            continue
        frame_ref = str(page.get("frameRef", ""))
        if not frame_ref or frame_ref not in html:
            fail(f"missing frameRef for page {page_id}: {frame_ref or '<empty>'}", errors)
        page_acs = page.get("acs", [])
        if not isinstance(page_acs, list):
            fail(f"page acs must be an array: {page_id}", errors)
            continue
        for ac in page_acs:
            ac_id = str(ac.get("id", "")) if isinstance(ac, dict) else ""
            if not ac_id or not re.search(rf"(?<![\w-]){re.escape(ac_id)}(?![\w-])", html):
                fail(f"missing AC for page {page_id}: {ac_id or '<empty>'}", errors)

    gaps = meta.get("gaps", []) if isinstance(meta.get("gaps", []), list) else []
    for gap in gaps:
        gap_id = str(gap.get("prdAcId", "")) if isinstance(gap, dict) else ""
        if gap_id and gap_id not in html:
            fail(f"missing acknowledged gap marker: {gap_id}", errors)

    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    print(
        "PASS freeze comparison "
        f"routes={len(routes)} pages={len(pages)} "
        f"acs={sum(len(page.get('acs', [])) for page in pages.values() if isinstance(page, dict) and isinstance(page.get('acs', []), list))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
