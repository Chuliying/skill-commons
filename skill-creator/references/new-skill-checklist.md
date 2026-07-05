# New Skill Checklist

本檢查表供 skill-creator 與維護者在新增技能時使用。每一項都需要檔案、測試輸出或 journey eval 作為證據。

## Product fit

- [ ] 指出服務 README 六條 ground truth 中的哪一條。
- [ ] 說明與既有技能的能力差異。
- [ ] 說明操作者角色與 Gate 密度依據。

## Metadata and provenance

- [ ] Frontmatter 有 `name`、`description`、`stage`、`maturity` 與 `source_kind`。
- [ ] 有 durable artifact 時，`output` 與 ARTIFACTS 路徑一致。
- [ ] `maturity` 是 `experimental` 或 `stable`；experimental 不在 core profile。
- [ ] 外部來源有 pinned `source`、license 與 SOURCES local patch 記錄。

## Integration

- [ ] INDEX、適用 profiles、README 速查表與 router 引用已同步。
- [ ] 相關連結在 generate 後仍可解析。
- [ ] 文件通過 `bash scripts/lint-docs.sh`。

## Verification

- [ ] 新行為先有 failing test 或可重複的 eval baseline。
- [ ] `bash bootstrap/generate.sh` 成功。
- [ ] `AGENTS.md` 列出的完整 Verify chain 全部通過。
- [ ] Stable 技能有對應 journey eval PASS 證據。
