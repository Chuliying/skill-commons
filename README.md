# skill-commons

[![CI](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml/badge.svg)](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml)

skill-commons 是給 AI 協作開發使用的 repository-native workflow kit。它把需求、Spec、
Plan、實作進度與驗證證據留在 Git，讓開發者、Claude Code、Codex 與 Cursor 從同一份
最新工作狀態接手。

你可以直接用自然語言交代任務。Router 選擇最短可行流程，需要跨 session 交接的狀態
寫進 repository。`v0.9.0` 新增 `project-status`，用一個唯讀、可重現且不使用 LLM 的
入口整理目前狀態與下一步。

[English](README.en.md) · [Spec-state protocol](docs/spec-state-protocol.md) ·
[Evaluation](docs/evaluation.md) · [Skill index](INDEX.md)

## 核心價值

產品核心是可驗證、可接續的共享工程狀態。Spec 是施工圖，Plan 是施工順序，
`meta.yml` 是進度表，測試結果是驗收報告，Git 保存變更歷史。下一位協作者可以回答：

- 現在要做什麼，完成條件是什麼；
- 上一個 session 做到哪裡，有哪些 blocker；
- 規格是否改變，舊 Plan 或 evidence 是否仍有效；
- 完成、PR、merge 與 deployment 各自有什麼證據。

`project-status` 讀取 bootstrap、work-item、Plan 與 Git 狀態，回報需要注意的地方和
下一個動作。它不修改專案，也不猜哪一個 active work item 應該優先。

完整模型與利害關係見 [Spec-state protocol](docs/spec-state-protocol.md)。

## 什麼時候值得用

- 工作跨 session、Agent、工具或開發者。
- 團隊需要 PRD、Spec、Plan、QA 與 release handoff 的共同格式。
- Reviewer 需要從完成宣稱回到實際 command 和 artifact。
- 同一 repository 同時支援 Claude Code、Codex 或 Cursor。

事實查證和邊界清楚的 micro-task 走最短路徑，不建立多餘文件。探索與規劃的路徑選擇
見 [Discovery and planning](docs/discovery-and-planning.md)。

## Quick Start

需要 Git、Bash 3.2+；Claude Code settings merge 需要 `jq`。Plan Sync、Repo Map 和
完整 maintainer verification 需要 Python 3.10+；onboarding scan 需要 Node.js 18+。

### 1. 固定版本

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.9.0
```

### 2. 選擇技能組合

```bash
mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
${EDITOR:-vi} .agent/project-manifest.md
```

Personal 起點：

```yaml
## skill-commons bootstrap

- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs: # 需要時填入 frontend 或 optional
```

`delivery_mode` 必須是 `personal` 或 `team-sprint`。需要前端、探索、個人 PRD、review
或 onboarding 時，再加入 `frontend` 或 `optional` capability pack。未選 delivery mode
時 onboarding 會停止。

`v0.9.0` 安裝目前的七技能核心組合。需要探索、個人 PRD、review 或 onboarding 時，
先把 `optional` 加到 `capability_packs`，再執行 onboarding。尚未遷移的專案可維持
`v0.7.1` legacy pin；版本差異與遷移步驟見 [Bootstrap](bootstrap/README.md)、
[Profile support](docs/profile-platform-support.md) 和
[Submodule bridge](docs/skill-commons-submodule-bridge.md)。

### 3. 安裝並檢查

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

未選擇 optional pack 時，不要要求 agent 讀未安裝的 optional 技能。

### 4. 讀取專案狀態

在 consuming repository 根目錄執行：

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
```

一般輸出給人閱讀；`--json` 提供穩定的 machine-readable schema。兩者都只讀取
bootstrap health、work-item、canonical Plan、Git working tree 與 active-work 歧義。

## 安裝完成後

直接用自然語言交代任務即可。例如「幫我加上匯出 CSV 功能」，Router 會選擇最小工作
流程；需要跨 session 接手時，相關狀態會寫進 `docs/work/<slug>/`。想明確指定技能時，
可以說「使用 `implement` 實作」或「使用 `sync-work` 保存進度」。完整清單見
[INDEX.md](INDEX.md)。

## 執行模型

Router 依任務選擇探索、建造、修錯、理解或發布流程。工作需要跨 session 接續時，
Plan 與 evidence 留在 `docs/work/<slug>/`；完成後仍需明確授權才會進入 Git delivery。

| 選擇 | 用途 |
|---|---|
| `personal` | 實作、除錯、驗證、安全與 Git delivery；少量 durable artifacts |
| `team-sprint` | 加入正式 PRD、Spec、QA、prototype 與 domain modeling |
| `frontend` pack | 前端設計能力 |
| `optional` pack | 探索、個人 PRD、review、onboarding 與 utilities |

`delivery_mode` 是安裝時選擇的技能組合；
`execution_mode` 是 Router 依單一任務決定的執行方式，不需要手動設定。它會決定該任務
需要哪些文件。工作狀態與 delivery 狀態
分開；完整格式見 [Artifact contract](ARTIFACTS.md)，平台差異見
[Profile and platform support](docs/profile-platform-support.md)。

## 信任與授權邊界

- 完成宣稱需要 fresh verification evidence。
- PRD 核可、team 設計核可、發布核可是三個人工 Gate。
- `work_status` 不代表 PR、merge 或 deployment 已發生。
- push、merge、刪除、force、discard 與外部發布需要執行前明確授權。
- Secret preflight 是範圍化 heuristic；dependency、auth 和高風險 operation review
  仍是獨立檢查。
- Top-level skills 是唯一 source of truth；`.claude/skills/`、`.codex/skills/` 與
  `.agents/skills/` 只由 generate fan-out。

## 已驗證與尚未驗證

Maintainer gate 會檢查 source、generated adapters、artifact／Plan／profile 契約、
bootstrap safety、secret preflight 與 clean public export。`bash tests/run-all.sh` 是目前
的完整 release gate。

這些檢查證明 repository contract 一致，尚未證明團隊速度、模型輸出品質或跨工具接手
體驗有所改善。缺少 private replay artifacts 的歷史 benchmark 數字只保留為未驗證
敘述。下一個產品實驗是無聊天紀錄的跨 session／跨工具冷啟動接手與 Spec drift
偵測；方法、數據與限制見 [Evaluation](docs/evaluation.md)。

## 文件入口

| 主題 | 文件 |
|---|---|
| Spec continuity 與協作者利益 | [Spec-state protocol](docs/spec-state-protocol.md) |
| Discovery、Research、Plan 與 testing seam | [Discovery and planning](docs/discovery-and-planning.md) |
| 測試、benchmark 與 claim boundary | [Evaluation](docs/evaluation.md) |
| Skills 與 profiles | [INDEX.md](INDEX.md) |
| Work item 與 lifecycle | [ARTIFACTS.md](ARTIFACTS.md) |
| 安裝、update、doctor、uninstall | [Bootstrap](bootstrap/README.md) |
| 平台支援與版本相容邊界 | [Profile support](docs/profile-platform-support.md) |
| 版本演進與貢獻 | [CHANGELOG.md](CHANGELOG.md) · [CONTRIBUTING.md](CONTRIBUTING.md) |

## Maintainer verification

修改 top-level source、profile、contract 或公開文件後：

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/run-all.sh
```

Release、push、PR、merge、tag 與 publication 仍需另外授權。
