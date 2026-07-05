---
name: codebase-understanding
description: |
  程式碼庫全局理解專家。Use when: (1) 進入大型 / 陌生 codebase, (2) 需要產出 architecture map, (3) 需要發現 domain skill 候選, (4) 重構前需要依賴關係視覺化, (5) Code Review 需要影響範圍分析。
  觸發關鍵字: 理解程式碼, codebase 分析, 架構圖, knowledge graph, 探索專案, 了解系統, 看看架構, understand
source_kind: original
stage: infra
---

# Codebase Understanding

**可以把它想像成讓 AI「看懂」整個 codebase 的 X 光機**。
利用 [Understand-Anything](https://github.com/Lum1104/Understand-Anything)（以下簡稱 UA）的 multi-agent pipeline，自動掃描程式碼庫、建立 knowledge graph、產出互動式架構 Dashboard。

## When to Use

- 進入大型或陌生的 codebase（需要完整 knowledge graph，而非單檔閱讀）
- 需要產出或更新 `architecture_map`
- 準備重構前，想看到模組依賴全貌
- `shared-skill-onboarder` 的 Pattern Discovery 階段，想要更精確的模式發現
- Code Review 時需要影響範圍分析

## When NOT to Use

- 專案很小（< 50 檔案），直接閱讀程式碼或用 `rg` 探索就夠了
- 純文件、文字、設定描述變更，沒有追蹤模組依賴的需求
- 只需要單一檔案/函式的解釋（直接閱讀程式碼）
- 已有完善的 `architecture_map` 且近期無大型變更
- `.understand-anything/knowledge-graph.json` 已超過 7 天未更新時，不要直接信任；先提醒使用者重新生成或改用既有文件與 `rg`

## Prerequisites

- [Understand-Anything](https://github.com/Lum1104/Understand-Anything) 已安裝
  - Claude Code:
    - `/plugin marketplace add Lum1104/Understand-Anything`
    - `/plugin install understand-anything`
  - Codex:
    - `curl -fsSL https://raw.githubusercontent.com/Lum1104/Understand-Anything/main/install.sh | bash -s codex`
  - 其他支援平台：依 UA README 將最後的 platform 參數改為 `opencode`、`gemini` 等對應名稱
- Node.js ≥ 22, pnpm ≥ 10（UA 的依賴要求）

> **Announce at start:** 「我正在使用 codebase-understanding 來分析整體程式碼架構。」

---

## Trigger

自然語言觸發詞：

```
理解這個專案
看看架構
```

UA slash commands（需先安裝 UA，非本 skill 觸發詞）：

```
/understand
/understand-dashboard
/understand-diff
```

---

## Process

### Step 1: 前置確認

1. **確認 UA 已安裝**：
   - 在支援 slash command 的 agent CLI 中確認 `/understand`、`/understand-dashboard` 可用，或檢查 `~/.understand-anything/repo`
   - 若未安裝 → 提示使用者安裝，給出對應平台的安裝指令，不要假裝已完成分析

2. **確認分析範圍**：
   - 預設：整個專案根目錄
   - 使用者可指定子目錄（如 `src/` 或特定 package）

3. **檢查是否已有 knowledge graph**：
   - 路徑：`.understand-anything/knowledge-graph.json`
   - 若已存在且 7 天內更新 → 詢問是否重新掃描或使用既有結果
   - 若已存在但超過 7 天未更新 → 先警告使用者 graph 可能過時，建議重新掃描

### Step 2: 執行 UA 分析 Pipeline

```
/understand --language zh-TW
```

UA 會自動執行 5-agent pipeline：

| # | Agent | 做什麼 |
|---|-------|--------|
| 1 | Project Scanner | 發現檔案、識別語言/框架 |
| 2 | File Analyzer | 用 tree-sitter 解析程式碼、產出 nodes/edges |
| 3 | Architecture Analyzer | 分類為 API / Service / Data / UI / Utility 層 |
| 4 | Tour Builder | 按依賴順序產出 guided walkthroughs |
| 5 | Graph Reviewer | 驗證圖譜完整性 |

產出：`.understand-anything/knowledge-graph.json`

> 此步驟可能消耗大量 LLM tokens。大型 codebase 建議先確認 token 預算。

### Step 3: 啟動 Dashboard（可選）

```
/understand-dashboard
```

在瀏覽器中啟動互動式 Dashboard，可以：
- Pan / Zoom 瀏覽架構全貌
- 點擊 node 查看函式/模組的白話描述
- 依 layer（API / Service / Data / UI）篩選
- 使用 Guided Tour 依序理解架構

### Step 4: 提取架構資訊

從 `knowledge-graph.json` 中提取關鍵資訊：

#### 4.1 Architecture Map 產出

讀取 nodes 的 `layer` 分類，彙整為架構層級摘要：

```markdown
## Architecture Map（由 UA 自動產出）

### API Layer
- [node summaries]

### Service Layer
- [node summaries]

### Data Layer
- [node summaries]

### UI Layer
- [node summaries]

### Utility Layer
- [node summaries]
```

將此摘要寫入 `.agent/knowledge/architecture-map.md`，再把該檔案路徑填入 `project-manifest.md` 的 `architecture_map`。

#### 4.2 Domain Skill 候選發現

分析 nodes 中的重複模式：

1. 找出相同 `type` + 相似 `metadata` 的 node 群組
2. 找出 edges 中反覆出現的依賴模式（如 component → hook → api-call）
3. 標記出現 2 次以上的結構模式 → 建議建立 domain skill

#### 4.3 關鍵依賴路徑

從 edges 中提取：
- 最高 in-degree 的 nodes（被最多模組依賴 → 修改風險最高）
- 最長依賴路徑（理解核心業務流程）

### Step 5: 產出報告並更新 manifest

將分析結果寫入 `.agent/knowledge/codebase-understanding-report.md`。

確認 `.agent/project-manifest.md` 的 `architecture_map` 指向 `.agent/knowledge/architecture-map.md`。若 manifest 不存在或格式不明，停止並回報需要人工建立或更新，不要把 raw `knowledge-graph.json` 寫成 `architecture_map`。

若需要讓團隊共用 UA 圖譜，可提交 `.understand-anything/` 中的 graph 產物；但不要提交 `.understand-anything/intermediate/` 與 `.understand-anything/diff-overlay.json` 這類本機暫存。

---

## Output

### 核心產出

| 產出 | 路徑 | 說明 |
|------|------|------|
| Knowledge Graph | `.understand-anything/knowledge-graph.json` | UA 產出的完整圖譜 |
| 架構理解報告 | `.agent/knowledge/codebase-understanding-report.md` | 人類可讀的架構摘要 |
| Architecture Map | `.agent/knowledge/architecture-map.md` | `project-manifest.md` 的 `architecture_map` 應指向此檔案路徑 |
| Domain Skill 候選 | 報告內的建議清單 | 供 `shared-skill-onboarder` 使用 |

### Report Template

```markdown
# Codebase Understanding Report

> 此報告由 Understand-Anything 自動產生，建議人工審核。

## 分析基本資訊

- **分析日期**：[YYYY-MM-DD]
- **分析範圍**：[專案路徑]
- **技術棧**：[Framework / Language / Styling / State]
- **檔案數量**：[N] 個（nodes 數量）
- **依賴關係**：[N] 條（edges 數量）

## Architecture Map

### API Layer
- [node summaries with key files]

### Service Layer
- [node summaries with key files]

### Data Layer
- [node summaries with key files]

### UI Layer
- [node summaries with key files]

### Utility Layer
- [node summaries with key files]

## 關鍵模組（High-Impact Nodes）

| 模組 | 被依賴次數 | 說明 | 修改風險 |
|------|-----------|------|---------|
| [module] | [N] | [summary] | // |

## 發現的重複模式（Domain Skill 候選）

| 模式名稱 | 出現次數 | 代表性檔案 | 建議 Skill |
|---------|---------|-----------|-----------|
| [pattern] | [N] | [file path] | `project/[name]/` |

## Guided Tour 摘要

1. [Tour step 1 - 入口模組]
2. [Tour step 2 - 核心邏輯]
3. ...

## 建議 Next Steps

1. [ ] 審核 Architecture Map，更新 `project-manifest.md`
2. [ ] 對候選模式執行 Pattern Discovery（`shared-skill-onboarder` Step 3）
3. [ ] 若需要更新 `system-context.md`（技術棧），依本報告「技術棧」欄位補寫至 manifest
```

---

## 子指令：影響分析

當需要分析特定變更的影響範圍時：

```
/understand-diff
```

產出：在 knowledge graph 上標記受影響的 nodes 和 edges，視覺化 ripple effects。

適用場景：
- Flow B（需求變更）的 `plan-sync` 補強
- Flow F（Code Review）的影響範圍判斷

---

## 與其他 Skills 的關係

| Skill | 關係 |
|-------|------|
| `shared-skill-onboarder` | 雙向：本 skill 的 Domain Skill 候選清單可作為其 Pattern Discovery 輸入；其在 `system-context.md` 過時時也會回呼本 skill 重新產出 |
| `to-prd` | 上游：重構前先用本 skill 理解依賴全貌，再用 to-prd 逆向產出 PRD |
| `plan-sync` | 補強：`/understand-diff` 提供視覺化影響分析 |
| `caveman-review` | 補強：提供模組依賴 context |

---

## Execution Checklist（必填輸出）

> Checklist 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。

```text
Skill: codebase-understanding
Executed At: YYYY-MM-DD HH:MM
Artifact: [knowledge-graph.json 路徑]

Steps:
Step 1: 前置確認
   └─ UA 安裝狀態: [已安裝/已安裝指引]
   └─ 既有 graph: [無/已存在→重新掃描/已存在→沿用]
Step 2: UA 分析 Pipeline
   └─ Nodes 數量: [N]
   └─ Edges 數量: [N]
   └─ 辨識 Layers: [API: N, Service: N, Data: N, UI: N, Utility: N]
Step 3: Dashboard
   └─ [已啟動/跳過]
Step 4: 提取架構資訊
   └─ Architecture Map: [已產出/跳過]
   └─ Domain Skill 候選: [N 個模式]
   └─ High-Impact Nodes: [N 個]
Step 5: 產出報告並更新 manifest
   └─ 報告路徑: [path]
   └─ Architecture Map 路徑: `.agent/knowledge/architecture-map.md`
   └─ Manifest architecture_map: [已更新/需人工更新]

Result:
- knowledge graph: [已產出 / 沿用既有]
- architecture map: [ready / 需人工審核]
- manifest: [architecture_map 已指向 architecture-map.md / 需人工更新]
- domain skill 候選: [N 個模式待確認]
- 建議 next step: [最短可執行下一步]

Notes: [token 消耗估計、分析覆蓋率、需注意事項]
```

只有本次分析交接 durable architecture artifact 時，未把 Checklist 寫入 artifact 才算交接未完成。

---

## 注意事項

1. **Token 消耗**：UA 跑完整 pipeline 會消耗大量 tokens，大型 codebase（> 500 檔案）建議分批分析
2. **一次性快照**：`knowledge-graph.json` 不會自動更新，程式碼大幅變更後需重跑 `/understand`
3. **Graph 品質**：UA 的分析品質取決於程式碼的可讀性和結構化程度。混亂的 codebase 可能產出品質較低的圖譜
4. **不取代人工判斷**：Architecture Map 和 Domain Skill 候選都是建議，需人工審核確認
