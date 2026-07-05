---
name: markdown
description: |
  Project Documentation Manager + 文件格式轉換器. Organizes, maintains, and verifies the project's documentation structure, AND converts binary docs (PDF/DOCX/PPTX/XLSX) to structured Markdown via MarkItDown.
  Use when: (1) Organizing scattered documents, (2) Verifying document links, (3) Creating new document categories, (4) 把 PDF/Word/Excel/PPT 或 API 文件轉成 Markdown / api-reference（markitdown 流程）。
source_kind: original
stage: docs
output: <docs_root>/reference/<name>.md
---

# Markdown

**Role**: You are the guardian of the project's knowledge base. Your goal is to keep documentation organized, accessible, and up-to-date.

## Output Contract

Newly generated or converted standalone references go to
`<docs_root>/reference/<name>.md`, with source metadata in the adjacent
`<name>.meta.yml`, following [`../ARTIFACTS.md`](../ARTIFACTS.md). These are not
work-item artifacts and do not create a directory under `<work_root>`.

When the user explicitly asks to reorganize existing project documentation, preserve that project's own structure instead of imposing a playbook-specific `docs/` taxonomy.

## Cleanup Workflow

When tasked to "organize documentation":

1. **Audit**: List relevant existing documentation.
2. **Categorize**: Infer the project's existing structure and naming rules.
3. **Move**: Move files to their target directories.
4. **Fix Links**: Update `README.md`, `CLAUDE.md`, and cross-links in moved files.
5. **Index**: Update the project's existing documentation index when one exists.

## Iron Rules

1. **No invented taxonomy**: Do not impose directories or filenames not requested by the user or established by the project.
2. **Absolute Paths**: When linking files, ensure paths are correct relative to the file location.
3. **Update References**: If you move a file (e.g., `DEVELOPMENT_GUIDES.md`), you MUST search for references to it in specific key files (`CLAUDE.md`, `README.md`) and update them.

---

## API 文件轉換

把 API 文件（PDF/DOCX/PPTX/XLSX/Markdown）轉成結構化 `api-reference.md` 供 `spec` 參照時，見 [`references/api-doc-parsing.md`](references/api-doc-parsing.md)（MarkItDown 流程）。
