---
name: security
description: |
  安全檢查專家。確保程式碼不包含敏感資訊、遵循安全最佳實踐。
  觸發時機: commit 前、安裝新套件前、處理認證邏輯時
  觸發關鍵字: security 掃描, 安全檢查, secrets, 敏感資訊洩露, api key 外洩, 硬編碼憑證, client env 前綴洩漏（例：Next.js 的 NEXT_PUBLIC）
source_kind: original
stage: infra
---

# Security Guardian

**職責**：確保程式碼安全，防止敏感資訊洩露。

---

## Available Scripts

以實際找到的 skill 目錄為基準解析（標準 consuming repo 佈局：`.agent/skills/_shared/security/`）：

```bash
# 完整的 secrets 掃描（預設從 manifest 讀 source_roots/source_extensions）
bash .agent/skills/_shared/security/scripts/scan-secrets.sh

# 指定目錄（預設掃 src；非此慣例的專案請帶入原始碼根目錄）
bash .agent/skills/_shared/security/scripts/scan-secrets.sh <target-dir>
```

## On-Demand Hook

接觸生產環境或高風險操作時，可啟用危險操作攔截（On-Demand，非全域常駐）：

```bash
# 手動測試攔截
echo "rm -rf /data" | bash .agent/skills/_shared/security/hooks/dangerous-op-guard.sh
# Exit 0 = 放行，Exit 2 = 阻擋
```

**攔截範圍**：`rm -rf`、`git push --force`、`DROP TABLE`/`TRUNCATE`、`kubectl delete`、`docker rm -f`

> 這是手動/按需測試。**切勿**把此 hook 直接設成全域 `PreToolUse`——會靜默攔截所有 session 的操作。要常駐請依 `hooks/dangerous-op-guard.md` 的範圍設定，並讓使用者明確知情。

**審計 log**：`hooks/dangerous-op-guard.sh` 被觸發時自動寫入 `~/.skill-memory/security/operations.log`（非每次呼叫 security skill 都會寫，只有實際跑這個 On-Demand hook 才會）

> 詳細說明：`hooks/dangerous-op-guard.md`

---

## Iron Laws

```
1. NO HARDCODED SECRETS (API keys, tokens, passwords)
2. NO SENSITIVE DATA IN LOGS OR URLS
3. NO UNTRUSTED PACKAGES
4. NO SECRETS IN CLIENT-EXPOSED ENV VARS（前綴依 framework，例：Next.js 的 NEXT_PUBLIC_）
```

---

## 安全檢查清單

### Phase 1: 敏感資訊檢查

掃描範圍與副檔名依專案而定：原始碼根目錄與語言讀 manifest 的 `## Paths` / `## Stack`（沒有就問使用者或用 repo 慣例），下例以 `<src-root>` / `<ext>` 代稱。

```bash
# 1.1 檢查硬編碼敏感資訊
grep -rEn "(api_key|apikey|secret|password|token)\s*[:=]\s*['\"][^'\"]+['\"]" <manifest-source-roots> <manifest-extension-includes> | grep -iv "type\|interface\|env"

# 1.2 檢查 client-exposed env 敏感變數（前綴依 framework，例：Next.js 的 NEXT_PUBLIC_、Vite 的 VITE_）
grep -rn "<client-env-prefix>.*KEY\|<client-env-prefix>.*SECRET\|<client-env-prefix>.*TOKEN\|<client-env-prefix>.*PASSWORD" <src-root>

# 1.3 檢查 log 輸出敏感資訊（log 呼叫依語言，例：console.log / print / logger）
grep -rn "<stack-log-call>.*\(token\|key\|secret\|password\)" <manifest-source-roots> <manifest-extension-includes>
```

| 發現 | 風險等級 | 處理方式 |
|------|:--------:|---------|
| 硬編碼 API Key | **Critical** | 立即移除，改用環境變數 |
| client-exposed env 敏感變數 | **High** | 移至 server-side |
| log 輸出 token | **High** | 移除或遮罩處理 |

### Phase 2: 環境變數檢查

```bash
# 2.1 確認 .env 在 .gitignore
grep -q "\.env" .gitignore && echo "OK" || echo "WARNING: .env not in .gitignore"

# 2.2 檢查環境變數使用（讀取語法依語言，例：process.env / os.environ）
grep -rn "process\.env\.\|os\.environ" <src-root> | head -20
```

**環境變數命名規範**：

| 類型 | 可見範圍 | 適用內容 |
|------|---------|---------|
| client-exposed 前綴（依 framework，例：Next.js 的 `NEXT_PUBLIC_`、Vite 的 `VITE_`） | Client + Server | 非敏感的公開配置 |
| 無 client 前綴 | Server only | API keys, tokens, secrets |

### Phase 3: 依賴安全檢查

指令依 manifest `## Stack` 的 package manager / 生態（沒有就問使用者）：

```bash
# 3.1 依賴弱點掃描：用 stack 對應的 audit 指令（例：<pkg-manager> audit --audit-level=high；Python 用 pip-audit）
<pkg-audit-cmd>

# 3.2 檢查套件來源（安裝前）：查 registry 的 homepage / repository / 下載量
<pkg-view-cmd> [package-name]
```

**安裝套件前檢查**：

| 檢查項目 | 建議標準 |
|---------|---------|
| 週下載量 | > 10,000 |
| 最後更新 | < 1 年內 |
| GitHub Stars | > 100 |
| 維護者 | 知名組織或個人 |

### Phase 4: 認證/授權檢查

**修改認證邏輯前必須確認**：

```
□ 是否影響現有的認證流程？
□ Token 是否正確傳遞（Header vs Cookie）？
□ 是否有適當的錯誤處理？
□ 是否有 Token 過期處理？
```

---

## 高風險操作

以下操作需要**特別審查**：

| 操作 | 風險 | 審查重點 |
|------|------|---------|
| 修改認證入口模組（讀 manifest `Domain Skill Names` 的 auth 相關 domain skill；沒有就問使用者 auth 入口位置） | 認證流程 | Token 處理是否正確 |
| 修改認證相關常數/配置 | 認證配置 | 是否洩露敏感資訊 |
| 新增 API route / endpoint | 授權檢查 | 是否有認證保護 |
| 修改 `.env.example` | 配置範例 | 是否包含真實值 |

---

## 安全最佳實踐

### 1. 環境變數

```typescript
//  正確：使用環境變數
const apiKey = process.env.API_KEY

//  錯誤：硬編碼
const apiKey = "sk-1234567890abcdef"
```

### 2. 敏感資訊遮罩

```typescript
//  正確：遮罩處理
console.log('Token:', token.substring(0, 8) + '...')

//  錯誤：完整輸出
console.log('Token:', token)
```

### 3. URL 參數

```typescript
//  正確：Header 傳遞
fetch(url, {
  headers: { Authorization: `Bearer ${token}` }
})

//  錯誤：URL 參數
fetch(`${url}?token=${token}`)
```

### 4. 錯誤訊息

```typescript
//  正確：通用錯誤訊息
throw new Error('Authentication failed')

//  錯誤：洩露內部資訊
throw new Error(`Invalid token: ${token}`)
```

---

## Pre-commit 自動檢查

先確認 consuming repo 是否已設定 pre-commit hook（看 repo 證據：`.git/hooks/`、husky、pre-commit framework 等；**不要假設存在**）：

- **已設定** → 確認包含 secrets pattern 掃描（api_key、secret_key、password 硬編碼檢測；排除型別定義和環境變數引用）；缺少則建議接入 `scripts/scan-secrets.sh`。
- **未設定** → commit 前手動執行 `scripts/scan-secrets.sh`（見 Available Scripts）。

---

## Framework References

依 manifest `stack.framework`（沒有就問使用者）條件式載入對應參考，不套用到其他 framework：

| framework | 參考 |
|-----------|------|
| next | `references/nextjs-security-patterns.md` |

---

## Related Skills

| Skill / 文件 | 關係 |
|-------|------|
| `caveman-review` | Phase 5 安全檢查 |
| `.agent/guardrails.md`（文件，非 skill） | 操作邊界定義 |

---

## Execution Checklist（必填輸出）

> Checklist 格式慣例見 [CHECKLIST-CONVENTION.md](../CHECKLIST-CONVENTION.md)。

```
Skill: security
Executed At: YYYY-MM-DD HH:MM
Scope: [檔案/目錄]

Steps:
Phase 1: 敏感資訊檢查 - [PASS/SKIP]
   Evidence: [硬編碼: X, client-exposed env: X, log 輸出: X]
Phase 2: 環境變數檢查 - [PASS/SKIP]
   Evidence: [.gitignore: OK/FAIL]
Phase 3: 依賴安全檢查 - [PASS/SKIP]
   Evidence: [依賴 audit: X vulnerabilities]
Phase 4: 認證/授權檢查 - [PASS/SKIP/N/A]
   Evidence: [審查結果]

Security Result:
   □ 硬編碼 Secrets: [無/有]
   □ client-exposed env 敏感: [無/有]
   □ 依賴 audit: [PASS/FAIL]
   □ 認證邏輯: [OK/需審查/N/A]

Findings: [無 / 問題清單]
Suggested Fix: [無 / 修復建議]
```

只有本次安全檢查交接 durable report 時，未把 Checklist 寫入 report 才算交接未完成。
