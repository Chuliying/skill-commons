# Execution Checklist 慣例

這個格式用於 durable artifact 的階段交接，讓 verification-before-completion 核對 skill 是否留下執行證據。沒有 artifact handoff 的技能不強制輸出 checklist。

## 共用格式

```text
Skill: <skill-name>
Executed At: YYYY-MM-DD HH:MM

Steps:
PASS Step/Phase N: <名稱>
  Evidence: <具體結果，不能只寫「已完成」>

Result: PASS | FAIL | N/A
Summary: <結果摘要>
Notes: <風險或下一步；沒有則填「無」>
```

Step/Phase 內容由各 skill 定義。狀態只用 `PASS`、`FAIL`、`N/A`；不使用圖示。

## 鐵律

有 durable artifact handoff 的技能未把 checklist 寫入 canonical artifact 時，該階段未完成。Checklist 必須引用實際命令、檔案或 Gate 證據。
