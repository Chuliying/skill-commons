---
name: spec
description: |
  將 PRD 轉化為技術實作規格。Use when: (1) PRD 完成後, (2) 需要設計技術方案, (3) 用戶說「產生 spec」「技術設計」時。
  觸發關鍵字: spec, 技術規格, 技術設計, 實作規格, spec
source_kind: original
stage: docs
output: <work_root>/<slug>/spec.md
---

# Spec

將 PRD 轉化為技術實作規格（spec.md），定義具體的實作步驟。

## When to Use

- PRD 已完成並通過 Gate 1
- 用戶說「產生 spec」「技術設計」
- 準備進入實作階段

## Trigger

```text
/spec [PRD 路徑]
```

---

> **沒有足夠資訊就不產出 Spec。不可推測或假設。** 完整的產出前提檢核併入下方 **Gate 2 preflight**（FR/ERR/AC、
> Project Manifest、API Reference、UI Token、UI Mockup 等都在該表；不在此重複一份，避免兩份清單
> 日後改一邊漏改另一邊）。資訊不足時：列出缺口 → 向使用者確認 → 等待確認後才開始產出。

## Process

### Step 0: 讀取 Project Manifest

> **shared skill 不得寫死專案文件或 domain skill 路徑。**

開始前必須：

1. 讀取 `.agent/project-manifest.md`
2. 取得四個 Stack capability flags、`system_context`、`architecture_map` 與 `environment_rules`；
   `has_api` 才讀 `api_reference`，`typed_contracts` 才讀 `types_entry`，`has_ui` 才讀 `design_tokens`
3. 讀取 `Domain Skill Names`，依需求載入實際宣告的 domain skills；不假設固定名稱
4. 檢查 `architecture_map`：
   - 存在且檔案可讀 → 讀取後繼續
   - 不存在、路徑失效、或明顯過時 → 詢問使用者選擇：
     a. 執行 `codebase-understanding` Flow N 自動生成（需 UA），產出 `.agent/knowledge/architecture-map.md` 並更新 manifest
     b. 手寫 `.agent/knowledge/architecture-map.md`，再更新 manifest
     c. 暫時略過，並在 Spec 標記 `Architecture Map Missing` risk
5. `system_context` 缺失時停止；capability 為 true 但對應路徑或命令缺失時才要求補齊

### Base 分支差異檢查

> 技術規格需要知道遠端差異，但不得在訪談或規格階段改動工作樹。

讀 manifest 的 `git_workflow.remote` 與 `git_workflow.base_branch`（缺少時詢問使用者），以
`<remote>`、`<base>` 代入：

```bash
git fetch <remote> <base>
git rev-list --left-right --count HEAD...<remote>/<base>
```

回報 ahead/behind 數量後繼續。若使用者明確要求同步，停止目前流程並交給 `sync-work`；
未取得明確要求時不得整合分支。

### Gate 2 preflight：前置檢查（必須先通過）

**Gate 2 preflight 執行順序（固定）**：

1. `Project Manifest / System Context / System Map / capability-required references` 完整性
2. `Knowledge Boundary`（Hard 立即停止；Soft 轉 FU）
3. ` Follow-ups 阻擋掃描`（包含第 2 步新產生的 FU）

> 優先序：`Hard boundary` > `FU 阻擋` > 其他檢查。
> 若第 2 步新增任何「阻擋型  待確認」FU，必須重新掃描 FU 後再決定是否可進入 Step 1。

> `check-prd`（見下表「PRD 完整」列）已確定性保證 PRD 形狀與 FU 段存在；下方「Follow-ups 阻擋」列因此只做語意判斷：是否有未關閉的阻擋型 FU。

| 檢查項目 | 檢查方式 | 未通過動作 |
|---------|---------|-----------|
| **Knowledge Boundary** | 從 manifest 讀取 `knowledge_boundary`；存在則讀取，不存在則跳過 | Hard boundary 違反 → 停止；Soft → 建立 FU |
| ** Follow-ups 阻擋** | **掃描 PRD 是否存在「阻擋型」且  待確認 的 FU（含 Boundary 後二次掃描）；未標記類型的 FU 視同阻擋型** | ** 立即停止，列出所有阻擋型/未標記類型的  FU 清單，要求回 PRD 確認後再執行** |
| **Project Manifest** | **必須讀取** `.agent/project-manifest.md` | 停止並要求補齊 |
| **System Context** | **必須讀取** manifest 中 `system_context` | 執行 `/init` 或 `codebase-understanding` |
| **System Map** | 依 Step 0 決策樹確認 manifest 中 `architecture_map` 已讀取，或已標記 risk | 未處理 decision → 停止 |
| API Reference | `has_api: true` 時確認 `api_reference` 存在；false 為 N/A | 執行 `markdown` |
| PRD 完整（機器檢查） | 執行 `python3 <shared_skills_root>/scripts/check-prd.py --prd <PRD 路徑> --tier team`：同一份 producer 契約當 input 前置，驗證 FR/AC/ERR、FU 段存在、AC 為 GWT、無殘留 placeholder | 退出非 0 → 停止並要求修正 PRD，不得開始設計 |
| **UI Token 規範** | `has_ui: true` 時讀取 `design_tokens` 與 UI domain skill；false 為 N/A | 補齊 manifest 或 domain skill |
| **系統型別/契約** | `typed_contracts: true` 時讀取 `types_entry`；false 為 N/A | 補齊 manifest 或 validator |
| **UI Mockup** | `has_ui: true` 且存在 `mockup_root` 時讀取所有適用圖檔；false 為 N/A | 存在但未讀時停止 |

**Gate 2 preflight 未通過** → 禁止開始後續步驟

## 核心原則 (Core Principles)

1. **Single Source of Truth (SSOT)**:
    - `has_api: true` 時，**必須優先讀取 manifest `api_reference` 指向的 API 文件**；找不到路徑一律先查 `.agent/project-manifest.md`，禁止創造不存在的路徑。
    - **絕對禁止** 猜測或僅憑現有前端程式碼推斷 API 格式。現有程式碼可能是錯的。
    - 若找不到文件，**必須** 暫停並詢問用戶「是否有 API 文件？」。只有在用戶確認「無文件」後，才可與用戶討論定義契約。
2. **Data Contract First**:
    - `typed_contracts: true` 時先定義專案語言的資料契約，再寫邏輯。
    - `has_api: true` 時契約命名與欄位必須和 API 文件一致。
3. **Atomic & Strict**:
    - 步驟拆小，但執行標準極嚴。
    - 每個契約欄位都必須有來源依據；capability false 時不建立假 Interface。
4. **Challenge First**:
    - 讀取 PRD 時先挑戰需求：先問「這個需求在技術上合理嗎？」「資料流是否可行？」。
    - 如果發現 PRD 有邏輯漏洞，**必須**退回要求修正。
5. **相容性**:
    - Spec 設計必須相容 manifest 指向的既有核心型別與系統結構，除非必要且經過詳細評估。

---

### Step 1：判斷 Story 類型（選擇模板）

> 根據 PRD 內容決定使用哪個模板

| Story 類型 | 判斷條件 | 使用模板 |
|-----------|---------|---------|
| **新功能** | 需要新增契約、API 呼叫、UI 或核心行為 | `spec-template.md` |
| **整合型** | 僅啟用/配置既有 Feature | `integration-spec-template.md` |

選定模板後、開始填寫 spec.md 前，必讀
[`references/spec-field-guide.md`](references/spec-field-guide.md)。模板只定義必填輸出骨架；
field guide 定義 Capability Snapshot、Files、Contracts、API/UI 條件式章節、
Flow / Data Flow、Errors、Decisions、Steps、Test Strategy 與 Gate 2 的填寫判斷。

**整合型特徵**：

- PRD 主要引用既有 Feature PRD
- 不需要新 Interface 或 API 呼叫
- 主要工作是配置啟用

> **關鍵原則**：依序讀取每個 Story PRD → 產出對應 Spec。不可在資訊不完整時開始產出。

### Step 2：讀取並理解 PRD（ 必須完整讀取）

1. 讀取目標 Story PRD 文件
2. **完整提取**關鍵資訊：
   - 功能需求 (FR) - 每個 FR 的輸入/輸出
   - 驗收標準 (AC) - GWT 格式
   - 錯誤場景 (ERR) - 觸發條件 + 預期行為
   - `has_ui: true` 時提取 UI/UX 概念與設計稿；false 為 N/A
   - **Flow section / 流程章節**（若存在）- 依 heading 語意讀取，作為技術設計的互動流程輸入
   - **NFR** - 作為效能/安全設計約束輸入
3. 如有引用 Feature PRD，**必須一併讀取**
4. **UI Mockup 讀取**（`has_ui: true` 且 Story 變更 UI 時必做）：
   - 掃描 manifest `paths.mockup_root` 找最新設計稿目錄（沒有就問使用者；無設計稿則略）
   - 若存在 mockup 圖檔，**讀取所有 PNG 圖檔**
   - 從 mockup 中提取：版面結構、欄位定義、元件層次、響應式行為（桌面 vs 手機）
   - 將 mockup 觀察結果記錄於 Spec 的「UI Component Design」章節

> **禁止**：在未完整讀取 PRD 前開始設計技術方案
> **禁止**：`has_ui: true` 且 mockup 存在時，Spec 的元件規格與 mockup 佈局不一致

### Step 3：分析環境與既有程式碼

> [!IMPORTANT]
> READ manifest 中 `environment_rules` 指向的規則文件 first.
> 認證、server/client 邊界與環境變數策略一律讀 manifest `environment_rules`；shared skill 不提供專案預設。

> 前置：執行 [Graph Context Check](../graph-context-check.md)。

1. 搜尋相關程式碼：找最少必要的類似實作作為參考；通常 1-2 個足夠，找不到時記錄 fallback
2. 識別需要變更的檔案
3. 分析依賴關係
4. **契約與資料流檢查**（Critical）：
   - `typed_contracts: true` 時讀取 `types_entry`，禁止建立衝突契約；false 記 N/A
   - `has_api: true` 時以 `api_reference` 為契約來源
   - `has_api` 與 `has_ui` 都為 true，且兩側資料形狀不同時定義 Transformer

**依據 domain skills 檢核**：遍歷 manifest `Domain Skill Names`，依各 skill 的 description 與需求範圍載入匹配項目；沒有匹配項目就使用 repo 既有實作作證據，不創造固定 domain 名稱。

讀取 skill 附屬的 `references/`、`resources/` 時，必須以實際找到的 skill 目錄為基準解析，不可寫死 `.agent/skills/...`

### 技術方案研究 (Tech Research)

只在新領域、外部 API/library、效能風險或安全風險明顯時做外部研究。內部小改動以 repo 慣例與相似實作作證據即可，並記錄 `Skipped: repo evidence sufficient`。

若環境有 web search 類工具（各 harness 名稱不同，例：Claude Code 的 `WebSearch`），可用它尋找最佳實作模式與潛在雷區：

```text
web_search("best practices for [tech stack] [feature]")
web_search("[feature] performance optimization [manifest stack.framework]")
```

若環境**沒有**此類工具：記錄 `Skipped: environment has no web search tool`；不因此卡住 Gate。

**驗證重點**：

1. 是否有現成的 Library 可用？
2. 大數據量下的效能解決方案？
3. 類似功能的常見 Anti-pattern？

### Step 4：查詢 API Reference（`has_api` 條件式）

> `has_api: true` 時必須查詢 API Reference；false 時記錄 `N/A (has_api=false)`。

**參考檔案**：manifest 中 `api_reference`

1. 根據 PRD 需求找到對應的 API
2. 複製 Request/Response JSON 範例到 Spec
3. 複製或引用 repo 使用的資料契約 / type definition 到 Spec
4. 如 API Reference 無對應 API，向使用者確認

### Step 5：設計技術方案

針對每個 FR，設計：

1. 需要的檔案變更
2. 元件/函式設計
3. 狀態管理方式
4. API 設計（如需要）

### Step 6：記錄技術決策

**決策評估標準**：

1. 可測試性
2. 可讀性
3. 一致性（與既有模式）
4. 簡潔性
5. 可逆性
6. SOLID 原則

### Step 7：規劃實作步驟

將實作拆分為可獨立提交的步驟：

```markdown
1. [ ] **新增型別定義**（15min）
   - 檔案：`[manifest 中 types_entry]`
   - 新增 `[FeatureContract]` 資料契約

2. [ ] **建立功能模組**（30min）
   - 檔案：`[依 domain skill / repo 慣例解析的路徑]` [NEW]
   - 依賴：步驟 1
```

**每個步驟必須**：

- 有時間估計
- 標記檔案操作（NEW/MODIFY/DELETE）
- 標記依賴關係

### Step 8：Gate 2 自檢（ 必須全部通過）

> ** 禁止主觀判斷**：以下每個適用項目都必須有客觀證據，特別是 capability 啟用的契約驗證。

| 類別 | 檢核項目 | 通過標準（客觀證據） |
|------|---------|--------------------|
| **Environment** | **符合環境規則** | Auth/SSR/Proxy 策略符合 manifest 中 `environment_rules` |
| **Tech Research** | **證據足夠** | 有 repo evidence、外部來源摘要，或明確 skip 理由 |
| 檔案 | 檔案清單完整 | 每個 FR 都有對應檔案 |
| 步驟 | 步驟有估時 | 每個步驟都有時間估計 |
| 決策 | 技術決策有理由 | 每個決策都有選擇原因 |
| **資料契約** | **條件式編譯** | `typed_contracts: true` 時必須以 `typecheck_cmd` 或對應 validator 實際驗證；false 為 N/A |
| **API 範例** | **契約安全** | `has_api: true` 時資料範例符合上述資料契約；false 為 N/A |
| **無未定義引用** | **依賴完整** | Spec 中提到的 hook/component 都有定義，或明確標註 `[EXISTING]` |
| **資料流** | **Transformer** | `has_api` 與 `has_ui` 都為 true 時定義 API Response → UI 轉換；否則依能力標 N/A |
| **測試案例** | **Unit Test** | 包含 Logic/Transformer 的 Unit Test 規劃 |
| **UI Token 合規** | **禁止 Hex Code** | `has_ui: true` 時執行 manifest-aware design-token gate；false 為 N/A |
| **UI Mockup 對齊** | **視覺規格一致** | `has_ui: true` 且有 mockup 時對齊；false 為 N/A |
| **版控** | **版本歷史表** | 已填寫第一筆（含修改時間、修改內容、對應 PRD 版本、作者） |

Gate 2 自檢通過後，team feature 依 [`../GATE-PACKAGE.md`](../GATE-PACKAGE.md) 呈現設計取捨：先把 spec stage 設為 `awaiting-approval`；收到 team 設計核可後改為 `approved`，才交給 QA plan。Personal/refactor optional spec 不新增人工 Gate，只保留 self-check evidence。

---

## Execution Checklist（必填輸出）

> Checklist 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。

```
Skill: spec
Executed At: YYYY-MM-DD HH:MM
Artifact: [Spec 檔案路徑]

Steps:
 Gate 2 preflight: 前置檢查 - [PASS/SKIP]
   └─ FU 阻擋掃描: [無阻擋型  FU / 發現 N 筆阻擋型  FU（已停止）]
   └─ Knowledge Boundary: [已讀取 / 跳過（manifest 無欄位）/ Hard 違反 N 筆]
   Evidence: [system-context , system-map , api-reference ]
Step 1: 判斷 Story 類型 - [PASS/SKIP]
   Evidence: [新功能/整合型]
Step 2: 讀取 PRD - [PASS/SKIP]
   Evidence: [PRD 路徑, FR/AC/ERR 數量]
Step 3: 分析環境與既有程式碼 - [PASS/SKIP]
   Evidence: [參考的類似實作]
   └─ Graph Context: [used / understand-diff used / missing -> rg fallback / stale -> rg fallback / skipped]
技術方案研究 - [PASS/SKIP]
   Evidence: [repo evidence / 外部來源摘要 / skip 理由]
Step 4: 查詢 API Reference - [PASS/SKIP]
   Evidence: [使用的 API 編號]
Step 5: 設計技術方案 - [PASS/SKIP]
   Evidence: [檔案清單摘要]
Step 6: 記錄技術決策 - [PASS/SKIP]
   Evidence: [決策數量]
Step 7: 規劃實作步驟 - [PASS/SKIP]
   Evidence: [步驟數量, 總估時]
Step 8: Gate 2 自檢 - [PASS/SKIP]
   Evidence: [自檢結果: PASS/FAIL]

 Gate 2 檢查:
   □ Environment: [PASS/FAIL]
   □ Tech Research: [PASS/FAIL/SKIP] (repo evidence / external evidence / skip reason)
   □ 檔案清單: [PASS/FAIL]
   □ Typed contract: [PASS/FAIL/N/A]
   □ API 範例: [PASS/FAIL/N/A]
   □ Transformer: [PASS/FAIL/N/A]

Notes: [任何特殊情況或後續建議]
```

**未輸出 Checklist = 未完成 Skill**

---

### 常見遺漏（必檢）

| 容易遺漏 | 必須提供 |
|---------|----------|
| API 回傳格式 | `has_api: true` 時提供可追溯範例；false 為 N/A |
| 邊界條件 | 空資料、null、錯誤的 JSON 範例 |
| 資料轉換 | `has_api` + `has_ui` 時提供 API-to-UI transformer；其他情況依流程或 N/A |
| 測試案例 | 可執行的 describe/it 程式碼 |
| 狀態更新邏輯 | Store/State 的更新流程 |

---

## Output

| 產出 | 路徑 |
|------|------|
| 技術規格 | `<work_root>/<slug>/spec.md` |
| Metadata | `<work_root>/<slug>/meta.yml` |

使用 `resources/spec-template.md` 或 `resources/integration-spec-template.md` 模板；
填寫規則依 [`references/spec-field-guide.md`](references/spec-field-guide.md)
，並遵循 [`../ARTIFACTS.md`](../ARTIFACTS.md)。

---

## Spec Artifact 結構

```
<work_root>/<slug>/
├── spec.md
└── meta.yml
```

---

## Next Step

spec.md 完成且通過 Gate 2 後：

```
/qa plan <work_root>/<slug>/prd.md <work_root>/<slug>/spec.md
```

---

## File Markers

| 標記 | 說明 |
|------|------|
| `[NEW]` | 新建檔案 |
| `[MODIFY]` | 修改既有檔案 |
| `[MODIFY L45-60]` | 修改特定行數 |
| `[DELETE]` | 刪除檔案 |

---

## 通用原則（跨切面）

設計涉及**資料轉換**（API 格式 ≠ 前端模型）或**時間參數**（SSR/client 一致性）的功能時，必讀 [`references/cross-cutting-principles.md`](references/cross-cutting-principles.md)：Data Transformer 規範與時間參數一致性規範。專案專屬細節屬 domain skill。
