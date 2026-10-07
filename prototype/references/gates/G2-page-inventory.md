# G2：Page Inventory

為 routes 中的頁面配置 label、frameRef、type，以及適用時的 flowId。
已有 frame-seed 僅補畫面骨架；不讓它新增或刪除需求中的頁面。

現有 sitemap 提供導航事實，PRD 提供本次目標。兩者相符時直接沿用；衝突時記錄差異，
依明確的使用者變更決定處理，未解衝突交給需要做決策的人。

將 component mapping 存在 `{artifact_dir}/planning/component-mapping.md`：

| pageId | frameRef | 使用元件／CSS classes | 來源或缺口 |
|---|---|---|---|
| application | frame-application | c-form-grid、c-input、c-btn | component library |

共用畫面可共用 frameRef；需要新增元件時揭露缺口，不聲稱元件庫已有。Frame 複用方式
由實際差異決定，不使用固定差異數量門檻。[複用參考](../frame-reuse-spec.md) 只在需要時讀。
保存 map 草稿後繼續萃取 AC；型別與引用錯誤由 `validate-map.sh` 在凍結前檢查。
