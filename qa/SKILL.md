---
name: qa
description: |
  QA 全流程：從 spec 產出測試方案，並在開發完成後做驗收閘門。Use when: (1) 技術規格完成後需要設計測試, (2) 用戶說「產生測試」「QA 方案」, (3) Story 開發完成、提 PR 前需要驗收。
  觸發關鍵字: QA, 測試方案, test case, validate, 驗收, qa
source_kind: original
stage: qa
output: <work_root>/<slug>/{qa-plan,qa-report}.md
---

# QA

QA 兩件事：**產出測試方案**（plan）與**驗收閘門**（validate）。失敗測試與 RED-GREEN-REFACTOR 交給 `implement`，本技能不重複。

## When to Use

- 技術規格（spec）完成，要設計測試 → 走 **A. 產 QA 方案**
- Story 開發完成、提 PR 前要驗收 → 走 **B. 驗收閘門**

## Trigger

```
/qa plan      [PRD 路徑] [spec 路徑]     # 產出測試方案
/qa validate  [spec 路徑]                # 驗收單一 Story 的 Done Definition
```

---

## A. 產 QA 方案（plan）

從 PRD + spec 產出各層級測試案例。流程與模板見：

- 詳細流程：[`references/qa-plan.md`](references/qa-plan.md)
- 產出模板：[`resources/qa-template.md`](resources/qa-template.md)

**產出落檔**（ADR-006）：`<work_root>/<slug>/qa-plan.md`，並更新工作項
共用的 `meta.yml`，遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。

產出後執行 machine traceability gate：

```bash
python3 <qa-skill-dir>/scripts/check-traceability.py --prd "$WORK_ROOT/$SLUG/prd.md" --qa-plan "$WORK_ROOT/$SLUG/qa-plan.md"
```

有未映射 AC 時修正 qa-plan；此檢查不等待人工核可。

## B. 驗收閘門（validate）

針對單一 spec 做驗收測試與規範檢查，定義 **Done Definition** 最終 gate。通用「無新鮮證據不得宣稱完成」鐵律見 `verification-before-completion`（不在此複述）；本模式只做**這個 story 的 AC 逐條核對 + 該功能測試**。

- 詳細流程：[`references/qa-validate.md`](references/qa-validate.md)
- 一鍵驗收腳本：

```bash
bash .agent/skills/_shared/qa/scripts/run-qa.sh "$WORK_ROOT/$SLUG/qa-plan.md"
```

**輸入**：同一工作項的 `implement-report.md`，用來核對開發側 evidence；
已證明項目可不重測，但 QA 仍需獨立抽驗與逐條核對 AC。

**產出落檔**：`<work_root>/<slug>/qa-report.md`，並更新共用 `meta.yml`。

## C. 寫失敗測試 → 交給 `implement`

需要 Code-First 的 RED-GREEN-REFACTOR 時，呼叫 `implement`；corner cases 從 spec 與 qa-plan 轉成 observed failing tests。

---

## 與 pipeline 的關係

`spec` → **qa (plan)** → `implement` → **qa (validate)** → `caveman-review`
