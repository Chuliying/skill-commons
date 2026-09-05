# 跨 repo artifact 契約與檢查

這份文件說明 skill-commons 用什麼契約讓工作產出跨 repo、跨 agent、跨 session 可讀，
以及有哪些檢查在守住它、怎麼執行。給維護者與接入這套流程的人看。

契約本身的欄位定義在 [`../ARTIFACTS.md`](../ARTIFACTS.md)；為什麼需要它、解決什麼
問題寫在 [`spec-state-protocol.md`](spec-state-protocol.md)。本文只講**機器契約與
它的檢查**。

## 契約的機器來源

[`../protocol-registry.json`](../protocol-registry.json) 是 Execution Mode 與
work-item 生命週期的**唯一機器來源**。它是宣告式契約，不含 runtime、state machine
或 scheduler。`scripts/work_items.py` 在 import 時載入它，所以驗證規則與文件不會
各自漂移。

三個 `non_goals` 約束的對象是 registry 本身。`scripts/check_protocol_registry.py` 除了要求這三個字串存在，還會走訪 registry 的所有 key，出現 `commands`、`handlers`、`runtime_steps`、`scheduler_config` 四個名稱之一就報錯。三者的理由各自不同：

- `runtime-engine`：契約要能被 Claude Code、Codex 與其他 harness 共用。registry 內建執行引擎會迫使接入方改跑它的引擎，可攜性消失。advisory execution 與 deterministic resume 在 `orchestration/execution.py`，與 registry 分開。
- `state-machine`：registry 列舉 delivery 狀態並宣告每個狀態的證據形狀，不編碼也不驅動狀態轉換。`scripts/work_items.py` 的 `validate_delivery` 只檢查當前狀態該有的證據欄位與 `work_status` 相容性，不比對前後狀態或推進順序，`awaiting_approval` 也不要求任何證據。registry 另建狀態機等於第二個真相來源，正是上一段要避免的漂移。
- `scheduler`：事件觸發與排程綁定 CI、權限與環境分級，屬消費端 repo 或平台的職責，registry 不驅動也不排程。

registry 宣告三件事：

| 宣告 | 內容 |
|---|---|
| `execution_modes` | 四個模式（`team-feature`、`personal-feature`、`bug-fix`、`refactor`）各自的 artifact 需求：`required`、`optional`、`absent` |
| `work_statuses` | `active`、`completed`、`abandoned` |
| `delivery_statuses` | `not_requested` 到 `deployed`，以及每個狀態**允許**與**必須**具備的證據 |

work-item v3 把「工作做完了」與「交付出去了」分成兩個欄位。這是刻意的：
`work_status: completed` 只說程式碼與驗證完成，`delivery_status` 才記錄對外發生了
什麼，而每個對外狀態各自宣告精確的證據 shape，部分欄位延續、部分欄位在後續狀態
消失——`approved` 要 `approval_ref`，`pr_created` 要 `approval_ref` 與 `pr_url`，
`merged` 要 `approval_ref` 與完整 `merge_sha`（不允許 `pr_url`），`deployed` 要
`approval_ref`、`merge_sha` 與 `deployment_id`；`awaiting_approval` 不允許也不
要求任何證據。本地 commit 或一次被擋下的 PR 都不構成推進。

分開的理由是：合併成單一 `status` 時，「已完成」會被讀成「已交付」，而交付是不可逆
且對外可見的動作。

## 跨 repo participant

有些任務要另一個 repo 才做得完。canonical-v2 plan 的 `## Sources` 用第四種 typed
reference 把那個 repo 記進契約：

```text
- repo: <identifier>@<相對於 workspace root 的路徑>
```

`identifier` 是這份 plan 對該 repo 的穩定稱呼；路徑相對 workspace root，所以 plan 換
一個 checkout 仍然可讀。絕對路徑、解析回本 repo 的路徑、不存在或非目錄的路徑，以及重複
的 identifier 都被拒絕。

宣告的時機是 authoring：`plan-sync` 要求撰寫任務時確認它依賴的東西在本 repo 都拿得到，
拿不到就停下來問使用者另一個 repo 在哪，把答案記成 `repo:` source 之後才繼續。不猜
participant 路徑，也不把任務悄悄縮到本 repo 拿得到的那一半——被縮小的任務正是這項偵測
要防的失敗。

宣告 participant 只放寬 Sources。`local:` source 可以解析到已宣告的 participant 內
（symlink 解析後也必須留在該 participant 內），但 verification evidence 永遠不離開提出
主張的那個 repo；宣告 participant 不會讓外部 evidence 變得合法，`plan-sync` 的一致性
檢查會直接說明這條規則。

`scripts/project_status.py` 與 `planctl status` 只把已宣告的 participant 當彙總狀態
報出來：排序後的 identifier，不洩漏絕對路徑。兩者都不進入 participant repo，不在裡面
執行、clone 或寫入任何東西。

## 檢查

每一項都是機器閘門，不是慣例。全部由 `bash tests/verify.sh` 涵蓋。

| 檢查 | 保證什麼 | 單獨執行 |
|---|---|---|
| work-item 契約 | metadata 符合 registry；stage 的 `skill` 必須是真實技能資料夾；交付證據與 `delivery_status` 相符 | `bash scripts/work-items.sh check` |
| protocol registry | registry 自身 schema 與 non-goals 未被違反 | `python3 scripts/check_protocol_registry.py` |
| skill inventory | 每個 fan-out 產物與 top-level 來源逐檔一致 | `python3 scripts/check-skill-inventory.py` |
| 文件 | 術語與風格符合 [`../STYLE.md`](../STYLE.md)；不驗證連結是否可解析 | `bash scripts/lint-docs.sh` |
| PRD 形狀 | PRD 依 tier 具備 FR/AC/ERR 且無殘留 placeholder | `python3 scripts/check-prd.py --prd <路徑> --tier <tier>` |
| AC 追溯 | 每個 AC 都對應到 TC | `python3 qa/scripts/check-traceability.py --prd <路徑> --qa-plan <路徑>` |
| secret 預檢 | worktree 與 staged 內容、log 衛生、`.env` ignore 狀態 | `bash security/scripts/scan-secrets.sh` |

如有文件連結變更，另行執行適用的連結檢查。

產品邊界由 retained-roots whitelist 與 reference journeys 守住，不維護 byte
基準；whitelist 漏掉的 root 會讓對應的 journey 失敗而被抓出來，不會靜默保留。
whitelist 與 journeys 的契約記錄在私有開發紀錄
`docs/work/contract-source-reduction/contract-decision.md`。

## 執行

唯一入口是 canonical runner：

```bash
bash tests/verify.sh
```

它**探索** suites（`tests/test_*.sh` 與 `tests/bootstrap/test_*.sh`）而非讀硬編
清單，所以新增測試不會靜默不跑；python 分層也在同一入口。`tests/run-all.sh` 是
轉呼叫的相容 shim。

只跑局部時用 roster 檔，不要另外寫一個 runner：

```bash
printf 'suite tests/test_work_items.sh\n' > /tmp/roster
VERIFY_ROSTER_FILE=/tmp/roster bash tests/verify.sh
```

`bash tests/verify.sh --list` 印出實際 roster 而不執行。

## 單一 repo 的使用成本

接入這套契約不會增加單一 repo 的日常負擔，因為契約只在 artifact 落檔時生效：

- 接入是一個指令：`bash .agent/skills/_shared/bootstrap/onboard.sh`。
  `DELIVERY_MODE` 有預設值（`personal`），只有維護者直接呼叫
  `bootstrap/generate.sh` 時才需要指定。
- personal 與 bug-fix 模式的 `spec`、`qa-plan`、`qa-report` 都是 `absent`。
  這些模式不會被要求產出它們，也不會因為缺少而失敗。
- micro-task 直達路徑不建立 plan。
- 交付證據只在真的要對外交付時才需要；`delivery_status: not_requested`
  是合法且常見的終態。

換句話說，重的部分（PRD、Spec、QA plan、交付證據）只在 `team-feature` 出現，
其餘模式付的成本是一份 `implement-report.md`。

## 邊界

`docs/work/**` 與 `docs/STATUS.md` 是私有開發紀錄，由 `.gitattributes`
`export-ignore` 排除在公開 payload 之外。維護者專用的測試 suite 同樣如此宣告，
所以公開 payload 的 roster 會自然變小，不需要 runner 另外判斷。公開/私有邊界
只宣告在 `.gitattributes` 一處。
