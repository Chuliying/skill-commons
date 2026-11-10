# skill-commons

**English readers: see [README.en.md](README.en.md).**

[![CI](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml/badge.svg)](https://github.com/Chuliying/skill-commons/actions/workflows/ci.yml)

skill-commons 是 AI 協作開發的 repository-native workflow kit。它把需求、Spec、Plan、實作狀態、驗證證據與交付授權留在 Git，讓開發者、Claude Code、Codex 與 Cursor 從同一份最新工作狀態接手。

它多做的一件事：**「完成」與「核准」只在它們涵蓋的內容沒變時成立。**項目通過驗證之後改了程式，驗證就變成過期；有人核准驗收條件之後改了那條條件，核准就變成過期。`project-status` 會對已完成、尚未交付的工作項目，以及已記錄證據的進行中項目，指出這些變化，不必重跑測試。

[English](README.en.md) · [互動 Repo Map](https://skill-commons-map.vercel.app) · [Quick Start](#quick-start) · [References](#references)

## 專案範疇

產品是一份可驗證、可接續的共享工程狀態：Spec 是施工圖，Plan 是施工順序，`meta.yml` 是進度板，測試與 review 是驗收證據，Git 保存變更歷史。適合跨 session、agent、工具、開發者或正式 review gate 的工作；事實查證與 bounded micro-task 由 Router 走最短路徑，避免額外文件。Spec drift 與交接邊界的完整模型見 [Spec-state protocol](docs/spec-state-protocol.md)。

上游生態（[Agent Skills](https://agentskills.io/specification)、[Superpowers](https://github.com/obra/superpowers)）解決可攜技能與開發方法；本專案在其上補足共享契約——repository artifact、Plan、evidence 與 delivery contract。外部來源、pinned commit 與本地 patch 見 [SOURCES.md](SOURCES.md)。

比較結果：2026 年 10 月的一份事先登記實測（一個 Python 小工具、一個功能，「完成」之後改一行程式、改一句驗收條件）中，SpecWeave 3.1.15 的狀態在兩種改動後仍顯示 Completed，Spec Kit 1.2.5 的狀態指令沒有顯示每個項目的狀態。SpecWeave 重跑 `verify` 時會抓到程式改動，Spec Kit 其中一次實測的 LLM convergence 步驟也標出了兩種改動；這裡測的差別在於：重新執行狀態指令時，不必重跑測試或 LLM 評估，就能標出過期。兩者的核心流程都沒有產生包含核准人、範圍與內容指紋的核准紀錄（Spec Kit 選用的 review gate 沒有實測；SpecWeave 會在任務證據記錄 commit SHA）。在 commit `6f7ae22`，skill-commons 三次紀錄都標出了兩種改動，其中兩次完成規定的安裝，第三次的安裝結果無法判定。較早的版本在這份實測中有部分沒通過，依結果修正；對手的實測沒有重跑。2026 年 11 月又對兩個代理驗證工具各跑一次同一份實測：Lians 0.5.0 在程式改動後也標成過期，但工作區任何改動都會觸發，包括驗收條件以外的一句話；ProofFlow v0.1.8 在測試已經失敗後仍顯示 `ready_for_review`，因為它讀的是代理記錄的內容。細節見 [Evaluation](docs/evaluation.md#competitor-comparison-october-2026)。

依內容判斷審查是否仍有效是既有做法，例如 [Doorstop 的 suspect link](https://doorstop.readthedocs.io/en/v3.2/cli/validation.html) 與 [GitHub 撤銷過期核准](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)。skill-commons 把它用在 agent 的工作項目與驗收條件上。SpecWeave 也會記錄哪個 agent 在何時認領任務，工具與時間紀錄是雙方都有的能力。

## 專案能力

| 能力 | 一句話 | 怎麼做到 |
|---|---|---|
| 完成隨內容過期 | 驗證證據記錄被驗證檔案與驗收條件的指紋；已完成、尚未交付的工作項目之後改了就顯示過期，沒有或未通過的證據會列為 attention | [verification](verification-before-completion/SKILL.md) · [ARTIFACTS.md](ARTIFACTS.md) |
| 核准綁定內容 | `approve` 記錄誰核准了哪些驗收條件及其指紋，以及是人在終端機確認、還是代理代為記錄，改了條件核准就過期（空白會合併、標點視為斷字；`reaffirm` 可附理由接受修改並留下紀錄） | [ARTIFACTS.md](ARTIFACTS.md) |
| 一張清單管理所有工作 | `project-status.sh --ledger` 列出每個工作項目（含待辦）的 stage 檔案、適用時的驗證與核准狀態，以及最後一次活動的 AI 工具與 session；`--ledger --json` 有完整的逐指令紀錄 | [ARTIFACTS.md](ARTIFACTS.md) |
| 允許修改的範圍 | 工作項目 `meta.yml` 可選填 `allowed_paths`；`verify.sh --work-item` 與 `project-status` 會列出項目開始後範圍外的改動，包括被提交的 `__pycache__` | [ARTIFACTS.md](ARTIFACTS.md) |
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

已知限制：在實測的全新雙 agent repo 中，安裝新增六個根目錄項目（內含 submodule 的 `.agent/`、`.gitmodules`、`.claude/`、`.agents/`、`AGENTS.md`、`CLAUDE.md`），repo 原本沒有 `.gitignore` 時再加一個；安裝新增 8 個 Git 追蹤項目（含 submodule gitlink，加上原有的兩個檔案共 10 個）。安裝後磁碟共有 466 個檔案；只裝 Claude 的 Spec Kit 新增兩個。數量依選擇的平台而定。AI 工具與 session 是 agent 環境回報的資料（Cursor 不回報 session），核准會記錄是人在終端機確認、還是 agent 代為記錄；能取得終端機並清除 agent 環境變數的程序仍可記成 `terminal`，所以兩者都不能當作身分驗證。核准涵蓋驗收條件的文字，程式由驗證涵蓋。產生的檔案與第一次使用路徑是英文；部分已安裝的技能（包括 `security`）仍有繁體中文。有一次雲端實測的 onboarding 沒有輸出就停止，無法重現；第二個指令之後請確認 `AGENTS.md` 已產生。另一次全新雲端 clone 沒有初始化 submodule。本機實測則在技能探索後才由 hook 補檔。首次開啟 Claude Code 前的準備步驟見[安裝指南](docs/skill-commons-submodule-bridge.md#layout)。

Maintainer 全量驗證（commit、tag、push、PR、merge 與 publication 需要另外授權）：

```bash
PROFILE=all bash bootstrap/generate.sh
bash tests/verify.sh
```

## Quick Start

需要 Git 與 Bash 3.2+；Claude Code 平台需要 `jq`。`project-status`、`work-items` 與驗證證據需要 Python 3.10+；onboarding scan 另需 Node.js 18+。在你的專案根目錄執行兩個指令：

```bash
git submodule add https://github.com/Chuliying/skill-commons.git .agent/skills/_shared
bash .agent/skills/_shared/bootstrap/onboard.sh
```

不需要 SSH key，也不會詢問問題。第一次執行會建立預設 manifest（`personal` 加 `optional` 技能包；平台依 repo 既有的 `.claude`、`.codex`、`.cursor` 判斷，都沒有時為 Claude Code 與 Codex），從專案檔案推導測試指令與原始碼目錄，並寫入 `.agent/`、各平台的技能目錄、`AGENTS.md` 與只引用 `AGENTS.md` 的 `CLAUDE.md`。技能目錄是產生出來的副本：onboard 會在 `.gitignore` 逐一列出產生的檔案。初始化 submodule（`git submodule update --init`）後，啟動檢查可依已提交的 manifest 與現有忽略規則重新產生副本（Codex 請照 `AGENTS.md` 先執行 `check.sh`）。較早的安裝會提交副本，一次 commit 的遷移步驟見 [bridge 文件](docs/skill-commons-submodule-bridge.md)。開始第一項工作：`bash .agent/skills/_shared/scripts/work-items.sh new <slug>`。Submodule 固定在加入當下的 commit。

### 進階設定

- 固定在發布版本：`git -C .agent/skills/_shared checkout v0.13.1`，再重跑 `onboard.sh`。這裡介紹的內容綁定驗證、核准、清單與工作項目指令在 `v0.13.1` 提供。
- 調整平台、`delivery_mode` 或 capability packs：編輯產生的 `.agent/project-manifest.md`，再重跑 `onboard.sh`。以下是三個平台都啟用的例子；只要最少技能時，移除 `optional`：

```yaml
- submodule_path: .agent/skills/_shared
- platforms: claude-code, codex, cursor
- delivery_mode: personal
- capability_packs: optional
```

- 確認安裝狀態：`bash .agent/skills/_shared/bootstrap/manage.sh doctor`。

## 安裝完成後

直接用自然語言交代任務，例如「幫我加入匯出 CSV，完成前執行驗證」，Router 會選最短流程。安裝產生的 `AGENTS.md` 已列出 agent 會用到的指令；每個指令對應一個階段，在專案根目錄執行：

```bash
S=.agent/skills/_shared
bash "$S/scripts/work-items.sh" new export-csv            # 建立 meta.yml、PRD 骨架與報告骨架
bash "$S/scripts/work-items.sh" new later-idea --queued   # 待辦
bash "$S/scripts/work-items.sh" start later-idea          # 開始做待辦時
# 填好 PRD、以測試實作之後：
bash "$S/verification-before-completion/scripts/verify.sh" --work-item export-csv
# 由對方在自己的終端機執行並輸入 yes；沒有 shell 可交給對方時，代理改加
# --by user:sam --agent-reported --quote "<對方的原話>"
python3 "$S/scripts/verification_evidence.py" approve --work-item export-csv
bash "$S/scripts/work-items.sh" complete export-csv --na "沒有專案文件需要更新"
bash "$S/verification-before-completion/scripts/verify.sh" --work-item export-csv
```

有更新專案文件時，用 `complete ... --doc README.md` 取代 `--na`。

需要狀態摘要時執行：

```bash
bash .agent/skills/_shared/scripts/project-status.sh
bash .agent/skills/_shared/scripts/project-status.sh --json
bash .agent/skills/_shared/scripts/project-status.sh --ledger   # 一項一列：stage、驗證、核准、AI 工具與 session
```

Submodule 缺失、selection 錯誤、doctor drift、uninstall 與 legacy adoption 等維運流程見 [Submodule bridge](docs/skill-commons-submodule-bridge.md) 與 [Bootstrap](bootstrap/README.md)。

## 貢獻者

- [Chuliying](https://github.com/Chuliying)：維護者
- [Renee Wang（@ItsReneeWang）](https://github.com/ItsReneeWang)：設計並實作 production prototype 技能組，prototype 契約改造時作為參考

## References

- 使用：[Bootstrap](bootstrap/README.md) · [Submodule bridge](docs/skill-commons-submodule-bridge.md) · [Platform support](docs/profile-platform-support.md) · [Skill index](INDEX.md)
- 契約：[Spec-state protocol](docs/spec-state-protocol.md) · [Artifacts](ARTIFACTS.md) · [Protocol registry](protocol-registry.json) · [Cross-repo contract](docs/cross-repo-contract.md) · [Discovery/plan](docs/discovery-and-planning.md)
- 證據：[Evaluation](docs/evaluation.md) · [Journey evals](journey-evals/README.md) · [互動 Repo Map](https://skill-commons-map.vercel.app)
- 來源：[SOURCES](SOURCES.md) · [Agent Skills spec](https://agentskills.io/specification) · [Superpowers](https://github.com/obra/superpowers)
- 維護：[CONTRIBUTING](CONTRIBUTING.md) · [CHANGELOG](CHANGELOG.md) · [STYLE](STYLE.md) · [Gate package](GATE-PACKAGE.md) · [Decisions](docs/skills-reorg/decisions.md)
