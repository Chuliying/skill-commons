# skill-commons

[![CI](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml/badge.svg)](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml)

skill-commons 是 AI 協作開發的 repository-native workflow kit。它把需求、Spec、Plan、實作狀態、驗證證據與交付授權留在 Git，讓開發者、Claude Code、Codex 與 Cursor 從同一份最新工作狀態接手。[English summary](README.en.md) · [Quick Start](#quick-start) · [References](#references)

## 專案範疇

產品是一份可驗證、可接續的共享工程狀態：Spec 是施工圖，Plan 是施工順序，`meta.yml` 是進度板，測試與 review 是驗收證據，Git 保存變更歷史。適合跨 session、agent、工具、開發者或正式 review gate 的工作；事實查證與 bounded micro-task 由 Router 走最短路徑，避免額外文件。Spec drift 與交接邊界的完整模型見 [Spec-state protocol](docs/spec-state-protocol.md)。

上游生態（[Agent Skills](https://agentskills.io/specification)、[Superpowers](https://github.com/obra/superpowers)）解決可攜技能與開發方法；本專案在其上補足共享契約——repository artifact、Plan、evidence 與 delivery contract。外部來源、pinned commit 與本地 patch 見 [SOURCES.md](SOURCES.md)。

## 專案能力

| 能力 | 一句話 | 怎麼做到 |
|---|---|---|
| 任務路由 | Router 依單一任務選最小 execution mode 與 artifact 集合，清楚的小修改走直接路徑 | [skill-router](skill-router/SKILL.md) |
| 持久交接 | dependencies、blockers、DoD 與 evidence 存活於 `docs/work/<slug>/`，第二個 session 從 repository 狀態接手 | [plan-sync](plan-sync/SKILL.md) · [Spec-state protocol](docs/spec-state-protocol.md) |
| 狀態入口 | `project-status` 唯讀、deterministic、no-LLM，回報狀態、attention 與下一步 | [ARTIFACTS.md](ARTIFACTS.md) |
| 跨 repo 偵測 | 任務依賴本 repo 之外的工作時偵測並停下確認，participant 記錄於 Plan，evidence 留在原 repo | [Cross-repo contract](docs/cross-repo-contract.md) |
| 跨工具安裝 | top-level skills 單一來源，onboarding 產生各平台 adapters；skill fan-out 僅及 Claude Code 與 Codex，Cursor 走 rule + AGENTS adapter；consuming repo 以 submodule pin 版本 | [Bootstrap](bootstrap/README.md) · [Platform support](docs/profile-platform-support.md) |
| 交付授權 | 工作完成與對外交付分開記錄；push、merge、discard、destructive recovery 與 publication 前需明確授權 | [ARTIFACTS.md](ARTIFACTS.md) · [sync-work](sync-work/SKILL.md) |

`delivery_mode` 是安裝時選擇的技能組合（`personal`、`team-sprint`，外加 `frontend`、`optional` capability packs）；`execution_mode` 是 Router 依單一任務決定的執行方式，無需手動設定。逐技能對應見 [INDEX.md](INDEX.md)，需求探索見 [Discovery and planning](docs/discovery-and-planning.md)。

## 驗收

| 層級 | 驗了什麼 | 如何驗 |
|---|---|---|
| Composition | source、generated adapters、profiles、provenance | [INDEX](INDEX.md) · [SOURCES](SOURCES.md) |
| Contract | work-item、registry、Plan、artifact、links、delivery evidence | [Cross-repo contract](docs/cross-repo-contract.md) |
| Behavior | unit/integration/e2e、bootstrap safety、security、release convergence | [Evaluation](docs/evaluation.md) |
| Agent journey | isolated personal/team/bug/refactor/release scenarios | [Journey evals](journey-evals/README.md) |

完成宣稱需要 fresh verification evidence，且每個完成的工作記錄一筆 documentation impact。PRD 核可、team 設計核可、發布核可是三個 workflow human gates；push、merge、discard、destructive recovery 與 publication 執行前需要明確授權。Deterministic gates 證明被測 revision 的 repository contracts 一致；團隊速度、模型品質、token 成本與跨工具接手價值仍需獨立實驗，claim limits 見 [Evaluation and evidence](docs/evaluation.md)。

Maintainer 全量驗證（commit、tag、push、PR、merge 與 publication 需要另外授權）：

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/verify.sh
```

## Quick Start

需要 Git、Bash 3.2+；Claude Code settings merge 需要 `jq`；完整 verification 需要 Python 3.10+；onboarding scan 需要 Node.js 18+。

```bash
git submodule add git@github.com:Chuliying/skill-commons.git .agent/skills/_shared
git -C .agent/skills/_shared checkout v0.9.0
mkdir -p .agent
cp .agent/skills/_shared/shared-skill-onboarder/templates/project-manifest.md \
  .agent/project-manifest.md
```

在 manifest 選擇 platforms、恰好一個 `delivery_mode`，並先把 `optional` 加到 `capability_packs`（若需要探索、review 或 onboarding skills）：

```yaml
## skill-commons bootstrap
- submodule_path: .agent/skills/_shared
- platforms: claude-code, cursor, codex
- delivery_mode: personal
- capability_packs: optional
```

```bash
bash .agent/skills/_shared/bootstrap/onboard.sh
bash .agent/skills/_shared/bootstrap/manage.sh doctor
```

## 安裝完成後

直接用自然語言交代任務，例如「幫我加入匯出 CSV，完成前執行驗證」，Router 會選最短流程。需要狀態摘要時執行：

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
```

Submodule 缺失、selection 錯誤、doctor drift、uninstall 與 legacy adoption 等維運流程見 [Submodule bridge](docs/skill-commons-submodule-bridge.md) 與 [Bootstrap](bootstrap/README.md)。

## References

- 使用：[Bootstrap](bootstrap/README.md) · [Submodule bridge](docs/skill-commons-submodule-bridge.md) · [Platform support](docs/profile-platform-support.md) · [Skill index](INDEX.md)
- 契約：[Spec-state protocol](docs/spec-state-protocol.md) · [Artifacts](ARTIFACTS.md) · [Cross-repo contract](docs/cross-repo-contract.md) · [Discovery/plan](docs/discovery-and-planning.md)
- 證據：[Evaluation](docs/evaluation.md) · [Journey evals](journey-evals/README.md)
- 來源：[SOURCES](SOURCES.md) · [Agent Skills spec](https://agentskills.io/specification) · [Superpowers](https://github.com/obra/superpowers)
- 維護：[CONTRIBUTING](CONTRIBUTING.md) · [CHANGELOG](CHANGELOG.md) · [STYLE](STYLE.md) · [Gate package](GATE-PACKAGE.md) · [Decisions](docs/skills-reorg/decisions.md)
