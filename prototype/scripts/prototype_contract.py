"""Dependency-free executable PrototypeMap v1/v2 contract.

Validates structure and references, not PRD meaning, approval or JavaScript safety.
Error paths are JSON pointers so repair tooling can identify a bounded change.
"""
from __future__ import annotations

import json
import math
import re
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path


def pointer(path, key):
    return path + "/" + str(key).replace("~", "~0").replace("/", "~1")


def parse_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"non-JSON number: {value}")

    return json.loads(text,
                      object_pairs_hook=unique, parse_constant=invalid)


def load_json(path):
    return parse_json(Path(path).read_text(encoding="utf-8"))


def validate_map(data):
    errors = []

    def error(path, message):
        errors.append({"path": path, "message": message})

    def obj(value, path):
        if not isinstance(value, dict):
            error(path, "must be an object")
            return {}
        return value

    def string(value, path, empty=False):
        if not isinstance(value, str) or (not empty and not value.strip()):
            error(path, "must be a non-empty string" if not empty else "must be a string")
            return False
        return True

    def integer(value, path, minimum=1, maximum=None):
        if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
            error(path, f"must be an integer in {minimum}..{maximum or 'unbounded'}")

    def array(value, path, nonempty=False):
        if not isinstance(value, list) or (nonempty and not value):
            error(path, "must be a non-empty array" if nonempty else "must be an array")
            return []
        return value

    def timestamp(value, path):
        if string(value, path):
            try:
                dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
                if dt.tzinfo is None:
                    raise ValueError("timezone required")
            except ValueError:
                error(path, "must be an ISO timestamp with timezone")

    def keys(values, path):
        for key in values:
            if path == "/routes" and key.isdecimal():
                error(pointer(path, key), "use a named route ID (e.g. s1); JS reorders numeric object keys")
            if not re.fullmatch(r"[a-zA-Z0-9_-]+", key) or key in {"__proto__", "constructor", "prototype"}:
                error(pointer(path, key), "unsafe identifier")

    def fields(value, path, allowed):
        if version == 2:
            for key in sorted(value.keys() - set(allowed.split())):
                error(pointer(path, key), "unknown v2 field")

    root = obj(data, "")
    meta = obj(root.get("meta"), "/meta")
    routes = obj(root.get("routes"), "/routes")
    pages = obj(root.get("pages"), "/pages")
    version = meta.get("schemaVersion", 1)
    if type(version) is not int or version not in (1, 2):
        error("/meta/schemaVersion", "supported versions are 1 and 2")
    fields(root, "", "meta routes pages frames")
    fields(meta, "/meta", "schemaVersion projectName subtitle prdVersion shellType createdAt frozenAt coverageRate gaps backfillRound frameSeedRef prdHistory")
    if "frameSeedRef" in meta:
        string(meta["frameSeedRef"], "/meta/frameSeedRef")
    for field in ("projectName", "prdVersion"):
        string(meta.get(field), "/meta/" + field)
    if "subtitle" in meta:
        string(meta["subtitle"], "/meta/subtitle", empty=True)
    if meta.get("shellType") not in ("standard", "flow"):
        error("/meta/shellType", "must be standard or flow")
    timestamp(meta.get("frozenAt"), "/meta/frozenAt")
    if "createdAt" in meta:
        timestamp(meta["createdAt"], "/meta/createdAt")
    if "coverageRate" in meta:
        value = meta["coverageRate"]
        if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 100:
            error("/meta/coverageRate", "must be a finite number in 0..100")
    if "backfillRound" in meta:
        integer(meta["backfillRound"], "/meta/backfillRound", 0)
    for i, gap in enumerate(array(meta.get("gaps", []), "/meta/gaps")):
        path = f"/meta/gaps/{i}"
        gap = obj(gap, path)
        fields(gap, path, "prdAcId description reason acknowledgedBy")
        for field in ("prdAcId", "description", "reason", "acknowledgedBy"):
            string(gap.get(field), pointer(path, field))
    for i, history in enumerate(array(meta.get("prdHistory", []), "/meta/prdHistory")):
        path = f"/meta/prdHistory/{i}"
        history = obj(history, path)
        fields(history, path, "version mapVersion changedAt summary")
        for field in ("version", "summary"):
            string(history.get(field), pointer(path, field))
        integer(history.get("mapVersion"), path + "/mapVersion")
        timestamp(history.get("changedAt"), path + "/changedAt")

    if not routes:
        error("/routes", "at least one route required")
    if not pages:
        error("/pages", "at least one page required")
    keys(routes, "/routes")
    keys(pages, "/pages")
    memberships = {page_id: set() for page_id in pages}
    class ShellIds(HTMLParser):
        def __init__(self):
            super().__init__()
            self.ids = set()

        def handle_starttag(self, tag, attrs):
            identifier = dict(attrs).get("id")
            if identifier:
                self.ids.add(identifier)

    shell = ShellIds()
    shell.feed((Path(__file__).resolve().parent.parent / "templates/scaffold-standard.html").read_text(encoding="utf-8"))
    dom_ids = shell.ids
    for route_id in routes:
        panel_id = "scenario-" + route_id
        if panel_id in dom_ids:
            error(pointer("/routes", route_id), "generated route ID conflicts with shell")
        dom_ids.add(panel_id)
    for route_id, route in routes.items():
        path = pointer("/routes", route_id)
        route = obj(route, path)
        fields(route, path, "name group pages")
        string(route.get("name"), path + "/name")
        if "group" in route:
            string(route["group"], path + "/group", empty=True)
        seen = set()
        for i, page_id in enumerate(array(route.get("pages"), path + "/pages", nonempty=True)):
            refpath = f"{path}/pages/{i}"
            if not isinstance(page_id, str) or not page_id:
                error(refpath, "route page id must be a string")
                continue
            if page_id not in pages:
                error(refpath, "unknown page reference")
            else:
                memberships[page_id].add(route_id)
            if page_id in seen:
                error(refpath, "duplicate page reference")
            seen.add(page_id)
            dom_id = route_id + "-" + page_id
            if dom_id in dom_ids:
                error(refpath, "ambiguous generated DOM id")
            dom_ids.add(dom_id)

    frames = obj(root["frames"], "/frames") if "frames" in root else None
    flows = {}
    for page_id, page in pages.items():
        path = pointer("/pages", page_id)
        page = obj(page, path)
        fields(page, path, "label frameRef type flowId acs backStep nextStep")
        string(page.get("label"), path + "/label")
        if string(page.get("frameRef"), path + "/frameRef"):
            if not re.fullmatch(r"[a-zA-Z0-9_-]+", page["frameRef"]) or page["frameRef"] in {"__proto__", "constructor", "prototype"}:
                error(path + "/frameRef", "unsafe frame identifier")
        if not memberships[page_id]:
            error(path, "page is unreachable from routes")
        if frames is not None and isinstance(page.get("frameRef"), str) and page["frameRef"] not in frames:
            error(path + "/frameRef", "unknown frame reference")
        for field in ("backStep", "nextStep"):
            if field in page and (not isinstance(page[field], str) or page[field] not in pages):
                error(pointer(path, field), "unknown page reference")
        if version == 2:
            kind = page.get("type", "surface")
            if kind not in ("surface", "flow-step"):
                error(path + "/type", "must be surface or flow-step")
            if kind == "flow-step":
                fid = page.get("flowId")
                if string(fid, path + "/flowId"):
                    flows.setdefault(fid, set()).update(memberships[page_id])
            elif "flowId" in page:
                error(path + "/flowId", "only flow-step pages have a flowId")
        for i, ac in enumerate(array(page.get("acs"), path + "/acs")):
            acpath = f"{path}/acs/{i}"
            ac = obj(ac, acpath)
            fields(ac, acpath, "id text prd src isHint")
            if "isHint" in ac and type(ac["isHint"]) is not bool:
                error(acpath + "/isHint", "must be boolean")
            string(ac.get("id"), acpath + "/id")
            string(ac.get("text"), acpath + "/text")
            for field in ("prd", "src"):
                if field in ac:
                    string(ac[field], acpath + "/" + field)
            if isinstance(ac.get("prd"), str) and re.search(r"同 [0-9S]|同上|見 [0-9S]|參見", ac["prd"]):
                error(acpath + "/prd", "expand abbreviated PRD reference")
    for fid, route_ids in flows.items():
        if len(route_ids) != 1:
            error("/pages", f"flowId {fid} must belong to exactly one route")
    if frames is not None:
        keys(frames, "/frames")
        for frame_id, frame in frames.items():
            path = pointer("/frames", frame_id)
            frame = obj(frame, path)
            fields(frame, path, "shell sections")
            string(frame.get("shell"), path + "/shell")
            rows = set()
            for i, section in enumerate(array(frame.get("sections"), path + "/sections", nonempty=True)):
                spath = f"{path}/sections/{i}"
                section = obj(section, spath)
                fields(section, spath, "row label span count notes")
                row = section.get("row")
                integer(row, spath + "/row", 0)
                if type(row) is int:
                    if row in rows:
                        error(spath + "/row", "duplicate row")
                    rows.add(row)
                string(section.get("label"), spath + "/label")
                integer(section.get("span"), spath + "/span", 1, 12)
                if "count" in section:
                    integer(section["count"], spath + "/count")
                if "notes" in section:
                    string(section["notes"], spath + "/notes", empty=True)
    return errors


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("map", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        errors = validate_map(load_json(args.map))
    except (OSError, ValueError) as exc:
        errors = [{"path": "", "message": str(exc)}]
    if args.json:
        print(json.dumps({"pass": not errors, "errors": errors}, ensure_ascii=False))
    else:
        for error in errors:
            print(f"FAIL {error['path'] or '/'}: {error['message']}")
        if not errors:
            print("PASS map structure and references (coverage meaning and approval not verified)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
