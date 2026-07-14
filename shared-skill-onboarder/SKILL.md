---
name: shared-skill-onboarder
description: |
  Shared skills 接入與整併專家。Use when: (1) 其他專案要接入共用 workflow skills, (2) 需要建立或補齊 project-manifest, (3) 需要自動掃描 repo 找出接入缺口, (4) 需要從程式碼中辨識模式並建立 domain skills。個人/輕量專案只要基本工程技能時走 Light track（省略團隊文件檢查與 pattern discovery，manifest 只填精簡欄位）。
  觸發關鍵字: shared skill onboarding, project-manifest, 接入 shared, skills 整併, skill-commons, submodule onboarding, 輕量接入, minimal onboarding, light onboarding
source_kind: original
stage: infra
---

# Shared Skill Onboarder

負責把「其他專案」接到 shared skills 體系上。

核心任務：確保 `implement` 在這個專案中有足夠的知識來寫出符合既有模式的程式碼。

這意味著 onboarding 不只是「檢查檔案存不存在」，而是要：

1. 理解這個專案的技術棧與架構
2. 從程式碼中辨識可重複的實作模式
3. 把這些模式建立成 domain skills
4. 讓 manifest 串起 shared skills 和 project skills

> **Announce at start:** 「我正在使用 shared-skill-onboarder 來檢查或建立 shared skills 接入條件。」

---

## Skill 的兩種類型

### Flow Skills — 放在 `_shared/`，跨專案通用

定義「怎麼做事」的流程，與技術棧無關：

- `prd-interview`：需求 → PRD
- `spec`：PRD → 技術規格
- `qa`：規格 → QA 方案
- `implement`：TDD 實作
- `skill-router`：任務分發
- `shared-skill-onboarder`：本 skill

直接可用，不需要 project-level 版本。

### Domain Skills — 放在 `project/`，各專案自建

定義「這個專案的程式碼長什麼樣」，與技術棧和架構決策高度耦合。

Domain skills 的內容必須從當前專案的程式碼中歸納，不可從其他專案複製。每個 domain skill 至少要引用一個真實存在的參考實作。

---

## Hard Rules

1. **No Guessing**: 找不到就列缺口，不要捏造路徑。
2. **Manifest First**: 所有 shared skills 的入口都必須收斂到 `.agent/project-manifest.md`。
3. **Skills Must Resolve**: manifest 裡宣告的 domain skills 必須真的能對應到 `SKILL.md`。
4. **Validation Before Claim**: 不可在沒有執行 repo 定義的 `validate:agent-manifest` script 前聲稱 onboarding 完成；package manager 依 repo lockfile / `packageManager` 判斷。
5. **Domain Skills From Code**: domain skills 的內容必須從當前專案的實際程式碼中歸納。不可直接套用其他專案的 domain skills。
6. **Shared Dependencies Must Be Bundled or Validated**: shared skills 若需要額外腳本/模板，必須跟著 `_shared/` 一起提供，或由 onboarding/validator 明確檢查並建立；不可默默依賴 host repo 預先存在未宣告的檔案。

---

## Process

### Step 1: 判斷模式

- 使用者說「幫我掃描」→ `Scan`
- 使用者說「幫我整理 checklist / 補 manifest」→ `Guided`
- 不確定時，優先用 `Scan`

### Track 判斷（Light / Full）

避免對只要基本工程技能的專案硬套一整套 team-onboarding 流程。

**Light track** 條件（符合任一即可）：
- `.agent/project-manifest.md` 已宣告 `delivery_mode: personal`
- 使用者說「輕量」「minimal」「個人專案」「先接基本的就好」
- 專案只需要 core 技能（`implement`/`sync-work`/`security`），不涉及 `spec`/`qa`/`prototype`/`prd-interview` 等 team overlay 技能

**Full track**：`delivery_mode: team-sprint`，或使用者明確要接
spec/qa/prototype/domain-modeling。舊 `profile:` 只當遷移輸入解讀，不用它建立
新 manifest。

缺少或不確定時就問一句：「這個專案要接 team 完整流程
（spec/qa/prototype），還是只要 implement 這類基本工程技能？」
先寫入明確 `delivery_mode`，不預設成 Full，也不展開全部 skills。

Light track 省略核心文件檢查與 Pattern Discovery；manifest 只填 Light track 需要的欄位。其餘流程不變。

### Step 2: 核心文件 Readiness 檢查（Full track；Light track 只確認 `project-manifest.md` 存在，其餘略過，直接跳到 Step 4）

確認以下檔案存在：

- `project-manifest.md`
- `guardrails.md`
- `system-context.md`
- `architecture_map`
- `api-reference.md` 與 `api_client_entry`（僅 `has_api: true`）
- `types_entry`（僅 `typed_contracts: true`）
- `design_tokens`（僅 `has_ui: true`）

Capability 為 false 的條件式文件記為 N/A，不阻擋 Full track。這使 team profile 的非 UI CLI
仍可合法完成 onboarding。

對 `system-context.md` 做內容驗證：標題必須包含當前專案名稱，不可是其他專案的複製。若內容過時或描述錯誤的專案 → 先執行 `codebase-understanding` 重新產出。

### Step 3: Pattern Discovery — 模式發現（Full track；Light track 預設跳過，除非使用者主動要求 domain skill scaffolding）

這是整個 onboarding 的核心步驟。目的是從程式碼中找出可重複的實作模式，建立成 domain skills。

分兩階段：

#### 3.1 粗篩（scan-project.js）

執行：

```bash
node .agent/skills/_shared/shared-skill-onboarder/scripts/scan-project.js
```

腳本輸出：
- 框架與技術棧偵測結果
- 目錄結構 fingerprint
- 重複檔案模式（哪些目錄有相同的檔案組合）
- 核心文件存在性
- 現有 project skills 清單
- **§7 Manifest Variable Suggestions**：`Paths` / `Stack` / `Git Workflow` 的偵測建議值（含 source roots/extensions、package manager、四個 capability flags、stack commands 與 remote default branch）

若偵測到的 `framework` 是 React 系（`next`、`vite-react` 等）：在 Scan Output 提示使用者可自行安裝
`vercel-composition-patterns`（React 組合模式指引）——**不**納入本次 onboarding 自動裝入，因為它未 vendor
進 skill-commons（來源授權見 [`../SOURCES.md`](../SOURCES.md)）：

```bash
npx -y skills add 'vercel-labs/agent-skills@vercel-composition-patterns' --copy -y
```

腳本只負責收集線索，不做模式判斷。

#### 3.2 細篩（AI 分析）

> 前置：執行 [Graph Context Check](../graph-context-check.md)。

根據粗篩結果：

1. 讀取 `system-context.md` 理解技術棧
2. 若 `.agent/knowledge/codebase-understanding-report.md` 存在，先讀其中「發現的重複模式」段落作為候選起點
3. 找出粗篩報告中的重複檔案模式（例：`features/` 下每個目錄都有 `index.tsx` + `use*.ts` + `types.ts`）
4. 讀取 1-2 個代表性實作檔案，提煉出具體的模式規則
5. 判斷哪些模式值得建立成 domain skill

**判斷標準**：一個模式值得建立 domain skill 的條件：

- 在 codebase 中出現 2 次以上
- 有固定的檔案結構或命名慣例
- implement 在建立同類功能時需要遵循它

#### 3.3 建立 Domain Skills

對每個辨識出的模式：

1. 在 `project/` 下建立 skill 目錄和 `SKILL.md`
2. SKILL.md 必須引用真實存在的參考實作檔案
3. CRITICAL 規則必須從實際程式碼中歸納
4. 有需要時建立 `references/` 存放詳細規則

#### 3.4 處理 _shared/ 中的 Domain Skills

如果 `_shared/` 裡存在 domain skills（例如從來源專案帶過來的）：

- 這些 skills 描述的是來源專案的架構，不可直接套用
- 可以作為參考，了解「domain skill 長什麼樣」
- 但內容必須根據當前專案重新建立

### Step 4: 建立 project-manifest.md

**Light track 只需要這些欄位**（其餘欄位整段省略，不留 `[路徑]` 佔位符；消費技能在欄位缺席時會依 repo 慣例推導或直接詢問使用者，見各 skill 的 Manifest Contract）：

```md
## Project Identity
- `name`: `[專案名稱]`

## Paths
- `source_roots`: `[原始碼根目錄，可用逗號分隔]`
- `tests_root`: `[測試根目錄]`
- `test_glob`: `[測試檔 glob]`
- `work_root`: `docs/work`
- `docs_root`: `docs`

## Stack
- `test_cmd`: `[跑測試指令]`
- `framework`: `[主框架]`
- `package_manager`: `[package manager 或 language runner]`
- `source_extensions`: `[副檔名，可用逗號分隔]`
- `has_ui`: `false`
- `has_api`: `false`
- `typed_contracts`: `false`
- `has_e2e`: `false`

## Git Workflow
- `base_branch`: `[主整合分支]`
- `remote`: `[主要 remote；通常由 remote default branch 偵測]`
- `sprint_tracking`: `false`
```

**Full track 完整版**（team-sprint；spec/qa/prototype/prd-interview 等 team overlay 技能需要下列全部欄位）：

```md
## Project Identity
- `name`: `[專案名稱]`
- `type`: `[專案類型]`
- `description`: `[一句話描述]`

## Skill Roots
- `shared_skills_root`: `.agent/skills/_shared`
- `project_skills_root`: `.agent/skills/project`

## Core Documents
- `guardrails`: `[路徑]`
- `system_context`: `[路徑]`
- `api_reference`: `[has_api: true 時必填]`
- `architecture_map`: `[路徑]`

## Core Code Entrypoints
- `types_entry`: `[typed_contracts: true 時必填]`
- `api_client_entry`: `[has_api: true 時必填]`
- `design_tokens`: `[has_ui: true 時必填]`

## Paths
[shared skills 用來定位測試 / 設計稿 / 文件，取代寫死的專案路徑。偵測來源：scan-project.js §7]
- `source_roots`: `[原始碼根目錄，可用逗號分隔]`
- `tests_root`: `[測試根目錄]`
- `test_glob`: `[測試檔 glob]`
- `mockup_root`: `[UI 設計稿根目錄，無則略]`
- `work_root`: `docs/work`
- `docs_root`: `docs`

## Stack
[shared skills 用來決定跑什麼指令，取代寫死的 npm 指令。偵測來源：scan-project.js §7]
- `test_cmd`: `[跑測試指令]`
- `typecheck_cmd`: `[型別檢查指令，無則略]`
- `lint_cmd`: `[lint 指令，無則略]`
- `e2e_cmd`: `[E2E 指令，無則略]`
- `framework`: `[主框架]`
- `package_manager`: `[package manager 或 language runner]`
- `source_extensions`: `[副檔名，可用逗號分隔]`
- `has_ui`: `[true/false；預設 false]`
- `has_api`: `[true/false；預設 false]`
- `typed_contracts`: `[true/false；預設 false]`
- `has_e2e`: `[true/false；預設 false]`

## Git Workflow
[sync-work 用來解析 Scoped Save / Integrate / Finish / Recovery 流程]
- `base_branch`: `[主整合分支]`
- `remote`: `[主要 remote；通常由 remote default branch 偵測]`
- `branch_pattern`: `[分支命名]`
- `ticket_pattern`: `[ticket 格式，無則略]`
- `commit_format`: `[commit 規範]`
- `integration_flow`: `[整合流程]`
- `sprint_tracking`: `[true 僅用於 PRD 必須歸屬 Sprint 的專案；否則 false]`

## Domain Skill Names
[只列出已建立的 domain skills，不列尚未存在的]
- `[domain]`: `[skill-name]`

## Domain Skill Readiness
[每個 skill 的狀態和說明]
```

Domain Skill Names 只登記已建立且有參考實作的 skills。不存在的不列。

### Project Variables 填寫（Paths / Stack / Git Workflow）

shared skills（spec、qa、implement、sync-work、subagent-driven-development、security）已改為**讀 manifest 變數**而非寫死路徑/指令/分支。onboarding 必須把這些值寫進 manifest，否則這些技能會反覆詢問使用者。依 track 分兩層，不必兩層都填：

- **Light track**：需要 `source_roots`/`source_extensions`、`tests_root`/`test_glob`、`work_root`/`docs_root`、`test_cmd`/`framework`/`package_manager`、四個 capability flags、`base_branch`/`remote`（供 `to-prd`/`plan-sync`/`implement`/`sync-work`/`security`/`subagent-driven-development` 使用；capability 缺席一律為 false）。
- **Full track** 額外需要：`lint_cmd`；`typed_contracts: true` 才需要 `typecheck_cmd`/`types_entry`，`has_e2e: true` 才需要 `e2e_cmd`，`has_ui: true` 才需要 `mockup_root`/`design_tokens`，`has_api: true` 才需要 `api_reference`/`api_client_entry`。Git workflow 欄位仍依團隊流程填寫。

以下 1-5 步以 Full track 為準；Light track 只做 1（只取 Light 需要的欄位）、2、3，跳過 4（無 ticket_pattern 等欄位）與 5（不 offer git-workflow domain skill）。

1. 讀 scan-project.js 的 **§7 Manifest Variable Suggestions**。
2. 把已由 repo 證據確認的值寫入 manifest 的 `## Paths` / `## Stack` / `## Git Workflow`；`base_branch` 只有 remote default branch 可視為已確認，本地存在常見名稱的分支不算。
3. 偵測為 `not detected` 的路徑或命令，**詢問使用者**，不要猜。Capability 未偵測到時採 `false`，不要求 CLI 專案虛構 UI、API、型別或 E2E 資產。
   偵測到 legacy artifact 目錄時只保留為歷史、不搬移；新工作項一律使用 `work_root`。
4. `ticket_pattern` / `branch_pattern` / `commit_format` / `integration_flow` 無法可靠自動偵測，一律詢問使用者。
5. **Git workflow 複雜度判斷**：若專案是多階段整合（feature → base → release）、有角色分支、或 ticket 綁定流程 → offer 用 [`templates/git-workflow-skill.md`](templates/git-workflow-skill.md) scaffold `project/git-workflow` domain skill，把這些專案專屬流程留在 project 端；shared `sync-work` 偵測到該 domain skill 時 defer 給它。簡單流程（單一 base branch、PR 直入）只填 manifest 即可，不需要這支 skill。

> 設計依據：project-pattern externalization 為 maintainer-side 背景；public
> 接入時以本節 contract 為準。

### Step 5: 驗證

```bash
<package-manager> run validate:agent-manifest
```

若尚未有 validator，明確標記 `validator missing`。

---

## Output

### Scan Output

```md
# Shared Skill Onboarding Report

## Track
- [Light/Full]（判斷依據: [profile 宣告 / 使用者要求 / 詢問結果]）

## Core Documents
- [存在/缺失清單，Light track 只列 project-manifest.md]

## System Context Validation
- 標題是否包含當前專案名稱: [YES/NO]

## Codebase Analysis (粗篩)
- Framework: [偵測結果]
- Repeating Patterns: [重複檔案模式清單]

## Discovered Patterns (細篩)
- [Pattern 名稱]: 出現 N 次，代表性檔案 [路徑]
  → 建議建立 domain skill: project/[skill-name]/

## Created Domain Skills
- [skill-name]: 引用 [參考實作路徑]

## Manifest
- [present/created/updated]

## Validation
- [PASS/FAIL/validator missing]

## Next Steps
1. ...
```

---

## Execution Checklist（必填輸出）

```text
Skill: shared-skill-onboarder
Executed At: YYYY-MM-DD HH:MM
Mode: [Guided/Scan]
Track: [Light/Full]

Steps:
Step 1: 判斷模式
Track 判斷: Light / Full
Step 2: 核心文件 Readiness 檢查 [Full 完整檢查 / Light 只確認 manifest 存在]
Step 3: Pattern Discovery [Full 執行 / Light 跳過]
   3.1 粗篩: [scan-project.js 結果摘要，或 "跳過（Light track）"]
   3.2 細篩: [辨識到的模式數量，或 "跳過（Light track）"]
   Graph Context: [依 `graph-context-check.md` 的 canonical status line]
   3.3 建立 Domain Skills: [建立的 skill 清單，或 "跳過（Light track）"]
Step 4: Manifest [Light 精簡版 / Full 完整版]
Step 5: 驗證

Result:
- track: [Light/Full]
- manifest: [present/missing/created]
- flow skills: [ready/not ready]
- domain skills: [N 個已建立，引用 N 個參考實作，或 "N/A（Light track）"]
- validator: [PASS/FAIL/missing]

Next Steps: [最短可執行下一步]
```

---

## 專案初始化（sitemap + 目錄）

首次接入需掃 route 產 `sitemap.json`、建目錄與 gitignore 規則時，見 [`references/project-init.md`](references/project-init.md)（React/Next）與 `scripts/scan-sitemap.sh`。
