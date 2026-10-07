"""Generate the mechanical prototype shell without evaluating frame JavaScript."""
from __future__ import annotations

import argparse
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re

from prototype_contract import load_json, validate_map

TEMPLATES = Path(__file__).resolve().parent.parent / "templates"


def json_text(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def script_json(value):
    return json_text(value).replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")


def validate_state(state, data):
    if not isinstance(state, dict) or set(state) != set(data["routes"]):
        raise ValueError("scenario state keys must equal route keys")
    for route_id, values in state.items():
        if not isinstance(values, dict):
            raise ValueError(f"state {route_id} must be an object")
        for key, value in values.items():
            if key in {"__proto__", "constructor", "prototype"}:
                raise ValueError(f"unsafe state key: {key}")
            if type(value) not in (str, int, float, bool) or value == "":
                raise ValueError(f"state {route_id}.{key} requires a concrete scalar")
    json_text(state)  # rejects NaN and infinity


def fixed_assets(data):
    return ("engine.js", "runtime-data.js", "shell-common.css",
            f"shell-{data['meta']['shellType']}.css", "print-report.css")


def render_html(data, state):
    nav, panels = [], []
    previous_group = None
    for index, (route_id, route) in enumerate(data["routes"].items()):
        group = route.get("group", "")
        if group and group != previous_group:
            parts = re.split(r"[：:]", group, maxsplit=1)
            scope = f' data-scope="{html.escape(parts[0], quote=True)}"' if len(parts) == 2 else ""
            nav.append(f'<li class="c-nav-group-label"{scope}>{html.escape(parts[-1])}</li>')
        previous_group = group
        active = " is-active" if index == 0 else ""
        nav.append(f'<li class="c-nav-link-item{active}" onclick="switchScenario(\'{route_id}\', this)">'
                   f'{html.escape(route["name"])}</li>')
        frames = "".join(f'<div id="{route_id}-{page_id}" class="c-flow-frame"></div>'
                         for page_id in route["pages"])
        shell = "c-mobile-shell" if data["meta"]["shellType"] == "flow" else "c-standard-shell"
        if shell == "c-standard-shell":
            frames = f'<div class="c-standard-shell__content">{frames}</div>'
        panels.append(f'<div id="scenario-{route_id}" class="l-scenario-panel{active}">'
                      f'<div class="{shell}">{frames}</div></div>')
    output = (TEMPLATES / "scaffold-standard.html").read_text(encoding="utf-8")
    if data["meta"]["shellType"] == "flow":
        output = output.replace("assets/shell-standard.css", "assets/shell-flow.css")
    values = {"PROTOTYPE_MAP_JSON": script_json(data), "SCENARIO_STATE_JSON": script_json(state)}
    output = re.sub(r"\{\{(PROTOTYPE_MAP_JSON|SCENARIO_STATE_JSON)\}\}",
                    lambda match: values[match[1]], output)
    output = output.replace("<!-- AI_FILL: PROTOTYPE_MAP.meta.projectName -->",
                            html.escape(data["meta"]["projectName"]))
    for name, value in (("NAV_HTML", "\n".join(nav)), ("PANELS_HTML", "\n".join(panels))):
        output, count = re.subn(r"<!-- AI_FILL: " + name + r"_START.*?AI_FILL: " + name + r"_END -->",
                               lambda _: value, output, flags=re.S)
        if count != 1:
            raise ValueError(f"scaffold needs one {name} slot")
    return output


class Styles(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == "style":
            self.active = True

    def handle_endtag(self, tag):
        if tag == "style":
            self.active = False

    def handle_data(self, data):
        if self.active:
            self.parts.append(data)


def build(map_path, state_path, frames_path, library_path, output):
    data = load_json(map_path)
    errors = validate_map(data)
    if errors:
        raise ValueError(json.dumps(errors, ensure_ascii=False))
    state = load_json(state_path)
    validate_state(state, data)
    frames = frames_path.read_bytes()
    if not frames.strip():
        raise ValueError("frames.js is empty")
    library = library_path.read_text(encoding="utf-8")
    if library_path.suffix.lower() in {".html", ".htm"}:
        parser = Styles()
        parser.feed(library)
        library = "\n".join(parser.parts)
    if not library.strip():
        raise ValueError("component library has no CSS")
    files = {"index.html": render_html(data, state).encode(),
             "assets/frames.js": frames,
             "assets/component-library.css": library.encode(),
             "data/scenario-state.json": json_text(state).encode()}
    files.update({"assets/" + name: (TEMPLATES / name).read_bytes() for name in fixed_assets(data)})
    # Validate every destination before writing; never follow a generated-path symlink.
    output = output.resolve()
    for relative in files:
        target = output / relative
        if target.is_symlink() or not target.resolve().is_relative_to(output):
            raise ValueError(f"output path escapes bundle or is a symlink: {relative}")
        if target.exists() and not target.is_file():
            raise ValueError(f"output path is not a regular file: {relative}")
    for relative, content in files.items():
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("map", "state", "frames", "library", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    try:
        build(args.map, args.state, args.frames, args.library, args.output)
    except (OSError, ValueError) as exc:
        print(f"FAIL {exc}")
        return 1
    print("PASS generated shell/data/assets; frame behavior requires browser verification")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
