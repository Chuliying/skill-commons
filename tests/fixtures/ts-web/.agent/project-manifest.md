# Project Manifest

## Paths

- source_roots: src
- tests_root: tests
- test_glob: tests/*.js
- work_root: docs/work
- docs_root: docs

## Stack

- framework: vite-react
- package_manager: npm
- source_extensions: ts,tsx,js
- test_cmd: node tests/greet.test.js
- typecheck_cmd: node scripts/typecheck.js
- lint_cmd: node --check scripts/typecheck.js && node --check tests/greet.test.js
- e2e_cmd: node tests/e2e.test.js
- api_check_cmd: node scripts/api-check.js
- has_ui: true
- has_api: true
- typed_contracts: true
- has_e2e: true
