# Agent Guardrails

Until the project's own rules are written down, follow these conservative limits:

- Do not force push.
- Do not delete remote branches.
- Do not read, change or commit `.env` or other secrets files.
- Before an irreversible action, explain its effect and get the user's explicit confirmation.

<!-- TODO: add the project's own limits: what may change, how to verify, and release boundaries. -->
