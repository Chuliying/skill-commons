# Frame 複用規範（Hybrid）

> AI 在 G5 產出 HTML 時，依 frame 差異量自動選擇複用策略。

---

## 目錄

- [判斷規則](#sec-rules)
- [Option A：template clone](#sec-opt-a)
- [Option C：FRAME_REGISTRY render function](#sec-opt-c)
- [AI 決策流程（G4 freeze 使用）](#sec-decision)
- [重要提醒](#sec-note)

---

<a id="sec-rules"></a>
## 判斷規則

| 條件 | 策略 | 說明 |
|------|------|------|
| 差異 ≤ 3 且無條件分支 | **Option A**：`<template>` + clone function | 適合靜態/低變體 frame |
| 差異 > 3 或有條件分支 | **Option C**：FRAME_REGISTRY render function | 適合高變體/動態 frame |
| 僅出現一次 | **Inline（via FRAME_REGISTRY）** | 也放在 FRAME_REGISTRY 中，保持一致 |

**差異的定義**：sid、onclick 目標、文字內容、條件顯示/隱藏區塊等不同之處。

---

<a id="sec-opt-a"></a>
## Option A：template clone

```html
<!-- 在 PANELS_HTML 區塊之後、DATA_JS 之前放置 -->
<template id="tpl-settings-page">
  <div class="c-flow-frame">
    <div class="c-mobile-navbar">
      <span class="c-mobile-navbar__title">我的設定</span>
    </div>
    <div class="c-mobile-shell__content">
      <div class="c-feature-tile c-feature-tile--active" data-slot="topup-tile">
        <span class="c-feature-tile__title">儲值金</span>
        <span class="c-feature-tile__subtitle" data-slot="balance">餘額 0</span>
      </div>
    </div>
  </div>
</template>
```

```javascript
// 在 DATA_JS 區塊中定義 clone function
function cloneSettingsPage(sid, balance) {
  var tpl = document.getElementById('tpl-settings-page');
  var clone = tpl.content.cloneNode(true);
  var frame = clone.querySelector('.c-flow-frame');
  frame.id = sid + '-step-1';
  clone.querySelector('[data-slot="balance"]').textContent = '餘額 ' + balance;
  clone.querySelector('[data-slot="topup-tile"]').onclick = function() {
    goTo(sid, 'step-2');
  };
  return clone;
}
```

**命名慣例**：
- template id：`tpl-{frame-name}`
- data-slot：`data-slot="{slot-name}"`
- clone function：`clone{FrameName}(sid, ...args)`

---

<a id="sec-opt-c"></a>
## Option C：FRAME_REGISTRY render function

```javascript
// 在 DATA_JS 區塊的 FRAME_REGISTRY 中定義
var FRAME_REGISTRY = {
  'frame-login': function(ctx) {
    return '<div style="min-height: calc(100vh - 220px); display:flex; align-items:center; justify-content:center; padding: 24px;">' +
      '<div class="c-library-section" style="width:100%; max-width: 700px; margin: 0;">' +
        '<h3 class="c-library-section__title">登入頁</h3>' +
        '<div class="c-form-grid">' +
          '<div><label>Email</label><input class="c-input" type="text" placeholder="user@example.com" disabled></div>' +
          '<div><label>密碼</label><input class="c-input" type="password" placeholder="••••••" disabled></div>' +
        '</div>' +
        '<button class="c-btn c-btn--primary" style="width:100%">登入</button>' +
      '</div>' +
    '</div>';
  },

  'frame-l1': function(ctx) {
    var isGlobal = (ctx.stepId === 'l1-global');
    return '<div class="c-library-layout">' +
      '<section class="c-library-section">' +
        '<h3 class="c-library-section__title">' + (isGlobal ? '全球總覽' : '台灣總覽') + '</h3>' +
        '<div class="c-library-grid">' +
          '<div class="c-kpi-card"><div class="c-kpi-card__label">指標 A</div><div class="c-kpi-card__value">128</div></div>' +
          '<div class="c-kpi-card"><div class="c-kpi-card__label">指標 B</div><div class="c-kpi-card__value">42</div></div>' +
        '</div>' +
      '</section>' +
    '</div>';
  }
};
```

**命名慣例**：
- registry key：`'{frameRef}'`（與 pages[].frameRef 一致）
- context 物件 `ctx`：包含 `sid`, `stepId`, `backStep`, `nextStep` + `SCENARIO_STATE[sid]` 展開值
- 使用 `component-library.css` 與 `shell-*.css` 中已定義的 class（如 `c-library-section`、`c-kpi-card`、`c-input`、`c-btn` 等）
- 登入/授權類頁面應置中：外層使用 flex 置中容器（避免左上貼齊）

---

<a id="sec-decision"></a>
## AI 決策流程（G4 freeze 使用）

```
對每個 frameRef：
1. 計算該 frameRef 被幾個 page 引用
2. 若僅 1 次 → 放在 FRAME_REGISTRY 中（Inline via render function）
3. 若 ≥ 2 次：
   a. 列出所有引用 page 之間的差異點
   b. 差異 ≤ 3 且全部為純值替換 → Option A（template clone）
   c. 差異 > 3 或有 if/else 條件分支 → Option C（FRAME_REGISTRY）
4. 在 G4 Gate Package 呈現決策結果供使用者確認
```

---

<a id="sec-note"></a>
## 重要提醒

- **所有 frame 內容都由 FRAME_REGISTRY 動態渲染**（engine.js 的 goTo 函式負責呼叫）
- frame `<div>` 在 PANELS_HTML 中只是空容器：`<div id="s1-login" class="c-flow-frame"></div>`
- **不要在 PANELS_HTML 中放入 frame 的 HTML 內容**
- engine.js 中的 `renderFrame()` 函式會在 goTo 時自動呼叫 FRAME_REGISTRY
