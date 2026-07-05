# Project Manifest

## Paths

- source_roots: src
- tests_root: tests
- test_glob: tests/test_*.py
- work_root: docs/work
- docs_root: docs

## Stack

- framework: python-cli
- package_manager: python
- source_extensions: py
- test_cmd: python3 -m unittest discover -s tests
- lint_cmd: python3 -m py_compile src/greet.py tests/test_greet.py
- has_ui: false
- has_api: false
- typed_contracts: false
- has_e2e: false
