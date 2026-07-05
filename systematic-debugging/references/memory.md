# Memory — 累積 Debug 知識庫（讀寫格式）

> 由 `systematic-debugging` 在 Phase 0（讀）與修復成功後（寫）載入。
> 屬**選用**：若不在家目錄留痕，可跳過或改成專案內路徑（如 `.agent/knowledge/debug-sessions.log`）。寫入前避免記入敏感資訊（路徑、密鑰、內部 URL）。

**儲存路徑**：`~/.skill-memory/systematic-debugging/debug-sessions.log`（家目錄，跨專案共用）

## 寫入格式（JSON Lines）

```json
{"date":"2025-03-25","symptom":"type-check fails after rebase","rootCause":"import path changed due to file rename","fix":"update import in 3 files","attempts":1,"tags":["import","type-check"]}
{"date":"2025-03-20","symptom":"chart not re-rendering","rootCause":"missing dependency in useEffect","fix":"add dataSource to deps array","attempts":2,"tags":["react","useEffect"]}
```

## 讀取歷史（除錯前 / Phase 0）

```bash
# 查看最近 10 個 debug session
tail -10 ~/.skill-memory/systematic-debugging/debug-sessions.log 2>/dev/null || echo "(no history)"

# 搜尋相似症狀
grep -i "useEffect\|react" ~/.skill-memory/systematic-debugging/debug-sessions.log 2>/dev/null || true
```

## 寫入（修復後）

```bash
mkdir -p ~/.skill-memory/systematic-debugging
echo '{"date":"'$(date +%F)'","symptom":"[symptom]","rootCause":"[root cause]","fix":"[fix]","attempts":[N],"tags":[...]}' \
  >> ~/.skill-memory/systematic-debugging/debug-sessions.log
```

**用途**：逐漸成為專案的 bug 知識庫。對於相似病狀，AI 可先查過去的治療方式（Phase 0）。
