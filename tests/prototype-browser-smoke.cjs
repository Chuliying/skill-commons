// Optional real-browser check. Requires Playwright and its browser or Chrome.
// Usage: node tests/prototype-browser-smoke.cjs <generated-two-step-demo/index.html>
const { chromium } = require('playwright');
const { pathToFileURL } = require('url');
const path = require('path');
const assert = require('assert/strict');

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const errors = [];
  try {
    const page = await browser.newPage();
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
    assert.equal(await page.locator('#s1-home').isVisible(), true);
    await page.getByRole('button', { name: '提交申請', exact: true }).click();
    assert.equal(await page.locator('#s1-confirm').isVisible(), true);
    assert.equal(await page.locator('#panel-progress-badge').textContent(), '2 / 2');
    await page.locator('#btn-prev').click();
    assert.equal(await page.locator('#s1-home').isVisible(), true);
    await page.locator('#panel-ac-list .c-ac-item').first().click();
    assert.equal(await page.locator('#panel-ac-list .is-checked').count(), 1);
    await page.getByText('返回首頁', { exact: true }).click();
    assert.equal(await page.locator('#s2-home').isVisible(), true);
    assert.deepEqual(errors, []);
    console.log('PASS real browser: initial render, next/previous step, AC toggle, scenario switch, no page errors');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
