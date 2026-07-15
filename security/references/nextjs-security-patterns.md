# Next.js 安全模式參考

Next.js（App Router）常見安全問題與正確實踐。

---

## 目錄

- [1. Server Action 認證問題](#sec-1)
- [2. NEXT_PUBLIC_ 變數誤用](#sec-2)
- [3. API Route 授權缺漏](#sec-3)
- [4. 環境變數注入](#sec-4)
- [5. 敏感資訊洩露到 Response](#sec-5)
- [6. 錯誤訊息洩露](#sec-6)
- [7. 認證流程檢查（依專案）](#sec-7)
- [快速掃描](#sec-scan)

---

<a id="sec-1"></a>
## 1. Server Action 認證問題

### 問題：Server Action 未驗證身份

```typescript
//  危險：任何人都能呼叫
'use server'
export async function deleteUser(id: string) {
  await db.delete(users).where(eq(users.id, id))
}

//  正確：先驗證 session
'use server'
export async function deleteUser(id: string) {
  const session = await getServerSession()
  if (!session?.user) throw new Error('Unauthorized')
  await db.delete(users).where(eq(users.id, id))
}
```

---

<a id="sec-2"></a>
## 2. NEXT_PUBLIC_ 變數誤用

```typescript
//  危險：API key 暴露給瀏覽器
NEXT_PUBLIC_OPENAI_KEY=sk-xxx

//  正確：敏感資訊只在 Server 用
OPENAI_KEY=sk-xxx  // 無 NEXT_PUBLIC_ 前綴
```

**規則**：
- `NEXT_PUBLIC_` 變數 → 編譯進 bundle → 用戶可從 DevTools 看到
- 敏感 API keys、tokens 永遠不加 `NEXT_PUBLIC_` 前綴

---

<a id="sec-3"></a>
## 3. API Route 授權缺漏

```typescript
//  危險：未保護的 API route
export async function GET(request: NextRequest) {
  const data = await getAllUsers()  // 任何人都可以拉所有用戶
  return NextResponse.json(data)
}

//  正確：驗證 token
export async function GET(request: NextRequest) {
  const token = request.headers.get('Authorization')?.replace('Bearer ', '')
  if (!token || !isValidToken(token)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const data = await getAllUsers()
  return NextResponse.json(data)
}
```

---

<a id="sec-4"></a>
## 4. 環境變數注入

```typescript
//  危險：直接使用未驗證的環境變數
const apiUrl = process.env.API_URL  // 可能是 undefined

//  正確：驗證必要的環境變數
const apiUrl = process.env.API_URL
if (!apiUrl) throw new Error('API_URL is required')
```

---

<a id="sec-5"></a>
## 5. 敏感資訊洩露到 Response

```typescript
//  危險：把 password hash 回傳給前端
return NextResponse.json({ user })  // user 包含 passwordHash

//  正確：選擇性回傳欄位
const { passwordHash, ...safeUser } = user
return NextResponse.json({ user: safeUser })
```

---

<a id="sec-6"></a>
## 6. 錯誤訊息洩露

```typescript
//  危險：洩露內部資訊
} catch (error) {
  return NextResponse.json({ error: error.message })  // 可能包含 DB schema
}

//  正確：通用錯誤訊息
} catch (error) {
  console.error('Internal error:', error)  // 只記 log
  return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
}
```

---

<a id="sec-7"></a>
## 7. 認證流程檢查（依專案）

修改認證邏輯前，先確認 consuming repo 自身的認證流程：讀 manifest `Domain Skill Names` 的 auth 相關 domain skill，或詢問使用者認證文件/入口模組位置。通用底線：
- Token 在 Header 傳遞（不用 URL 參數）
- 修改認證邏輯前必須確認不影響現有流程

---

<a id="sec-scan"></a>
## 快速掃描

```bash
# 執行完整安全掃描
bash <security-skill-dir>/scripts/scan-secrets.sh
```
