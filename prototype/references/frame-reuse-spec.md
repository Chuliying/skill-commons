# Frame 複用

相同畫面可共用 frameRef，透過 ctx 傳入場景差異。依內容與互動選擇簡單的 render
function 或局部 template helper，不以「差異幾項」強制選架構。

`planning/frames.js` 定義 FRAME_REGISTRY；helper 與 template 都留在這份來源內。
需要 DOM template 時可在 function 中建立 detached template，不手改產生的 shell。

```javascript
var FRAME_REGISTRY = {
  'frame-home': function(ctx) {
    var template = document.createElement('template');
    template.innerHTML = '<section class="c-library-section"><h2></h2></section>';
    template.content.querySelector('h2').textContent = ctx.title || '首頁';
    return template.innerHTML;
  }
};
```

這是可執行程式，不是受限 DSL。Escape 動態內容，並在瀏覽器確認需要的互動與狀態。
