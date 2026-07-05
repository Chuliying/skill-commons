/* ====================================================================
 * PROTOTYPE BUILDER — RUNTIME ENGINE
 * ====================================================================
 *
 * ⚠️  READONLY — AI 不得修改此檔案
 * 此檔案包含所有 runtime JS 邏輯，從 templates/ 複製到 output/ 使用。
 * AI 在 G5 僅需填入 DATA_JS 區塊（PROTOTYPE_MAP、衍生變數、FRAME_REGISTRY）。
 *
 * 依賴的全域變數（由 DATA_JS 提供，必須在本檔案之前載入）：
 *   - PROTOTYPE_MAP   : Object  (G4 凍結 JSON)
 *   - SCENARIO_TITLES  : Object  { sid: "名稱" }
 *   - NAV_PATH         : Object  { sid: ["pageId", ...] }
 *   - STEPS            : Object  { sid: [{ id, label, dotIdx }, ...] }
 *   - STEPPER_LABELS   : Object  { sid: ["label", ...] }
 *   - PANEL_MAP        : Object  { sid: "scenario-{sid}" }
 *   - AC_DATA          : Object  { sid: { pageId: [AcItem, ...] } }
 *   - SCENARIO_STATE   : Object  { sid: { ...data } }
 *   - FRAME_REGISTRY   : Object  { frameRef: function(ctx) → HTML string }
 * ==================================================================== */

/* =============================================================
   STATE
   ============================================================= */
var currentScenario = Object.keys(SCENARIO_TITLES)[0] || 's1';
var currentStepId = (NAV_PATH[currentScenario] || [])[0] || 'step-1';

/* =============================================================
   SCENARIO & STEP NAVIGATION
   ============================================================= */
function switchScenario(sid, navEl) {
  document.querySelectorAll('.l-scenario-panel').forEach(function(p) { p.classList.remove('is-active'); });
  document.querySelectorAll('.c-nav-link-item').forEach(function(n) { n.classList.remove('is-active'); });
  var panel = document.getElementById(PANEL_MAP[sid]);
  if (panel) panel.classList.add('is-active');
  if (navEl) navEl.classList.add('is-active');
  currentScenario = sid;
  goTo(sid, NAV_PATH[sid][0]);
}

function goTo(sid, stepId) {
  var panel = document.getElementById(PANEL_MAP[sid]);
  if (!panel) return;
  panel.querySelectorAll('.c-flow-frame').forEach(function(f) { f.classList.remove('is-active'); });
  panel.querySelectorAll('.c-confirm-dialog-overlay').forEach(function(d) { d.classList.remove('is-open'); d.style.display = 'none'; });
  panel.querySelectorAll('.c-payment-selector-overlay').forEach(function(d) { d.classList.remove('is-open'); d.style.display = 'none'; });

  // Option C: 若 FRAME_REGISTRY 有此 frame，動態渲染
  var page = PROTOTYPE_MAP.pages ? PROTOTYPE_MAP.pages[stepId] : null;
  if (page && page.frameRef && FRAME_REGISTRY[page.frameRef]) {
    var state = SCENARIO_STATE[sid] || {};
    var ctx = Object.assign({}, state, {
      sid: sid,
      stepId: stepId,
      backStep: page.backStep,
      nextStep: page.nextStep
    });
    var frameEl = document.getElementById(sid + '-' + stepId);
    if (frameEl) {
      frameEl.innerHTML = FRAME_REGISTRY[page.frameRef](ctx);
    }
  }

  var el = document.getElementById(sid + '-' + stepId);
  if (el) el.classList.add('is-active');

  if (sid !== currentScenario) {
    document.querySelectorAll('.l-scenario-panel').forEach(function(p) { p.classList.remove('is-active'); });
    var sp = document.getElementById(PANEL_MAP[sid]);
    if (sp) sp.classList.add('is-active');
    currentScenario = sid;
  }
  currentStepId = stepId;
  updateMiddlePanel();
  updateShellIdBar(sid, stepId);
  updateNavParentActive();
}

/* =============================================================
   SHELL ID BAR — 顯示「MAP {routeId} / {pageId} → {frameRef}」
   位於 .l-preview-area 最上方的全域 dev 標籤（非 scenario shell 內部），
   讓 prototype tune mode 使用者能直接從畫面定位要調整的 map key
   ============================================================= */
function updateShellIdBar(sid, stepId) {
  var bar = document.querySelector('.l-preview-area > .c-shell-id-bar')
         || document.querySelector('.c-shell-id-bar');
  if (!bar) return;

  var pages = (typeof PROTOTYPE_MAP !== 'undefined' && PROTOTYPE_MAP.pages) || {};
  var page = pages[stepId] || {};
  var frameRef = page.frameRef || '';

  function setText(selector, value) {
    var el = bar.querySelector(selector);
    if (!el) return;
    el.textContent = value || '';
    el.style.display = value ? '' : 'none';
  }

  setText('.c-shell-id-bar__route', sid);
  setText('.c-shell-id-bar__page', stepId);
  setText('.c-shell-id-bar__frame', frameRef);

  var sepEl = bar.querySelector('.c-shell-id-bar__sep');
  if (sepEl) {
    sepEl.style.display = (sid && stepId) ? '' : 'none';
  }
}

/* =============================================================
   NAV PARENT ACTIVE — 當 link-item is-active 時，連動標示 group-label
   ============================================================= */
function updateNavParentActive() {
  document.querySelectorAll('.c-nav-group-label.is-parent-active').forEach(function(el) {
    el.classList.remove('is-parent-active');
  });
  var activeLink = document.querySelector('.c-nav-link-item.is-active');
  if (!activeLink) return;
  var prev = activeLink.previousElementSibling;
  while (prev && !prev.classList.contains('c-nav-group-label')) {
    prev = prev.previousElementSibling;
  }
  if (prev) prev.classList.add('is-parent-active');
}

function prevStep() {
  var path = NAV_PATH[currentScenario];
  var idx = path.indexOf(currentStepId);
  if (idx === -1) {
    var meta = STEPS[currentScenario].find(function(s) { return s.id === currentStepId; });
    if (meta) {
      for (var i = path.length - 1; i >= 0; i--) {
        var pm = STEPS[currentScenario].find(function(s) { return s.id === path[i]; });
        if (pm && pm.dotIdx < meta.dotIdx) { goTo(currentScenario, path[i]); return; }
      }
    }
    goTo(currentScenario, path[0]);
    return;
  }
  if (idx > 0) goTo(currentScenario, path[idx - 1]);
}

function nextStep() {
  var path = NAV_PATH[currentScenario];
  var idx = path.indexOf(currentStepId);
  if (idx === -1) idx = path.length - 1;
  if (idx < path.length - 1) goTo(currentScenario, path[idx + 1]);
}

function restartScenario() {
  goTo(currentScenario, NAV_PATH[currentScenario][0]);
}

function jumpToStep(sid, dotIdx) {
  var path = NAV_PATH[sid];
  var steps = STEPS[sid];
  for (var i = 0; i < path.length; i++) {
    var meta = steps.find(function(s) { return s.id === path[i]; });
    if (meta && meta.dotIdx === dotIdx) { goTo(sid, path[i]); return; }
  }
}

/* =============================================================
   FRAME RENDERING (Hybrid)
   ============================================================= */
function renderFrame(frameRef, sid, stepId) {
  if (FRAME_REGISTRY && FRAME_REGISTRY[frameRef]) {
    var state = SCENARIO_STATE[sid] || {};
    var page = (PROTOTYPE_MAP.pages && PROTOTYPE_MAP.pages[stepId]) || {};
    var ctx = Object.assign({}, state, {
      sid: sid,
      stepId: stepId,
      backStep: page.backStep,
      nextStep: page.nextStep
    });
    return FRAME_REGISTRY[frameRef](ctx);
  }
  return null;
}

/* =============================================================
   MIDDLE PANEL RENDERING
   ============================================================= */
function updateMiddlePanel() {
  var sid = currentScenario;
  var stepId = currentStepId;
  var stepsArr = STEPS[sid];
  if (!stepsArr) return;
  var meta = stepsArr.find(function(s) { return s.id === stepId; });
  if (!meta) return;

  document.getElementById('panel-scenario-title').textContent = SCENARIO_TITLES[sid];

  var labels = STEPPER_LABELS[sid];
  var activeIdx = meta.dotIdx;
  var total = labels.length;
  document.getElementById('panel-progress-badge').textContent = (activeIdx + 1) + ' / ' + total;

  // Vertical Stepper
  var stepperEl = document.getElementById('panel-stepper');
  var html = '';
  for (var i = 0; i < labels.length; i++) {
    var dotClass = 'c-v-stepper__dot';
    var labelClass = 'c-v-stepper__label';
    if (i < activeIdx) { dotClass += ' is-done'; labelClass += ' is-done'; }
    else if (i === activeIdx) { dotClass += ' is-active'; labelClass += ' is-active'; }
    html += '<div class="c-v-stepper__item" style="cursor:pointer" onclick="jumpToStep(\'' + sid + '\',' + i + ')">' +
      '<div class="c-v-stepper__track"><span class="' + dotClass + '">' + (i + 1) + '</span>';
    if (i < labels.length - 1) {
      var lineClass = 'c-v-stepper__line';
      if (i < activeIdx) lineClass += ' is-done';
      html += '<span class="' + lineClass + '"></span>';
    }
    html += '</div><span class="' + labelClass + '">' + labels[i] + '</span></div>';
  }
  stepperEl.innerHTML = html;

  // AC List
  var acList = document.getElementById('panel-ac-list');
  var acItems = (AC_DATA[sid] && AC_DATA[sid][stepId]) || [];
  var acHtml = '';
  var checked = getAcChecked();
  var notes = getAcNotes();
  for (var j = 0; j < acItems.length; j++) {
    var item = acItems[j];
    var acText = (typeof item === 'string') ? item : item.text;
    var acIdTag = '<span class="c-ac-item__id">' + (j + 1) + '</span>';
    var acKey = sid + '__' + stepId + '__' + j;

    // PRD info button + popover (Heroicons solid)
    var infoBtn = '';
    var popover = '';
    if (typeof item === 'object' && item.prd) {
      var popId = 'prd-pop-' + sid + '-' + stepId + '-' + j;
      infoBtn = '<button class="c-ac-item__info-btn" onclick="event.stopPropagation();togglePrdPopover(\'' + popId + '\')" title="查看 PRD 原文"><svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" style="display:block"><path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12zm8.706-1.442c1.146-.573 2.437.463 2.126 1.706l-.709 2.836.042-.02a.75.75 0 01.67 1.34l-.04.022c-1.147.573-2.438-.463-2.127-1.706l.71-2.836-.042.02a.75.75 0 11-.671-1.34l.041-.022zM12 9a.75.75 0 100-1.5.75.75 0 000 1.5z" clip-rule="evenodd"/></svg></button>';
      var escapedPrd = item.prd.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\\n/g, '<br>');
      popover = '<div class="c-ac-prd-popover" id="' + popId + '">' +
        '<div class="c-ac-prd-popover__label">PRD 原文</div>' +
        '<div class="c-ac-prd-popover__text">' + escapedPrd + '</div>' +
        (item.src ? '<div class="c-ac-prd-popover__src">來源：' + item.src + '</div>' : '') +
        '</div>';
    }

    // Note button (Heroicons solid — chat bubble)
    var hasNote = notes[acKey] ? ' is-has-note' : '';
    var noteBtn = '<button class="c-ac-item__note-btn' + hasNote + '" onclick="event.stopPropagation();toggleAcNote(\'' + acKey + '\')" title="備註">' +
      '<svg class="icon-note" width="16" height="16" viewBox="0 0 24 24" fill="currentColor" style="display:block"><path fill-rule="evenodd" d="M4.804 21.644A6.707 6.707 0 006 21.75a6.721 6.721 0 003.583-1.029c.774.182 1.584.279 2.417.279 5.322 0 9.75-3.97 9.75-9 0-5.03-4.428-9-9.75-9s-9.75 3.97-9.75 9c0 2.409 1.025 4.587 2.674 6.192.232.226.277.428.254.543a3.73 3.73 0 01-.814 1.686.75.75 0 00.44 1.223z" clip-rule="evenodd"/></svg>' +
      '</button>';

    if (item.isHint) {
      acHtml += '<li class="c-ac-item" style="cursor:default;padding-left:28px;color:var(--color-text-secondary);">' +
        '<span class="c-ac-item__text">' + acText + '</span></li>';
    } else {
      var isChecked = checked[acKey] ? ' is-checked' : '';
      acHtml += '<li class="c-ac-item' + isChecked + '" onclick="toggleAcItem(\'' + sid + '\',\'' + stepId + '\',' + j + ',this)">' +
        '<span class="c-ac-item__check"></span>' +
        '<span class="c-ac-item__text">' + acIdTag + acText + '</span>' +
        '<div class="c-ac-item__actions">' + infoBtn + noteBtn + '</div>' +
        '</li>' + popover;
      // Note editor (hidden by default)
      acHtml += '<div class="c-ac-note-editor" id="note-editor-' + acKey + '" style="display:none;">' +
        '<textarea class="c-ac-note-editor__input" placeholder="輸入備註..." onblur="saveAcNote(\'' + acKey + '\', this.value)">' + (notes[acKey] || '') + '</textarea>' +
        '</div>';
    }
  }
  acList.innerHTML = acHtml;

  // Nav buttons state
  var path = NAV_PATH[sid];
  var pathIdx = path.indexOf(stepId);
  var btnPrev = document.getElementById('btn-prev');
  var btnNext = document.getElementById('btn-next');
  btnPrev.disabled = (pathIdx <= 0 && pathIdx !== -1) || (pathIdx === -1 && meta.dotIdx === 0);
  btnNext.disabled = (pathIdx >= path.length - 1) || (pathIdx === -1);
}

/* =============================================================
   LOCALSTORAGE: AC CHECKED STATE
   ============================================================= */
function getAcChecked() {
  try { return JSON.parse(localStorage.getItem('ac_checked') || '{}'); } catch(e) { return {}; }
}
function setAcChecked(obj) {
  try { localStorage.setItem('ac_checked', JSON.stringify(obj)); } catch(e) {}
}
function toggleAcItem(sid, stepId, idx, el) {
  el.classList.toggle('is-checked');
  var checked = getAcChecked();
  var key = sid + '__' + stepId + '__' + idx;
  if (el.classList.contains('is-checked')) { checked[key] = true; } else { delete checked[key]; }
  setAcChecked(checked);
}

/* =============================================================
   LOCALSTORAGE: AC NOTES
   ============================================================= */
function getAcNotes() {
  try { return JSON.parse(localStorage.getItem('ac_notes') || '{}'); } catch(e) { return {}; }
}
function setAcNotes(obj) {
  try { localStorage.setItem('ac_notes', JSON.stringify(obj)); } catch(e) {}
}
function toggleAcNote(acKey) {
  var editor = document.getElementById('note-editor-' + acKey);
  if (!editor) return;
  var isVisible = editor.style.display !== 'none';
  editor.style.display = isVisible ? 'none' : 'block';
  if (!isVisible) {
    var textarea = editor.querySelector('textarea');
    if (textarea) textarea.focus();
  }
}
function saveAcNote(acKey, value) {
  var notes = getAcNotes();
  var trimmed = value.trim();
  if (trimmed) {
    notes[acKey] = trimmed;
  } else {
    delete notes[acKey];
  }
  setAcNotes(notes);
  // Update note button state
  var btns = document.querySelectorAll('.c-ac-item__note-btn');
  btns.forEach(function(btn) {
    if (btn.onclick && btn.onclick.toString().indexOf(acKey) > -1) {
      if (trimmed) btn.classList.add('is-has-note');
      else btn.classList.remove('is-has-note');
    }
  });
}

/* =============================================================
   DIALOG & INTERACTION HELPERS
   ============================================================= */
function togglePrdPopover(id) {
  var el = document.getElementById(id);
  if (!el) return;
  var wasOpen = el.classList.contains('is-open');
  document.querySelectorAll('.c-ac-prd-popover.is-open').forEach(function(p) { p.classList.remove('is-open'); });
  if (!wasOpen) el.classList.add('is-open');
}

function openConfirm(id) {
  var el = document.getElementById(id);
  if (el) { el.style.display = 'flex'; el.classList.add('is-open'); }
}
function closeConfirm(id) {
  var el = document.getElementById(id);
  if (el) { el.style.display = 'none'; el.classList.remove('is-open'); }
}

/* =============================================================
   PDF EXPORT (window.print)
   ============================================================= */
function exportReport() {
  var container = document.getElementById('print-report-container');
  container.innerHTML = buildReportHtml();
  container.style.display = 'block';
  window.print();
  container.style.display = 'none';
}

function buildReportHtml() {
  var checked = getAcChecked();
  var notes = getAcNotes();
  var now = new Date().toLocaleString('zh-TW');

  // Statistics
  var totalAc = 0, checkedCount = 0, notedCount = 0;
  var routeKeys = Object.keys(SCENARIO_TITLES);

  routeKeys.forEach(function(sid) {
    var stepAcs = AC_DATA[sid] || {};
    Object.keys(stepAcs).forEach(function(stepId) {
      var items = stepAcs[stepId];
      items.forEach(function(item, idx) {
        if (item.isHint) return;
        totalAc++;
        var key = sid + '__' + stepId + '__' + idx;
        if (checked[key]) checkedCount++;
        if (notes[key]) notedCount++;
      });
    });
  });

  var meta = PROTOTYPE_MAP.meta || {};
  var coverageRate = meta.coverageRate !== undefined ? meta.coverageRate : 100;

  var html = '<div class="c-print-report">';

  // Header
  html += '<div class="c-print-report__header">' +
    '<h1 class="c-print-report__title">' + (meta.projectName || 'Prototype') + ' — 確認報告</h1>' +
    '<div class="c-print-report__meta">' +
      '<span>PRD 版本：' + (meta.prdVersion || '-') + '</span>' +
      '<span>匯出時間：' + now + '</span>' +
      '<span>AC 覆蓋率：' + coverageRate + '%</span>' +
    '</div>' +
  '</div>';

  // Statistics
  html += '<div class="c-print-report__stats">' +
    '<div class="c-print-report__stat">&#x2705; 已確認：' + checkedCount + ' / ' + totalAc + '</div>' +
    '<div class="c-print-report__stat">&#x2B1C; 未確認：' + (totalAc - checkedCount) + '</div>' +
    '<div class="c-print-report__stat">&#x1F4DD; 有備註：' + notedCount + '</div>' +
  '</div>';

  // Per route → per page → per AC
  routeKeys.forEach(function(sid) {
    html += '<div class="c-print-report__route">' +
      '<h2 class="c-print-report__route-title">' + SCENARIO_TITLES[sid] + '</h2>';

    var stepAcs = AC_DATA[sid] || {};
    var path = NAV_PATH[sid] || [];
    path.forEach(function(stepId) {
      var items = stepAcs[stepId];
      if (!items || items.length === 0) return;
      var stepMeta = (STEPS[sid] || []).find(function(s) { return s.id === stepId; });
      var stepLabel = stepMeta ? stepMeta.label : stepId;

      html += '<div class="c-print-report__step">' +
        '<h3 class="c-print-report__step-title">' + stepLabel + '</h3>';

      items.forEach(function(item, idx) {
        if (item.isHint) return;
        var key = sid + '__' + stepId + '__' + idx;
        var status = checked[key] ? '&#x2705;' : '&#x2B1C;';
        var noteText = notes[key] ? '<div class="c-print-report__note">&#x1F4DD; ' + notes[key] + '</div>' : '';
        html += '<div class="c-print-report__ac-item">' +
          '<span class="c-print-report__ac-status">' + status + '</span>' +
          '<span class="c-print-report__ac-id">' + item.id + '</span>' +
          '<span class="c-print-report__ac-text">' + (item.text || item) + '</span>' +
          noteText +
        '</div>';
      });

      html += '</div>';
    });

    html += '</div>';
  });

  // Gaps (if any)
  if (meta.gaps && meta.gaps.length > 0) {
    html += '<div class="c-print-report__gaps">' +
      '<h2 class="c-print-report__gaps-title">缺口說明</h2>';
    meta.gaps.forEach(function(gap) {
      html += '<div class="c-print-report__gap-item">' +
        '<strong>' + gap.prdAcId + '</strong>：' + gap.description +
        (gap.reason ? ' — ' + gap.reason : '') +
      '</div>';
    });
    html += '</div>';
  }

  // Sign-off
  html += '<div class="c-print-report__signoff">' +
    '<div class="c-print-report__signoff-row"><span>PM 簽核：</span><span class="c-print-report__signoff-line"></span></div>' +
    '<div class="c-print-report__signoff-row"><span>UI 簽核：</span><span class="c-print-report__signoff-line"></span></div>' +
    '<div class="c-print-report__signoff-row"><span>DEV 簽核：</span><span class="c-print-report__signoff-line"></span></div>' +
    '<div class="c-print-report__signoff-row"><span>日期：</span><span class="c-print-report__signoff-line"></span></div>' +
  '</div>';

  html += '</div>';
  return html;
}

/* =============================================================
   INIT — 首次載入時渲染
   ============================================================= */
goTo(currentScenario, currentStepId);
