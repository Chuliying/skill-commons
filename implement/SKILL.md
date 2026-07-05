---
name: implement
description: |
  使用 RED-GREEN-REFACTOR 實作 feature、bug fix 或 refactor。Use when: router 已指定 Execution Mode，且需要測試先行的程式碼變更。
  觸發關鍵字: implement, 實作, TDD, test first, coding, 開發
source_kind: original
stage: implement
output: <work_root>/<slug>/implement-report.md
---

# Implement

依 router 指定的 Execution Mode 與條件式輸入，直接完成測試先行的實作迴圈。

## Iron Laws

1. 沒有先觀察到正確原因的失敗測試，不寫 production code。
2. 沒有 fresh verification evidence，不宣告完成。
3. Bug 沒有 root-cause evidence，不開始修復。

若 production code 先於測試出現，移除該變更並從 RED 重來。例外只限 throwaway prototype、generated code 或純設定，且必須先取得使用者同意。

## Execution Mode 與條件式輸入

Router 派發時必須指定 Execution Mode。PRD、Spec、qa-plan 的狀態只有：

- `required`：缺件就停止回報，不猜測或補造。
- `optional`：存在就讀，不存在仍可繼續。
- `absent`：此路徑不產該 artifact。

| Execution Mode | PRD | Spec | qa-plan | Handoff |
|---|---|---|---|---|
| `team-feature` | required | required | required | qa validate |
| `personal-feature` | optional | absent | absent | verification-before-completion |
| `bug-fix` | absent | absent | absent | verification-before-completion |
| `refactor` | required | optional | absent | verification-before-completion |

替代證據：

- `bug-fix`：`systematic-debugging` 的 root-cause evidence 與可重現 RED。
- `refactor`：既有行為的 characterization test；Spec 存在時遵循其邊界。
- `personal-feature`：有 PRD/plan 就讀；micro-task 以使用者訊息與 RED 為契約。

## Step 1：環境與邊界

1. 核對 Execution Mode 與條件式輸入，把已讀、optional-missing、absent 記入報告。
2. 讀 `.agent/project-manifest.md`；不存在時用 repo 慣例定位 stack、tests 與 work root，並在報告記錄 fallback。
3. manifest 有 architecture map 或 Domain Skill Names 時，只讀與本次範圍相關者。
4. `has_ui: true` 時讀 design tokens；有 mockup 且任務改 UI 時，實作前建立對照清單。
5. 只修改任務與 failing test 所界定的範圍，維持未授權的外部契約。

## Step 2：RED → GREEN → REFACTOR

每個行為都完成一個完整迴圈，再進下一個。

### RED

1. 寫一條最小測試，名稱描述單一可觀察行為。
2. 使用 manifest `test_cmd` 或 repo 慣例執行該測試。
3. 必須取得 **observed failing test**：測試是 FAIL，不是載入錯誤；訊息符合預期；原因是行為尚未存在。
4. 測試立刻 PASS 時，修正測試或確認這不是新行為；不得把它當 RED evidence。

### GREEN

1. 只寫讓目前 RED 通過的最小 production code，不預做下一個需求。
2. 重跑目標測試，再跑受影響測試；必須全部 PASS。
3. 測試失敗時修 code，不改弱 assertion 來迎合實作。

### REFACTOR

1. 只在 GREEN 後移除重複、改善命名或抽 helper，不新增行為。
2. 每次調整後重跑測試，保持 GREEN。
3. 有 UI 變更時，同步執行適用的 design-token gate。

測試優先使用真實 code；mock 無法避免時，先讀 [`references/testing-anti-patterns.md`](references/testing-anti-patterns.md)。連續失敗超過五次，停止並回到 `systematic-debugging`。

## Step 3：專案模式與完整驗證

1. 核對檔案位置、命名、API、domain rules、tokens 與 mockup。
2. 執行 manifest 宣告的 `test_cmd`；`lint_cmd` 有設定就執行；只有 `typed_contracts: true` 才要求 `typecheck_cmd`。
3. capability false 的檢查明確記 `N/A`，不製造假 evidence。

禁止在沒有輸出證據時使用「應該通過」「大概可用」等完成敘述。

## Output

1. 測試與功能程式碼依 manifest 或 repo 慣例放置。
2. 將每輪 RED/GREEN/REFACTOR、命令、輸出摘要與 gate 結果寫入 `<work_root>/<slug>/implement-report.md`。
3. 更新工作項 `meta.yml`，遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。

## Next Step

- `team-feature` → `qa validate` → `verification-before-completion`。
- 其他 mode → `verification-before-completion`。
- 需要 fresh-context review 時 → `caveman-review`。

## Execution Checklist（artifact handoff 必填）

```text
Skill: implement
Executed At: YYYY-MM-DD HH:MM
Files: [新增/修改檔案]
Report: <work_root>/<slug>/implement-report.md

Steps:
Step 1: 環境與邊界 - [PASS/SKIP]
  Evidence: [mode；輸入狀態；manifest/fallback]
Step 2: RED-GREEN-REFACTOR - [PASS/SKIP]
  Evidence: [RED 預期失敗；GREEN/REFACTOR 指令與結果]
Step 3: 專案模式與完整驗證 - [PASS/SKIP]
  Evidence: [domain/UI 規則；完整驗證輸出]

Gate:
  type-check: [PASS/FAIL/N/A]
  lint: [PASS/FAIL/N/A]
  test: [PASS/FAIL] (X/Y)
  UI mockup: [PASS/N/A]
```

未輸出 checklist 時，這次 artifact handoff 尚未完成。
