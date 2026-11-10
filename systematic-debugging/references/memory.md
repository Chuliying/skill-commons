# Memory — accumulated debug knowledge base (read/write format)

> Loaded by `systematic-debugging` in Phase 0 (read) and after a successful fix (write).
> This is **optional**: if you do not want to leave traces in your home directory, skip it or use a path inside the project instead (for example `.agent/knowledge/debug-sessions.log`). Before writing, avoid recording sensitive information (paths, secrets, internal URLs).

**Storage path**: `~/.skill-memory/systematic-debugging/debug-sessions.log` (home directory, shared across projects)

## Write format (JSON Lines)

```json
{"date":"2025-03-25","symptom":"type-check fails after rebase","rootCause":"import path changed due to file rename","fix":"update import in 3 files","attempts":1,"tags":["import","type-check"]}
{"date":"2025-03-20","symptom":"chart not re-rendering","rootCause":"missing dependency in useEffect","fix":"add dataSource to deps array","attempts":2,"tags":["react","useEffect"]}
```

## Reading history (before debugging / Phase 0)

```bash
# Show the 10 most recent debug sessions
tail -10 ~/.skill-memory/systematic-debugging/debug-sessions.log 2>/dev/null || echo "(no history)"

# Search for similar symptoms
grep -i "useEffect\|react" ~/.skill-memory/systematic-debugging/debug-sessions.log 2>/dev/null || true
```

## Writing (after a fix)

```bash
mkdir -p ~/.skill-memory/systematic-debugging
echo '{"date":"'$(date +%F)'","symptom":"[symptom]","rootCause":"[root cause]","fix":"[fix]","attempts":[N],"tags":[...]}' \
  >> ~/.skill-memory/systematic-debugging/debug-sessions.log
```

**Purpose**: over time this becomes the project's bug knowledge base. For similar symptoms, the AI can first look up how they were treated before (Phase 0).
