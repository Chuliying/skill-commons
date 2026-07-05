# Spec 通用原則（跨切面）

> 由 `spec` 在設計資料流 / 時間參數相關功能時載入。專案專屬細節（檔名、欄位、hook 名稱）一律屬 domain skill，見 `.agent/project-manifest.md` 指向的 domain skills，不寫在此。

## Data Transformer 規範

當後端 API 回傳格式與前端資料模型不一致時，**必須**定義 Transformer。

> **Iron Law**：Mock Data、外部資料設定與 parser/transformer 必須完全對齊。任一不對齊都可能造成靜默失敗。Spec 必須明確指出由哪一層負責轉換、各層對應的欄位/格式。

> **專案專屬細節**（API 格式範例、欄位對應、`ChartMetadata`/`chartOptions` 等檔案位置）屬 domain skill。

## 時間參數一致性規範

> **Critical**：若專案同時存在 server/client rendering，兩側必須使用相同的時間範圍來源，否則可能造成 hydration 不一致。

**設計原則**（spec 必須涵蓋）：

- 時間範圍解析完成前，不發送任何需要時間參數的請求（`enabled` 條件需含完整時間參數）。
- 禁止用「基於當前日期計算」的 fallback（可能落在後端可用範圍外，與 SSR 不一致）。
- cache/query identity 必須穩定地包含時間參數，避免物件參考變化造成重複請求。

> **專案專屬細節**（SSR 取數流程、hook 名稱、後端參數格式等）屬 domain skill。
