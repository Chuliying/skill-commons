# Skills Reorg — Decision Log (ADRs)

> Produced via `grill-with-docs` grilling session. One ADR per locked decision.
> Status legend: 🔒 locked · 🟡 proposed · ⬜ open

---

## ADR-001 — 單一真實來源：top-level 資料夾 🔒

**Decision:** skill-commons 的 **top-level 技能資料夾**是唯一 source of truth。

- 外部 skills.sh 技能 **vendored 成 top-level 資料夾**（與自寫技能同構）。
- `.claude/skills/`、`.codex/`、`.cursor/` 等為**生成產物**，由 bootstrap 的 generate 步驟從 top-level 同步產生，供各 agent `/` 觸發。
- `.agent/skills/_shared` submodule 掛載契約**不變**，consuming repo 不受影響。

**Consequences:**
- 需要一支 `bootstrap/generate.sh`（或擴充現有 bootstrap）把 top-level 技能 fan-out 到各 agent 目錄。
- `.agents/skills/`（skills.sh 預設複數路徑）將被廢棄/收斂進 top-level。
- 外部技能需要 provenance 記錄（來源 repo@commit）以便日後 update。

---

## ADR-002 — 外部技能 vendoring 與更新策略 🔒

**Decision:** 外部技能以 top-level 資料夾 vendor；目前共 11 個 provenance entries（含 2 個依賴與後續加入的 ponytail）。

- SKILL.md frontmatter 加 `source: owner/repo@<commit>`。
- 根目錄建 `SOURCES.md` 索引（技能 → 來源 repo@commit → 安裝指令）。
- `.agents/skills/` 與 `.claude/skills/`、`.codex/` 設為 `.gitignore` 的生成產物。
- 更新流程：`npx skills update` → 重新 vendor → 更新 `SOURCES.md` commit。

**Consequences:**
- 外部技能保留 upstream 原名（不可改名，否則 provenance/更新會斷）。→ 影響 ADR-003。
- grill-with-docs 依賴的 `grilling`、`domain-modeling` 也一併 vendor。

---

## ADR-003 — 命名一致性 🔒

**Decision（用戶確認：「除了不能改的之外讓名字一致」）：**

- **命名規則**：kebab-case、精簡、動詞起手或名詞概念、**不加 stage 前綴**（與外部技能風格一致）。stage 分組改用 frontmatter `stage:` 欄位 + 根目錄 `INDEX.md`。
- **不可改**：外部技能保留 upstream 原名（ADR-002 provenance 鎖死）。
- **可改（自寫技能）正規化**：去掉 persona/role 字尾（-er / -generator / -engineer / -validator / -builder），收斂成核心概念。

**改名對照（自寫技能）：**

| 現名 | 新名 | 理由 |
|---|---|---|
| feature-implementer | `implement` | 去 persona 字尾（對應清單 "Add"） |
| test-driven-development | `tdd` | 精簡（對應清單 "TDD"） |
| qa-generator + qa-validator + qa-engineer | `qa` | 三合一（見 ADR-005） |
| prototype-builder + prototype-tuner | `prototype` | 二合一（見 ADR-005） |
| doc-librarian | `markdown` | 對應清單 "Markdown"（文件轉換） |
| spec-generator | `spec` | 去 -generator 字尾（與 qa-generator→qa 一致） |
| dev-kickoff / plan-sync / brainstorming / skill-router / skill-creator | 不變 | 已一致 |

---

## ADR-004 — domain vs shared 分類 🔒

**Proposal:** 全部 curated 技能都是 **shared flow 技能**（跨專案通用），放 `_shared`（即本 repo top-level）。**domain 技能維持原機制**：由 consuming repo 在 `.agent/skills/project/` 自建，從該專案程式碼歸納，不放進 playbook。external 技能（grill/to-prd/caveman/reducing-entropy/find-skills）皆 shared；`vercel-composition-patterns`、`shadcn`、`design-taste-frontend` 屬「shared-但技術相關」，仍放 shared，由 router 在偵測到對應技術棧時才載入。

---

## ADR-005 — 既有技能合併/裁減（只留必要） 🔒（用戶最終裁減：persona/分析類 archive，工具類保留）

**保留為 infra（前題已確認）：** systematic-debugging, verification-before-completion, shared-skill-onboarder, codebase-understanding。

**合併：** qa-* →`qa`；prototype-* →`prototype`。

**提案裁減（移到 `_archive/` 而非直接刪，可回復）：**
api-doc-parser, architect, auditor, change-tracker, project-onboarding, rd-sync-work, sync-work, repo-investigator, reverse-prd（被 to-prd 取代）, rollback, security, vercel-react-best-practices（被 vercel-composition-patterns 取代）, writing-plans（被 grill+plan-sync 取代）, executing-plans, finishing-a-development-branch, subagent-driven-development, requesting-code-review, code-reviewer（被 caveman-review 取代）。

> ⚠️ 此為最高風險決策（影響範圍大、近乎不可逆）→ 需用戶逐項確認，見 plan.md「裁減確認清單」。

---

## ADR-006 — 產出物固定落檔結構 🔒

**2026-07-04 修訂：** 工作流產出改以工作項為軸，集中在 manifest
`work_root`（預設 `docs/work`）的 `<work_root>/<slug>/`；slug 不含日期且跨 stage
沿用。每個工作項只有一份 `meta.yml`，各 stage 更新自己的 entry。獨立格式轉換
落在 `<docs_root>/reference/`。legacy `.agent/artifacts/` 留在原地，不搬移；新工作
一律遵循根目錄 `ARTIFACTS.md` v2。

---

## ADR-007 — CLAUDE.md 狀態追蹤模板 🔒

**2026-07-04 修訂：** root `CLAUDE.md` 只放超過半數 session 會用到的穩定規則、
指令與導航，目標不超過 50 行。易變的 **目前狀態 / 計劃 / TODO / Backlog**
移到 `docs/STATUS.md`；技能只在 stage 邊界更新相關一行。機器路徑與指令仍以
`project-manifest.md` 為單一來源。

---

## ADR-008 — 成功衡量指標 🔒

見 metrics.md（8 條可驗證指標）。

---

## ADR-009 — Work-item Closeout 🔒

工作項在 merge／PR 前 closeout，不把 spec/QA 內容複製回 PRD：

1. `prd.md` 追加 `## Delivery`，記錄發布日、與原 PRD 的偏差、PASS 驗收連結與已升級資產。
2. `meta.yml` 改為 `shipped`，stages 標為 done/validated。
3. `adr.md` / `glossary.md` 中仍長期有效的內容升級到專案層，work item 原件保留。

`finishing-a-development-branch` 在使用者選擇 merge／PR 後、實際執行前 closeout；保留或放棄 branch 不標 `shipped`。`qa validate` PASS 時提示可 closeout。
