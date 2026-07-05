---
name: markdown-api-doc-reference
description: |
  將 API 文件（PDF/Markdown/Office 文件）轉換為結構化 API Reference，供其他 skills 參照。Use when: (1) 用戶提供 API 文件, (2) 需要建立 api-reference.md, (3) spec-generator 找不到 API Reference 時, (4) 需要先把 PDF/DOCX/PPTX/XLSX 轉成 Markdown, (5) PM 整理事業單位 PRD/規格為可讀 Markdown。
  觸發關鍵字: API 文件, PDF, Word, PowerPoint, Excel, Markdown, MarkItDown, markitdown, 轉 markdown, 整理文件, 事業單位 PRD, api-reference, 後端規格
---

# API Doc Parser

將使用者提供的 API 文件轉換為結構化的 API Reference，作為 Single Source of Truth 供後續 Spec 產出參照。

當來源是 PDF / Word / PowerPoint / Excel 等二進位文件時，可先使用 bundled MarkItDown wrapper 轉成 Markdown，再進行 API 結構化解析或銜接 `prd-interview`。MarkItDown 是 optional dependency；缺少 runtime 時不要自動安裝，應清楚回報需要 Python 3.10+ 與 `markitdown` CLI。

---

## Trigger

當使用者提供 API 文件（PDF、Markdown、Word 等）並需要在開發流程中使用時觸發。

**常見場景**：

- 使用者說「這是 API 文件」
- 使用者提供 PDF/Markdown 格式的後端 API 規格
- 開始新專案需要整理 API 資訊
- **PM**：事業單位提供 PDF / Word / Excel / PPT 版 PRD 或需求摘要，需先轉成 Markdown 再進 `/prd-interview`

---

## Process

### Step 1：讀取 API 文件

1. 確認文件格式（PDF/Markdown/其他）
2. 若文件不是 Markdown 或純文字，先走「文件轉 Markdown」流程
3. 提取所有 API 端點資訊（若為 API 文件）：
   - Endpoint 路徑
   - HTTP 方法
   - Request Parameters
   - Response 格式
   - 錯誤碼

#### 文件轉 Markdown（Optional MarkItDown）

適用格式：PDF、DOCX、PPTX、XLSX、XLS、PNG、JPG、JPEG、WebP、GIF、HTML、CSV、JSON、XML、EPub 等需要先抽取文字與表格結構的文件。

**Agent 執行方式**（PM 不應手動貼腳本）：在 workspace 內呼叫 `convert-markitdown.sh` 或等效的 `markitdown <input> -o <output>`，路徑由使用者 Prompt 指定。

```bash
DOCS_ROOT="<manifest paths.docs_root; default: docs>"
bash .agent/skills/_shared/markdown/scripts/convert-markitdown.sh path/to/source.pdf "$DOCS_ROOT/reference/source.md"
# 圖片範例：path/to/screenshot.png → path/to/screenshot.md
```

安全邊界：

- 只處理 local workspace 內的檔案。
- 不接受 `http:`, `https:`, `file:`, `data:` 等 URI。
- 不啟用 MarkItDown plugins。
- 不啟動 `markitdown-mcp`；本 skill 只使用一次性 CLI wrapper。
- 單張圖片（PNG / JPG / JPEG / WebP / GIF）可轉 Markdown，通常含尺寸與 EXIF metadata；複雜流程圖、掃描件仍需 PM 對照原圖。
- 不使用 OCR、LLM image description、Azure Document Intelligence、YouTube transcription、audio transcription，除非使用者明確要求並完成額外安全評估。
- 預設不覆寫既有輸出檔；若確定要覆寫，設定 `MARKITDOWN_OVERWRITE=1`。
- 預設清除 Excel 轉換常見的 `Unnamed: N` 欄名與 Markdown table cell 裡的 `NaN` 空值噪音，以節省後續 token；若需要保留原始輸出，設定 `MARKITDOWN_KEEP_TABLE_NOISE=1`。

Runtime 要求：

- Python 3.10+
- `markitdown` CLI，可用建議版本：`markitdown==0.1.5`
- 建議安裝 extras 採最小集合，例如：`markitdown[pdf,docx,pptx,xlsx]==0.1.5`

若 wrapper 回報 runtime 缺失，只列出安裝建議，不要替使用者自動執行 `pip install`。

### Step 2：建立 API Reference（API 文件情境）

**輸出路徑**：`.agent/project-manifest.md` 中的 `api_reference`

**結構**：

```markdown
# [專案名稱] API Reference

> **來源**: [原始文件名稱]
> **版本**: [版本號]
> **用途**: 供 AI Skills 產出 Spec 時參照

## API 總覽

| 編號 | API 名稱 | Endpoint | 方法 | 用途 |
|:----:|---------|----------|:----:|------|
| 00 | [名稱] | [路徑] | GET | [用途] |

## API 詳細規格

### API-XX：[名稱]

**用途**：[說明]

**Endpoint**: `[METHOD] [path]`

**Request Parameters**:
| 參數 | 類型 | 必填 | 說明 |
|------|------|:----:|------|

**Response**:
```json
{ ... }
```

```

### Step 2b：銜接 PRD（事業單位文件情境）

若來源是事業單位 PRD / 需求摘要（非 API 規格）：

1. 轉換後的 `.md` 放在 repo 內可追溯路徑（例如 `docs/imports/`）
2. PM 抽查章節、表格、AC 是否可讀
3. 以該 `.md` 為輸入，執行 `prd-interview` 產出內部 RA（PRD）

### Step 3：驗證完整性

確認每個 API 都有：
- [ ] Endpoint 和方法
- [ ] Request Parameters 表格
- [ ] Response JSON 範例
- [ ] 用途說明

---

## Output

| 產出 | 路徑 | 說明 |
|------|------|------|
| API Reference | manifest 中 `api_reference` | 結構化 API 總表（API 文件情境） |
| Markdown 中介檔 | 使用者指定或原檔旁 `.md` | 從 PDF/Office 文件轉出的可解析文字 |

---

## 與其他 Skills 的關係

```

markdown（API 文件轉換模式）
       ↓ 產出
Markdown 中介檔 / api-reference.md
       ↓ 被參照
prd-interview (事業單位 PRD → 內部 RA)
spec (產出 Spec 時查詢 api_reference)

```

---

## 更新流程

當 API 文件更新時：

1. 使用者提供新版 API 文件
2. 執行本 skill 更新 `api-reference.md`
3. 在文件底部更新「更新紀錄」區塊

---

## 品質檢核

產出 API Reference 後，確認：

- [ ] 所有 API 都有詳細規格
- [ ] Response 有 JSON 範例
- [ ] 有認證方式說明
- [ ] 有錯誤格式說明
- [ ] 有更新紀錄

若使用 MarkItDown 中介轉換，額外確認：

- [ ] 中介 Markdown 沒有包含不應寫入 repo 的敏感資訊
- [ ] 表格欄位沒有因轉換錯位
- [ ] Endpoint、HTTP 方法、Request/Response 範例可回溯到來源文件（API 情境）
- [ ] 需求章節、AC、名詞定義可對照原文（PRD 情境）
