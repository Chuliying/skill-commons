#!/usr/bin/env python3
"""Verify a generated bundle against its frozen map and installed fixed templates.

This is an integrity/structure check, not JavaScript execution, UI acceptance,
PRD coverage, or proof of human approval. Legacy hand-written bundles must be
regenerated with prototype_bundle.py; they are not silently grandfathered.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path

from prototype_contract import load_json, parse_json, validate_map
from prototype_bundle import TEMPLATES, fixed_assets, json_text, render_html, validate_state


class DataScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.values = {}
        self.current = None
        self.duplicates = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'script':
            self.current = None
            if attrs.get('type') == 'application/json':
                key = attrs.get('id')
                if key in self.values:
                    self.duplicates.append(key)
                self.current = key
                self.values[key] = ''

    def handle_endtag(self, tag):
        if tag == 'script':
            self.current = None

    def handle_data(self, value):
        if self.current is not None:
            self.values[self.current] += value


def verify(map_path, html_path, assets_dir=None):
    frozen = load_json(map_path)
    errors = [f"{e['path'] or '/'}: {e['message']}" for e in validate_map(frozen)]
    if errors:
        return errors
    output = html_path.parent.resolve()
    if html_path.is_symlink():
        return ['index.html must not be a symlink']
    html = html_path.read_text(encoding='utf-8')
    parser = DataScripts()
    parser.feed(html)
    if parser.duplicates:
        errors.append('duplicate JSON script IDs')
    try:
        embedded = parse_json(parser.values['prototype-map'])
        state = parse_json(parser.values['scenario-state'])
        if json_text(embedded) != json_text(frozen):
            errors.append('embedded map differs from frozen map; regenerate the bundle')
        validate_state(state, frozen)
    except (KeyError, ValueError) as exc:
        return errors + [f'missing/invalid pure JSON data: {exc}; regenerate with prototype_bundle.py']
    if html != render_html(frozen, state):
        errors.append('HTML shell/data differs from deterministic projection; regenerate the bundle')
    assets = output / 'assets'
    if assets_dir is not None and assets_dir.resolve() != assets.resolve():
        errors.append('--assets-dir must be the directory actually loaded by index.html')
    for name in (*fixed_assets(frozen), 'frames.js', 'component-library.css'):
        path = assets / name
        if path.is_symlink() or not path.resolve().is_relative_to(output):
            errors.append(f'asset escapes bundle or is a symlink: {name}')
        elif not path.is_file() or not path.stat().st_size:
            errors.append(f'missing or empty asset: {name}')
        elif name in fixed_assets(frozen) and path.read_bytes() != (TEMPLATES / name).read_bytes():
            errors.append(f'fixed asset changed: {name}')
    state_path = output / 'data/scenario-state.json'
    if state_path.is_symlink() or not state_path.resolve().is_relative_to(output):
        errors.append('scenario-state path escapes bundle or is a symlink')
    elif json_text(load_json(state_path)) != json_text(state):
        errors.append('embedded scenario state differs from data/scenario-state.json')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map', dest='map_path', type=Path, required=True)
    parser.add_argument('--html', type=Path, required=True)
    parser.add_argument('--assets-dir', type=Path)
    args = parser.parse_args()
    try:
        errors = verify(args.map_path, args.html, args.assets_dir)
    except (OSError, ValueError) as exc:
        errors = [str(exc)]
    for error in errors:
        print(f'FAIL {error}')
    if not errors:
        print('PASS freeze structure/integrity; browser behavior and approval not verified')
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
