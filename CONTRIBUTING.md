# Contributing to skill-commons

本文件給 skill-commons 維護者使用，定義技能從提案、成熟、修改到淘汰的固定軌道。Top-level 技能資料夾是唯一 source of truth；生成目錄不得直接編輯。

## 新增門檻

每個新技能提案必須回答：

- 服務 README 六條 ground truth 中的哪一條。
- 與現有技能的能力差異，避免同一能力出現多個包裝入口。
- 主要操作者是工程角色或非工程角色。
- Gate 密度如何由 `min(重做成本, 操作者的錯誤定位能力)` 推導。
- 為何新增技能比擴充既有技能更合適。

## 成熟度標記

Frontmatter 的 `maturity` 只有 `experimental` 或 `stable`。既有技能缺少欄位時視為 `stable`，維持向後相容。

Experimental 技能不進 `profiles/core`，不承諾輸入輸出契約穩定，且 CHANGELOG 必須標示實驗性。升為 stable 前，對應 journey eval 必須有可重複的 PASS 證據。

## 新增檢查表

新增或收錄技能時使用 [skill-creator/references/new-skill-checklist.md](skill-creator/references/new-skill-checklist.md)。最低要求包含：

- Frontmatter 的 name、description、stage、output、maturity、source_kind 與必要 provenance。
- 符合 STYLE.md。
- 同步 INDEX、profiles 與 README 速查表。
- 有 artifact 產出的技能接上 ARTIFACTS 契約。
- `bootstrap/generate.sh` 與 `AGENTS.md` 的完整 Verify chain 全部通過。

## 修改門檻

輸入、輸出、handoff 或 Gate 契約變更屬 breaking change，必須更新 CHANGELOG 並依 semver 升版。只調整不影響行為的文字不算 breaking change。

外部技能依 `source_kind` 處理：vendored 內容保留 upstream，必要本地 patch 記入 SOURCES；adapted 技能更新前以 pinned commit 做 diff，保留本地契約。

## 淘汰路徑

技能先在 description 標記 `deprecated` 一個 minor 版本，並在 CHANGELOG 說明替代入口。下一個允許移除的版本才移到 `_archive/`，同步更新 INDEX、profiles、router 與 tests。舊名稱可保留一個 minor 的 migration alias。

## 健檢節奏

每次 `npx skills update` 後，或至少每季一次，檢查觸發詞衝突、能力重疊、SKILL.md 行數與 STYLE 違規。結果落在 `docs/skills-reorg/`，附日期、檢查範圍與處置。

## 開發與驗證

1. 先改 top-level source。
2. 執行 `bash bootstrap/generate.sh`。
3. 執行 `AGENTS.md` 列出的完整 Verify chain，包含 profiles、artifact、work-item、plan、journey harness、machine gate、release convergence 與 bootstrap。
4. 新增根目錄文件時同步加入 README 文件連結。
5. Commit、tag、push 與 PR 依 repository guardrails 執行；未經明確授權不 push。
