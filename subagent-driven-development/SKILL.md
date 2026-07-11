---
name: subagent-driven-development
description: |
  使用 Subagent 批次執行 implementation plan。每個任務分派獨立 subagent 實作，並有 spec compliance + code quality 雙重 review。
  觸發關鍵字: subagent, 平行執行, plan 執行, 大型任務
source: obra/superpowers@d884ae04edebef577e82ff7c4e143debd0bbec99
source_kind: adapted
stage: infra
---

# Subagent-Driven Development

> 改編自 [obra/superpowers](https://github.com/obra/superpowers)。
> **與 `superpowers:subagent-driven-development` 同名**：本工作流以此版為準（整合 manifest gate 與 spec/quality 雙重 review）。

## Overview

根據 implementation plan，每個任務分派獨立 subagent 執行，並進行兩階段 review（spec compliance → code quality）。

**核心原則：** 每個 subagent 有新鮮 context，避免 context 污染。

> **Announce at start:** 「我正在使用 subagent-driven-development skill 來執行這個 plan。」

---

## When to Use

```
有 implementation plan？
  → YES：任務大多獨立？
    → YES：留在當前 session？
      → YES：→ subagent-driven-development（本 skill）
      → NO：→ 序列模式（單一 subagent + 人工 checkpoint，見下）
    → NO（耦合度高）：→ 手動逐步執行
  → NO：→ 有 material ambiguity 才先用 brainstorming；否則直接用 plan-sync 產出 plan
```

**序列 / checkpoint 模式：**
- 適合需要人工核准或任務間高度相依的 plan
- 依 plan 順序執行小批次，每批完成後暫停並提供 verification evidence
- 使用者確認後才進下一批；不做平行 dispatch

---

## The Process

### Step 0: 讀取 Plan

1. 讀取 plan 檔案（一次讀完）
2. **提取所有任務的完整文字和 context**（不要讓 subagent 去讀 plan）
3. 建立 TodoWrite，列出所有任務

### Step 1: 執行每個任務（逐一進行）

每個任務的循環：

```
1. 分派 Implementer Subagent
   └─ 提供：完整任務文字 + 專案 context + 相關 spec
   └─ Subagent 如有問題，先回答再讓他繼續

2. Implementer 實作：
   └─ TDD（RED → GREEN → REFACTOR）
   └─ 自我 review
   └─ Commit

3. 分派 Spec Compliance Reviewer Subagent
   提供給 Reviewer 的 Deterministic Gate：

   **🚦 Spec Compliance Gate（必須全部 PASS）**

   | 檢核項目 | 驗證方式 |
   |---------|---------|
   | 檔案清單一致 | `git diff --name-only` 的結果 vs. Plan 的 Files 列表，確認沒有多做或少做 |
   | Spec 步驟覆蓋 | Plan 中每個 Task 對應的 Spec 步驟都已實作，無遺漏 |
   | Interface 一致 | Spec 定義的所有 Interface/Type 都完整出現在程式碼中（欄位名稱 Case-sensitive） |
   | 無超出 Spec 的行為 | diff 中沒有 Spec 未要求的新函式、新 prop、新 state |
   | type-check | manifest `stack.typecheck_cmd` → 0 errors |
   | test | manifest `stack.test_cmd` → all pass |

   ❌ 任一項 FAIL → Implementer 修復 → 重新跑完整 Gate
   ✅ 全部 PASS → 進到下一階段

4. 分派 Code Quality Reviewer Subagent
   提供給 Reviewer 的 Deterministic Gate：

   **🚦 Code Quality Gate（必須全部 PASS）**

   > lint 指令讀 manifest `stack.lint_cmd`；下方為範例。

   <!-- example -->
   ```bash
   # 1. 無 console.log（排除測試和設定檔）
   grep -rn "console.log" [changed_files] | grep -v "test\|spec\|config"

   # 2. 無 any 型別
   grep -rn ": any\b" [changed_files] | grep -v "test\|spec\|\.d\.ts"

   # 3. 無硬編碼色值（Design Token Gate）
   grep -rEn "text-\[#|bg-\[#|border-\[#|from-\[#|to-\[#" [changed_files]

   # 4. 無 TODO/FIXME 殘留
   grep -rn "TODO\|FIXME\|XXX\|HACK" [changed_files]

   # 5. 無 test.only / test.skip
   grep -rn "test\.only\|test\.skip\|it\.only\|it\.skip" [changed_files]

   # 6. lint
   <lint_cmd>
   ```

   | 項目 | 通過條件 |
   |------|---------|
   | console.log | 無結果輸出 |
   | any | 無結果輸出 |
   | 硬編碼色值 | 無結果輸出 |
   | TODO/FIXME | 無結果輸出 |
   | test.only/skip | 無結果輸出 |
   | lint | 0 errors |

   ❌ 任一項 FAIL → Implementer 修復 → 重新跑完整 Gate
   ✅ 全部 PASS → 標記任務完成

5. 標記任務完成（TodoWrite）
6. 繼續下一個任務
```

### Step 2: 最終 Review

所有任務完成後：

1. 分派 **Final Code Reviewer Subagent**（全面 review）
2. 確認整體實作符合 spec
3. 呼叫 `finishing-a-development-branch` skill

---

## ⚠️ Red Flags — 絕對禁止

| 禁止行為 | 原因 |
|---------|------|
| 並行分派多個 implementer subagent | 會造成 git conflict |
| 跳過 spec compliance review | review 是保證品質的關鍵 |
| 讓 subagent 自己讀 plan 檔案 | 效率低，改為 controller 提供完整文字 |
| Spec reviewer 還沒過就做 code quality review | 順序錯誤 |
| 接受「差不多」的 spec compliance | spec reviewer 發現問題 = 未完成 |
| 跳過重新 review（reviewer 發現問題後） | 一定要 fix → 重新 review |

---

## 優勢

**品質保證：**
- Self-review 在移交前抓出自己的問題
- Spec compliance 防止多做或少做
- Code quality 確保程式碼品質
- Review loop 確保修復真的有效

**效率：**
- Fresh context 不會混淆不同任務的邏輯
- Controller 提供完整 context，subagent 不需自己找
- 問題在任務結束前就解決，不會累積

---

## 🔖 Execution Checklist（必填輸出）

每個任務完成後輸出：

```
📋 Task N: [任務名稱]
✅ Implementer: [完成] commits: [SHA]
✅ Spec Review: [PASS] - [簡述確認結果]
✅ Code Quality: [PASS] - [簡述確認結果]
```

所有任務完成後輸出：

```
📋 Skill: subagent-driven-development
📅 執行時間: YYYY-MM-DD HH:MM
📁 Plan: [plan 檔案路徑]

任務執行摘要:
✅ Task 1: [名稱] - DONE
✅ Task 2: [名稱] - DONE
...
✅ Final Code Review: [PASS]

🚦 最終狀態:
   □ 所有任務完成: [Y/N]
   □ Final Review: [PASS/FAIL]
   □ 下一步: finishing-a-development-branch

📝 備註: [特殊情況]
```

---

## Integration

**前置 Skill：**
- `plan-sync` — 產出此 skill 執行的 plan

**使用的 Skills：**
- `implement` — subagent 實作時使用，內含 RED-GREEN-REFACTOR
- `caveman-review` — code quality review 與 fresh-context dispatch

**後續 Skill：**
- `finishing-a-development-branch` — 所有任務完成後呼叫

**替代方案：**
- 序列 checkpoint 模式 — 依序分批並等待人工 checkpoint
