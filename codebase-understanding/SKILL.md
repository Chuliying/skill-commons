---
name: codebase-understanding
description: |
  程式碼庫全局理解專家。Use when: (1) 進入大型 / 陌生 codebase, (2) 需要產出 architecture map, (3) 需要發現 domain skill 候選, (4) 重構前需要整理模組引用證據, (5) Code Review 需要確認影響範圍。互動式 knowledge graph 或 dashboard 僅在使用者明確要求時走 optional visualization。
  觸發關鍵字: 理解程式碼, codebase 分析, 架構圖, repo map, knowledge graph, 探索專案, 了解系統, 看看架構, understand
source_kind: original
stage: infra
---

# Codebase Understanding

以可重建的 Repo Map、repository search 與直接讀檔建立架構理解。Repo Map
是 deterministic repository evidence extractor，不是 knowledge graph，也不會
自動產生架構結論。

> **Announce at start:** 「我正在使用 codebase-understanding 來分析整體程式碼架構。」

## 適用邊界

適用：

- 陌生或大型 codebase 的 inventory 與 module-reference 初探。
- 產出或更新人工審核的 `.agent/knowledge/architecture-map.md`。
- Spec、debug、review 或 refactor 前確認相關檔案與引用候選。
- 找出可供 `shared-skill-onboarder` 深入驗證的重複模式候選。

不適用：

- 單一檔案或小型改動；直接讀檔與 `rg` 較快。
- 需要 symbol resolution、caller/callee、data flow 或精確 impact graph。
- 把 candidate edge 當成已解析 dependency。
- 自動建立 domain skill 或修改 architecture map。

## Requirements

預設路徑只需要：

- Git worktree。
- Python 3.10+ standard library。
- `rg`；缺少時使用 repo 可用的文字搜尋工具。

Repo Map 不使用 Node、network、LLM、daemon 或外部 parser。

## Repo Map CLI

以實際 skill 目錄解析 `scripts/repo_map.py`：

```bash
python3 <codebase-understanding-dir>/scripts/repo_map.py status --root .
python3 <codebase-understanding-dir>/scripts/repo_map.py scan --root .
```

`--root` 預設 `.`，只接受 Git worktree 內的 repo-relative directory。stdout
是一行 compact JSON；stderr 只放錯誤。Status JSON 會包含實際
`cache_path`，consumer 必須解析 JSON 的 `state`，不能只看 exit code：

- `0`：`fresh`。
- `1`：`missing` 或 `stale`。
- `2`：`corrupt`、`incompatible` 或 runtime failure。

`scan` 成功為 `0`，operational/contract failure 為 `2`。Coverage 與
freshness 分開：`fresh + partial` 是合法狀態。

Cache 位於：

```text
$(git rev-parse --git-path skill-commons/repo-map/v1)/
├── meta.json
├── inventory.jsonl
└── edges.jsonl
```

它是 Git-private、可重建 cache，不是 work-item artifact，也不應提交。

## Evidence semantics

Repo Map inventory 包含 Git tracked 與未 ignored 的 untracked paths。Symlink
不 follow，submodule 不遞迴；supported source 超過 2 MB 只 hash、不 parse。

- Python `.py` / `.pyi` import 使用 AST，precision 為 `syntax_exact`。
- JS/TS 使用 line-oriented literal specifier candidates，precision 永遠是
  `textual_candidate`。包含 `} from "x"` 這類 multiline tail；specifier
  自己拆到下一行時不保證命中。
- Edge kind 是 `module_reference`，不提供 resolved target，也不代表
  `depends_on`。
- Unsupported、syntax error、decode error、too-large 都會反映在 coverage，
  不得偽裝 complete。

Freshness 以 scoped inventory shape、supported source content 與 extractor
fingerprint 為準，不以 commit 狀態代替內容：

- bytes 不變的 `git add` 或 commit 不會使 cache stale。
- supported source content、path add/delete/rename 會 stale。
- unsupported file 內容改變不 stale；它的 add/delete/rename 會改 inventory，
  因此 stale。

`status` 每次仍需重 hash supported inputs，成本為 O(repo)。v1 保持 full
rebuild；若 pilot 證明需要加速，只允許 stat shortcut 加 content-hash fallback，
不引入 incremental parser/database。

## Process

### Step 1: 確認範圍與現有 evidence

1. 讀 manifest 的 source roots、`architecture_map` 與相關 domain skill。
2. 執行 [Graph Context Check](../graph-context-check.md)。
3. 若任務只需少量檔案，直接使用 `rg` 與讀檔，不必建立 cache。

### Step 2: 取得可信 Repo Map

1. 執行 `status --root <scope>` 並解析 JSON。
2. `missing` / `stale` 且任務值得完整掃描時，執行 `scan`；否則用搜尋
   fallback。
3. `corrupt` / `incompatible` 時可完整重建一次；仍失敗就回報並 fallback。
4. `partial` / `inventory_only` 時，只把 cache 用於其實際覆蓋面，缺口用
   repository search 與直接讀檔補足。

### Step 3: 建立架構理解

1. 從 inventory 找到 entry points、source roots、tests 與 configuration。
2. 用 module-reference edges 形成待驗證假設。
3. 對重要 edge 讀取實際 source；JS/TS candidate 一律用 `rg` 或 parser
   evidence 複核。
4. 不從 import count 推導 business importance，不聲稱 caller/callee 或 ripple
   impact。
5. 把已驗證的 ownership、boundary、data path 與 open questions整理成報告。

### Step 4: 更新 durable human artifacts

需要持久交接時，更新：

- `.agent/knowledge/codebase-understanding-report.md`：本次範圍、證據、限制與
  open questions。
- `.agent/knowledge/architecture-map.md`：只有人工/agent 複核過、仍長期有效
  的架構摘要。

Manifest 的既有 `architecture_map` 欄位保持指向
`.agent/knowledge/architecture-map.md`。Repo Map cache 不可填進該欄位。

## Optional visualization: Understand-Anything

只有使用者明確需要 interactive dashboard、guided tour 或 semantic exploration
時，才建議 optional
[Egonex-AI/Understand-Anything](https://github.com/Egonex-AI/Understand-Anything/tree/9d6f025dca0253ec85e115aa2d4cc87f7b642eca)
flow。來源、pin、license 與用途記在 [SOURCES.md](../SOURCES.md) 的 Optional
runtime adapters。

啟用前先取得使用者對 runtime、network、model/token cost 與資料政策的核可，
再依 pinned upstream 文件安裝。UA output 不參與 Repo Map freshness、不作
release gate；UA 無法使用時，只損失 visualization，預設理解流程仍使用 Repo
Map、`rg` 與直接讀檔。v1 不提供 UA adapter code 或 compatibility reader。

## Required output

在 calling report 保留 shared fragment 規定的 Graph Context line，不在此複製
值域。需要 durable report 時另記：

```text
Skill: codebase-understanding
Scope: <repo-relative root>
Repo Map: <state/coverage/cache path>
Evidence checked: <files and module-reference candidates>
Fallback: <rg/direct reading/N/A>
Architecture map: <updated/review-needed/N/A>
Limitations: <partial/unsupported/unresolved candidates>
```

只有本次工作真的建立或更新 durable architecture artifact 時，才要求把這段
寫入 report。分析結論必須區分 machine extraction、直接驗證與人工判斷。
