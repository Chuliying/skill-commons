# skill-commons

[![CI](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml/badge.svg)](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml)

skill-commons 把共用的工程工作流程放進 repository，讓 Claude Code、Codex 與
Cursor 沿用相同的任務分流、文件格式和驗證規則。跨 session、跨 agent 的工作
可以接續，完成宣稱也能回到實際執行的證據。

這是一套可攜式 feature-delivery protocol 和工具集。repository artifacts 保存
工作狀態，declarative contracts 約束格式。排程和不同 host 的狀態留在各自的
執行環境；push、merge 與 deploy 仍由使用者授權。

## 什麼時候值得用

skill-commons 適合這幾種情況：

- 工作會跨 session、跨 agent，或需要由另一個人接手。
- 團隊需要固定的 PRD、計畫、驗證與 release handoff 格式。
- 同一個 repository 同時有人使用 Claude Code、Codex 或 Cursor。
- 你希望完成宣稱能對應到實際執行的 test、lint 或其他 evidence。

一次性的簡短問答和邊界清楚的 micro-task 可以直接實作與驗證，省略額外文件。

## Quick Start

### 需要的工具

- Git（需支援 submodule）
- Bash 3.2+（macOS 內建版本即可）
- `jq`（Claude Code settings merge 需要）
- Python 3.10+（Plan Sync、Repo Map 與本 repo 完整驗證需要）
- Node.js 18+（onboarding scan 與 TypeScript/Web fixtures 需要）

只使用 Markdown skills 時不需要 Python。`rg` 可選；安裝後搜尋較快。

### 1. 加入 submodule

Pin `v0.7.0` tag：

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.7.0
```

### 2. 選擇工作模式

複製 manifest template，然後在 onboarding 前確認 selection：

```bash
mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
${EDITOR:-vi} .agent/project-manifest.md
```

個人或小型專案可從這個設定開始：

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs:
```

`delivery_mode` 必須是 `personal` 或 `team-sprint`。需要前端或選用工具時，才在
`capability_packs` 加上 `frontend` 或 `optional`。mode 未指定時 onboarding 會停止，
避免把空值解讀成「全部安裝」。

### 3. Onboard

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

接著讓 agent 讀 `shared-skill-onboarder/SKILL.md`。它會從 repository 補齊 paths、
stack、capabilities 與 Git workflow；找不到的資料應保持 unknown，不要猜。

## Execution Mode 與工作流程

每個任務先由 `skill-router` 選一條最小流程，再依 execution mode 決定哪些條件式
文件要建立。任務只取用需要的階段。

```text
使用者需求
  → skill-router 選擇 flow
  → 需要時釐清需求或建立 plan
  → implement / systematic-debugging
  → verification-before-completion
  → 經授權後才進入 release 操作
```

### Delivery modes

| Mode | 適合情況 | 額外流程 |
|---|---|---|
| `personal` | 個人或低交接密度工作 | 不載入 team 的 PRD interview、Spec、QA、prototype |
| `team-sprint` | 需要正式需求、設計和 QA 交接 | 加入 PRD、Spec、QA、prototype 與 domain modeling |

兩種 mode 都包含 core skills。`frontend` 和 `optional` 是另外選擇的 capability
packs；實際 membership 以 [`profiles/`](profiles/) 與
[`profiles.json`](profiles.json) 為準。

### Artifact contract

`protocol-registry.json` 是 execution mode 與 artifact requirement 的 machine
source。以下表格只提供閱讀摘要：

| execution_mode | 必要文件 | 視需要建立 | 不使用 |
|---|---|---|---|
| `team-feature` | PRD、Spec、QA plan、Plan、implement report、QA report | — | — |
| `personal-feature` | implement report | PRD、Plan | Spec、QA plan/report |
| `bug-fix` | implement report | Plan | PRD、Spec、QA plan/report |
| `refactor` | PRD、implement report | Spec、Plan | QA plan/report |

工作狀態和交付狀態分開記錄：`work_status` 表示 requested work 是否完成；
`delivery_status` 才記錄 approval、PR、merge 或 deployment。完整格式見
[`ARTIFACTS.md`](ARTIFACTS.md)。

## 核心能力與邊界

### Brainstorming：有歧義才用

`brainstorming` 只在 material ambiguity 會改變 scope、架構、公開行為或驗收方式，
而且 repo evidence 無法回答時載入。
清楚的 micro-task、bug、review、既有 spec 實作和 read-only 問題直接 Skip。

四種成本模式是 Skip / Quick / Standard / Deep：

| Mode | 上限 |
|---|---|
| Skip | 不問問題，直接走對應 flow |
| Quick | 最多一問 |
| Standard | 最多三問；每個決策最多兩個選項；一次最終確認 |
| Deep | 先說明原因、範圍和成本，取得使用者同意後才進行 |

`brainstorm.md` 只在跨 session、跨 agent、正式 team handoff 或使用者要求時建立。
靜態 contract tests 可以檢查這些邊界，但不能證明模型一定正確觸發，也不能單獨
證明 token、時間或成果品質有改善。這類結論需要 matched A/B run 與人工 review。

### Plan Sync：保存計畫；Goal Mode 管理執行

Plan Sync 保存 repository 內的任務依賴、blocker 和 Verification Evidence。Codex
或 Claude Code 的 Goal Mode 則負責目前 session 的 continuation、budget、pause 和
resume。兩者可以一起用，責任維持分開。

v0.7 只接受 canonical-v2 `plan/plan.md`。`planctl` 能驗證 recorded evidence 的
格式與引用，不能替你執行測試，也不能證明某個 authored `PASS` 是誰產生的。
`--goal-status` 會輸出 `host_goal=unmanaged`，明確表示 host lifecycle 不由 repo
plan 管理。

### Repo Map：可重現的本地索引

`codebase-understanding` 預設使用本地 Repo Map：

```bash
python3 <codebase-understanding-dir>/scripts/repo_map.py scan --root .
python3 <codebase-understanding-dir>/scripts/repo_map.py status --root .
```

它使用 Git 和 Python standard library，不需要 network、LLM、daemon 或外部 parser。
Python import 由 AST 提取；JS/TS 只記錄 line-oriented `textual_candidate`。
`module_reference` 只記錄尚未解析的候選。caller/callee、impact 與 semantic graph
都需要另外解析。

v1 的 `status` 會重算 supported inputs，成本是 O(repo)，沒有 incremental database。
[Understand-Anything](SOURCES.md#optional-runtime-adapters) 只保留為明確 opt-in 的
interactive visualization。啟用前要另外確認 runtime、network、model/token cost
與資料政策；它不控制 Repo Map freshness 或 release gate。

## 平台與 fan-out

Top-level skill folders 是唯一 source of truth。`bootstrap/generate.sh` 依 selection
把它們 fan-out 到各 host 的 discovery 位置：

| 平台 | 接入方式 |
|---|---|
| Claude Code | `.claude/skills/`、`CLAUDE.md`、SessionStart hook |
| Codex | `.codex/skills/`、`AGENTS.md` |
| Cursor | Cursor rule 與 `AGENTS.md`；不做 skill fan-out |

修改集中在 top-level skill folders，生成目錄只承接 fan-out。ownership ledger 只允許
update/uninstall 變更 managed entries，foreign skills、hooks、rules 和文字會保留。
`PROFILE=all` 僅供 maintainer 執行完整生成；consuming repo 依 manifest selection 生成。

平台差異與支援範圍見
[`docs/profile-platform-support.md`](docs/profile-platform-support.md)。

## 驗證、安全與授權

工作流只有三個人工 Gate：PRD 核可、team 設計核可、發布核可。schema、
traceability、typecheck、lint 和 test 屬於機器 Gate，應由對應 command 留下結果。

`security/scripts/scan-secrets.sh` 是 heuristic secret preflight，使用
`CLEAR/FINDINGS/SKIP` 回報指定範圍。完整安全稽核還要另外執行 dependency audit、
auth/authorization review 與適用的高風險 operation guard。

push、merge、刪除、force 操作和外部發布都屬於不可逆操作，必須先讀 consuming
repo 的 guardrails。
delivery 仍需獨立授權與對應 evidence；work item 完成只記錄 requested work。

## 升級、檢查與移除

從 v0.6 升級時，先編輯 `.agent/project-manifest.md`。把 v0.6 template 中空的
`- profile:` 移除，改成明確的 `delivery_mode` 與 `capability_packs`；舊格式和新
格式不可並存。

確認 manifest 後，再由使用者把 submodule 切到已審查 revision：

```bash
git -C .agent/skills/_shared fetch --tags
git -C .agent/skills/_shared checkout v0.7.0

bash .agent/skills/_shared/bootstrap/manage.sh update
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

`manage.sh update` 只會重跑目前 checkout revision 的 onboarding；Git ref 由使用者
先行 fetch 與切換。pre-ledger 產物若已被修改，bootstrap 會拒絕直接接管；review
差異後才做一次明確 adoption：

```bash
SKILL_COMMONS_ADOPT_LEGACY=1 \
  bash .agent/skills/_shared/bootstrap/onboard.sh
```

本地管理介面：

```bash
bash .agent/skills/_shared/bootstrap/manage.sh doctor [project-root]
bash .agent/skills/_shared/bootstrap/manage.sh update [project-root]
bash .agent/skills/_shared/bootstrap/manage.sh uninstall [project-root]
```

`doctor` 是 read-only health check。`uninstall` 只移除 ledger-owned entries 與
managed adapter blocks，並保留 manifest、guardrails、submodule 和 foreign content。
若要縮減 platforms，先用舊 selection uninstall，再改 manifest 並重新 onboard。

### Troubleshooting

- Onboarding 因 selection 停止：確認 `delivery_mode`，不要用空的舊 `profile:`。
- `doctor` 回報 drift：先確認 submodule revision，再執行 `manage.sh update`。
- Legacy adoption 被拒絕：review 差異後，再決定是否執行一次明確 adoption。
- Plan 格式被拒絕：遷移到 canonical-v2，或在遷移完成前維持舊版 pin。

## 常用入口

| 想做的事 | 從這裡開始 |
|---|---|
| 任務分流 | `skill-router` |
| 需求探索或 PRD | `brainstorming`、`to-prd`、`prd-interview` |
| 技術規格或執行計畫 | `spec`、`plan-sync` |
| 實作、除錯、驗證 | `implement`、`systematic-debugging`、`verification-before-completion` |
| QA、review、安全預檢 | `qa`、`caveman-review`、`security` |
| Git 工作與 release handoff | `sync-work`、`finishing-a-development-branch` |
| Codebase inventory | `codebase-understanding` |
| 文件整理或文字修訂 | `markdown`、`humanizer` |
| 接入 consuming repo | `shared-skill-onboarder` |

完整清單見 [`INDEX.md`](INDEX.md)。

## Maintainer verification

修改 top-level skills 後，先做完整 fan-out，再跑 repository gates：

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/run-all.sh
```

進一步文件：

- [`CONTRIBUTING.md`](CONTRIBUTING.md)：貢獻與 skill lifecycle
- [`CHANGELOG.md`](CHANGELOG.md)：版本與 breaking changes
- [`ARTIFACTS.md`](ARTIFACTS.md)：work-item 與 Plan Sync 格式
- [`GATE-PACKAGE.md`](GATE-PACKAGE.md)：人工 Gate handoff
- [`SOURCES.md`](SOURCES.md)：外部來源、license 與 local patches
- [`docs/skill-commons-submodule-bridge.md`](docs/skill-commons-submodule-bridge.md)：submodule 接入細節
