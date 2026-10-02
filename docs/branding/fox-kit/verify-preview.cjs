#!/usr/bin/env node
'use strict';

// Optional development check. The delivered preview itself has no dependencies.
// Use an already installed Playwright via NODE_PATH and an installed browser via
// BROWSER_EXECUTABLE; this script does not download either one.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');
const icons = require('./icons.js');
const scenes = require('./scenes.js');
const output = path.resolve(process.env.FOX_VERIFY_OUTPUT || 'dist/fox-kit-validation');

async function main() {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_EXECUTABLE ? { executablePath: process.env.BROWSER_EXECUTABLE } : {}) });
  const checks = [];
  const errors = [];
  const network = [];
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, reducedMotion: 'no-preference' });
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
  page.on('request', (request) => { if (/^https?:/.test(request.url())) network.push(request.url()); });
  try {
    await page.goto(pathToFileURL(path.join(__dirname, 'index.html')).href);
    assert.equal(await page.locator('#iconGrid .asset-card').count(), icons.icons.length);
    assert.equal(await page.locator('#sceneGrid .asset-card').count(), scenes.scenes.length);
    assert.equal(await page.locator('#motionType option').count(), scenes.motions.length);
    checks.push('Offline file:// renders the complete catalogue and scene list.');

    const svgs = icons.icons.flatMap((icon) => [icons.svg(icon.id), ...(icon.selectedBody ? [icons.svg(icon.id, { selected: true })] : [])])
      .concat(scenes.scenes.map((scene) => scenes.svg(scene.id)), [scenes.fox(), scenes.fox({ color: '#faf8f3', background: '#476b4f' })]);
    const invalid = await page.evaluate((sources) => sources.map((text, i) => ({ document: new DOMParser().parseFromString(text, 'image/svg+xml'), i })).filter((entry) => entry.document.querySelector('parsererror, script, foreignObject, image, animate')).map((entry) => entry.i), svgs);
    assert.deepEqual(invalid, []);
    for (const invalidColor of ['#12345', '#1234567', 'red" onload="alert(1)']) {
      assert.throws(() => scenes.fox({ color: invalidColor }));
      assert.throws(() => icons.svg('search', { color: invalidColor }));
    }
    checks.push('All SVG variants parse; static assets contain no scripts/bitmaps/animation; invalid color attributes are rejected.');

    await page.locator('#searchInput').fill('search_outlined');
    assert.ok(await page.locator('#iconGrid .asset-card').count() > 0);
    assert.ok((await page.locator('#iconGrid').textContent()).includes('搜索'));
    await page.locator('#searchInput').fill('<svg onload=alert(1)>');
    assert.equal(await page.locator('#iconGrid .asset-card').count(), 0);
    await page.locator('#searchInput').fill('');
    await page.locator('#categoryFilter').selectOption('navigation');
    assert.equal(await page.locator('#iconGrid .asset-card').count(), 5);
    const before = await page.locator('#iconGrid svg').first().innerHTML();
    await page.locator('#selectedToggle').check();
    assert.notEqual(await page.locator('#iconGrid svg').first().innerHTML(), before);
    for (const size of [16, 20, 24, 32, 48]) {
      await page.locator('[data-size="' + size + '"]').click();
      assert.equal(await page.locator('#iconGrid svg').first().getAttribute('width'), String(size));
    }
    await page.locator('#colorInput').fill('#223344');
    const color = await page.locator('#iconGrid svg').first().evaluate((node) => getComputedStyle(node).color);
    assert.equal(color, 'rgb(34, 51, 68)');
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#iconGrid .download-button').first().click();
    const download = await downloadPromise;
    assert.equal(download.suggestedFilename(), 'today-selected.svg');
    await download.saveAs(path.join(output, download.suggestedFilename()));
    assert.match(fs.readFileSync(path.join(output, download.suggestedFilename()), 'utf8'), /<svg/);
    await page.locator('#colorInput').fill('#476b4f');
    await page.locator('#selectedToggle').uncheck();
    await page.locator('#categoryFilter').selectOption('all');
    await page.locator('[data-size="24"]').click();
    checks.push('Search, no-results, category, five sizes, color, navigation selection and actual SVG download work.');
    await page.waitForTimeout(180);
    await page.screenshot({ path: path.join(output, 'overview.png') });

    for (const motion of scenes.motions) {
      await page.locator('#motionType').selectOption(motion.type);
      await page.locator('#replayButton').click();
      const active = await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).map((a) => ({ state: a.playState, duration: a.effect.getTiming().duration, iterations: a.effect.getTiming().iterations })));
      assert.ok(active.length > 0, motion.id + ' must animate');
      assert.ok(active.every((a) => a.duration === motion.duration), motion.id + ' timing');
      assert.ok(active.every((a) => a.iterations === (motion.loop ? Infinity : 1)), motion.id + ' iterations');
      await page.locator('#pauseButton').click();
      assert.ok(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).every((a) => a.playState === 'paused')));
    }
    await page.locator('#motionType').selectOption('analyze');
    for (const speed of [0.5, 1, 1.5]) {
      await page.locator('[data-speed="' + speed + '"]').click();
      const duration = await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true })[0].effect.getTiming().duration);
      assert.equal(duration, 2400 / speed);
    }
    await page.locator('#motionStage').focus();
    await page.keyboard.press('Space');
    assert.ok(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).every((a) => a.playState === 'paused')));
    await page.keyboard.press('Space');
    assert.ok(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).every((a) => a.playState === 'running')));
    await page.locator('#pauseButton').click();
    await page.locator('#motionStage').evaluate((node) => Promise.all(node.getAnimations({ subtree: true }).map((animation) => animation.ready)));
    const time = await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true })[0].currentTime);
    await page.waitForTimeout(150);
    assert.equal(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true })[0].currentTime), time);
    await page.locator('#playButton').click();
    checks.push('All 8 animations play/pause/replay with expected durations; speed and keyboard pause/resume work.');

    await page.locator('#reduceMotionToggle').check();
    await page.locator('#playButton').click();
    assert.equal(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).length), 0);
    await page.locator('#reduceMotionToggle').uncheck();
    assert.equal(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).length), 0);
    await page.locator('#playButton').click();
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForTimeout(80);
    assert.equal(await page.locator('#reduceMotionToggle').isChecked(), true);
    assert.equal(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).length), 0);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    await page.waitForFunction(() => !document.getElementById('reduceMotionToggle').checked);
    await page.locator('#playButton').click();
    await page.evaluate(() => {
      Object.defineProperty(document, 'hidden', { configurable: true, value: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    assert.ok(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).every((a) => a.playState === 'paused')));
    await page.evaluate(() => { delete document.hidden; });
    checks.push('Manual and runtime system reduced-motion changes stop animation; visibilitychange pauses (simulated hidden state).');

    await page.locator('#motionType').selectOption('saved');
    await page.locator('[data-speed="1"]').click();
    await page.waitForTimeout(800);
    assert.ok(await page.locator('#motionStage').evaluate((node) => node.getAnimations({ subtree: true }).every((a) => a.playState === 'finished')));
    await page.locator('.motion-panel').screenshot({ path: path.join(output, 'motion-complete.png') });
    await page.locator('#motionType').selectOption('analyze');
    await page.waitForTimeout(500);
    await page.locator('#pauseButton').click();
    await page.waitForTimeout(180);
    await page.locator('.motion-panel').screenshot({ path: path.join(output, 'motion-analysis.png') });

    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 900 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'horizontal overflow at ' + width);
      await page.evaluate(() => { document.documentElement.style.fontSize = '180%'; });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'large text overflow at ' + width);
      await page.evaluate(() => { document.documentElement.style.fontSize = ''; });
    }
    await page.evaluate(() => scrollTo(0, 0));
    await page.screenshot({ path: path.join(output, 'mobile.png') });
    checks.push('320/390px layouts and 180% root text fit without horizontal overflow.');
    assert.deepEqual(network, []);
    assert.deepEqual(errors, []);
    checks.push('No external HTTP requests or browser console/page errors.');
    fs.writeFileSync(path.join(output, 'checks.json'), JSON.stringify({ browser: browser.version(), checks }, null, 2) + '\n');
    console.log(JSON.stringify({ status: 'passed', checks, output }, null, 2));
  } finally {
    await browser.close();
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
