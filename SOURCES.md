# External Skill Sources (Provenance)

依 ADR-002（`docs/skills-reorg/decisions.md#adr-002`）管理 vendored 與 adapted 外部技能來源。
vendored 更新流程：`npx skills update <skill>` → 重新 vendor → 重套下列 local patches → 更新本表 commit；adapted 技能則以 pinned commit 做人工 diff 後重套本地契約。

| Skill | Source (owner/repo@skill) | Pinned commit | Kind | Stage | Install size | License |
|---|---|---|---|---|---|---|
| skill-creator | `anthropics/skills@skill-creator` | `9d2f1ae18723` | adapted | skill | — | Apache-2.0 |
| brainstorming | `obra/superpowers@brainstorming` | `d884ae04edeb` | adapted | docs | — | MIT |
| finishing-a-development-branch | `obra/superpowers@finishing-a-development-branch` | `d884ae04edeb` | adapted | infra | — | MIT |
| subagent-driven-development | `obra/superpowers@subagent-driven-development` | `d884ae04edeb` | adapted | infra | — | MIT |
| grilling _(dep)_ | `mattpocock/skills@grilling` | `2454c95dc305` | vendored | plan | — | MIT |
| domain-modeling _(dep)_ | `mattpocock/skills@domain-modeling` | `2454c95dc305` | vendored | plan | — | MIT |
| to-prd | `mattpocock/skills@to-prd` | `2454c95dc305` | vendored | docs | 241K | MIT |
| design-taste-frontend | `leonxlnx/taste-skill@design-taste-frontend` | `5285855df671` | vendored | design | 158K | MIT |
| reducing-entropy | `softaworks/agent-toolkit@reducing-entropy` | `3027f20f3181` | vendored | implement | 3.7K | MIT |
| caveman-review | `juliusbrussee/caveman@caveman-review` | `25d22f864ad6` | vendored | review | 166K | MIT |
| humanizer | `blader/humanizer@humanizer` | `1b48564898e9` | adapted | docs | — | MIT |

## Optional runtime adapters

Optional adapters are not vendored, installed, or executed by default. Their
upstream code and schemas are not part of skill-commons.

| Adapter | Source | Pinned commit | License | Purpose |
|---|---|---|---|---|
| Understand-Anything | `Egonex-AI/Understand-Anything` | `9d6f025dca0253ec85e115aa2d4cc87f7b642eca` | MIT | Explicit interactive visualization, guided tour, or semantic exploration only |

`codebase-understanding` uses the local Repo Map contract by default. Enabling
Understand-Anything requires an explicit user decision and review of its pinned
upstream installation/runtime requirements; it is never a freshness authority
or release gate.

## Credits

MIT 授權要求重製時保留原始版權聲明，完整列在這裡（依來源 repo 的 LICENSE 檔）：

- **mattpocock/skills**（`grilling`, `domain-modeling`, `to-prd`；淘汰入口保留於 private development repository 的 `_archive/`）— Copyright (c) 2026 Matt Pocock
- **leonxlnx/taste-skill**（`design-taste-frontend`）— Copyright (c) 2026 Leonxlnx
- **softaworks/agent-toolkit**（`reducing-entropy`）— Copyright (c) 2026 Leonardo Flores
- **juliusbrussee/caveman**（`caveman-review`）— Copyright (c) 2026 Julius Brussee
- **blader/humanizer**（`humanizer`）— Copyright (c) 2025 Siqi Chen
- **anthropics/skills**（`skill-creator`）— Apache-2.0；完整授權文字保留於 `skill-creator/LICENSE.txt`
- **obra/superpowers**（`brainstorming`, `finishing-a-development-branch`, `subagent-driven-development`）— Copyright (c) 2025 Jesse Vincent，MIT

## 安裝指令（重現用）

```bash
npx -y skills add 'mattpocock/skills@grilling' --copy -y
npx -y skills add 'mattpocock/skills@domain-modeling' --copy -y
npx -y skills add 'mattpocock/skills@to-prd' --copy -y
npx -y skills add 'leonxlnx/taste-skill@design-taste-frontend' --copy -y
npx -y skills add 'softaworks/agent-toolkit@reducing-entropy' --copy -y
npx -y skills add 'juliusbrussee/caveman@caveman-review' --copy -y
npx -y skills add 'blader/humanizer' --copy -y
```

> `shadcn` 不在此表：採用既有 `vercel:shadcn` plugin（reference，不 vendor）。
> `vercel-composition-patterns` 也不在此表（授權來源 repo `vercel-labs/agent-skills` 沒有 LICENSE
> 檔案，不 vendor 進本 repo 重新公開發布）。React 專案接入時由 `shared-skill-onboarder` 建議自行安裝：
> `npx -y skills add 'vercel-labs/agent-skills@vercel-composition-patterns' --copy -y`

## Local patches

這些最小 patch 是 skill-commons 的跨技能契約，不屬於 upstream。每次重新
vendor 後必須重套並跑測試：

| Skill | Patch | Reason |
|---|---|---|
| all vendored skills | `source_kind: vendored` frontmatter | 讓 provenance 可機器檢查；upstream 更新後一律重套 |
| `skill-creator` | `stage`, `source`, `source_kind`; 保留本 repo 可用的 schema/eval scripts；新增本地 new-skill checklist reference | 登記官方來源並接入 skill-commons metadata 與 lifecycle contract |
| `brainstorming` | project-specific bounded discovery：material-ambiguity qualification、Skip/Quick/Standard/Deep 預算、conditional artifact、local handoff | 避免 adapted upstream 的 always-on ceremony，同時保留來源、名稱與 profile 相容性 |
| `finishing-a-development-branch` | manifest/guardrails、Gate Package、closeout、Recovery Mode、pre-merge runner | 接入跨專案安全、發布核可與 artifact closeout |
| `subagent-driven-development` | plan-sync contract、雙 review、gate handoff | 接入本 repo orchestration contract |
| `to-prd` | `stage`, `output`, local-first artifact body；移除內嵌 PRD 模板，改引用 canonical `prd-template.md`；產出後跑 `scripts/check-prd.py --tier core` 當 output gate | 接入 work-item artifact contract v3；PRD 形狀改由單一 canonical 模板 + check-prd 強制，消除與 `prd-interview` 的漂移並確保可銜接 spec/qa |
| `grilling` | `stage`, durable docs mode、`output`、`meta.yml` body | 合併壓測入口並接入 work-item artifact contract v3 |
| `caveman-review` | fresh-context dispatch、findings-first local review template | 合併 review 風格與派發能力，避免結構化 handoff 重新引入冗長 review 儀式 |
| `humanizer` | `stage`, `maturity`, `source`, `source_kind`; condensed optional utility with disclosure boundary | 接入 optional docs utility，保留 upstream pattern taxonomy 與 MIT notice |
