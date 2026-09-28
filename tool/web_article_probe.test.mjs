import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../android/app/src/main/kotlin/app/readlater/readlater/WebArticleCaptureDialog.kt', import.meta.url), 'utf8');
const rawScript = source.match(/private val PROBE_SCRIPT = """([\s\S]*?)"""\.trimIndent\(\)/)?.[1];
const maxHtmlBytes = source.match(/private const val MAX_HTML_BYTES = ([^\n]+)/)?.[1];
const script = rawScript?.replaceAll('$MAX_HTML_BYTES', maxHtmlBytes);
assert.ok(script, 'the native WebView readiness probe must exist');
const extractScript = source.match(/private val EXTRACT_SCRIPT = """([\s\S]*?)"""\.trimIndent\(\)/)?.[1].replaceAll('$MAX_HTML_BYTES', maxHtmlBytes);
const automaticTemplate = source.match(/private fun automaticExtractionScript\(expectedSignature: String\): String \{[\s\S]*?return """([\s\S]*?)"""\.trimIndent\(\)/)?.[1];
assert.ok(extractScript, 'the native manual extraction script must exist');
assert.ok(automaticTemplate, 'automatic saving must atomically validate readiness before extraction');

function page({ readyState = 'complete', visibilityState = 'visible', text = '公众号完整正文', visibleText = text, title = '文章标题', images = [], contentPresent = true, contentStyle = {}, ancestorStyle = {}, rects = [{}] } = {}) {
  const ancestor = { style: ancestorStyle, parentElement: null };
  const content = {
    textContent: text,
    innerText: visibleText,
    parentElement: ancestor,
    style: contentStyle,
    getClientRects: () => rects,
    querySelectorAll: () => images.map((attributes) => ({
      currentSrc: attributes.currentSrc ?? '',
      getAttribute: (name) => attributes[name] ?? null,
    })),
  };
  return {
    document: {
      readyState,
      visibilityState,
      title,
      querySelector: () => contentPresent ? content : null,
      documentElement: { outerHTML: `<html><div id="js_content">${text}</div></html>` },
    },
    location: { href: 'https://mp.weixin.qq.com/s/article' },
    getComputedStyle: (element) => ({ display: 'block', visibility: 'visible', opacity: '1', ...element.style }),
    Blob,
  };
}

function probe(options) {
  return JSON.parse(vm.runInNewContext(script, page(options)));
}

function capture(options, expectedSignature = null) {
  const automaticScript = automaticTemplate.replaceAll('$probeExpression', () => script.trim().replace(/;$/, ''))
    .replaceAll('$captureExpression', () => extractScript.trim().replace(/;$/, ''))
    .replaceAll('${JSONObject.quote(expectedSignature)}', () => JSON.stringify(expectedSignature));
  return JSON.parse(vm.runInNewContext(expectedSignature === null ? extractScript : automaticScript, page(options)));
}

test('a loaded visible article produces a repeatable full-content signature', () => {
  const first = probe();
  assert.equal(first.ready, true);
  assert.equal(first.url, 'https://mp.weixin.qq.com/s/article');
  assert.equal(first.signature, probe().signature);
});

test('loading, missing content, blank content and background documents are not ready', () => {
  for (const options of [
    { readyState: 'interactive' },
    { contentPresent: false },
    { text: ' \n\t ' },
    { visibilityState: 'hidden' },
    { visibleText: '' },
  ]) assert.equal(probe(options).ready, false);
});

test('hidden content and hidden ancestors cannot trigger automatic saving', () => {
  for (const options of [
    { rects: [] },
    { contentStyle: { display: 'none' } },
    { contentStyle: { visibility: 'hidden' } },
    { ancestorStyle: { opacity: '0' } },
    { ancestorStyle: { display: 'none' } },
  ]) assert.equal(probe(options).ready, false);
});

test('same-length text replacement changes the readiness signature', () => {
  assert.notEqual(probe({ text: '第一段正文' }).signature, probe({ text: '第二段正文' }).signature);
  assert.notEqual(probe({ title: '初始标题' }).signature, probe({ title: '实际标题' }).signature);
});

test('lazy image changes and image ordering change the readiness signature', () => {
  const first = { 'data-src': 'https://example.com/first.jpg' };
  const second = { 'data-src': 'https://example.com/second.jpg' };
  const initial = probe({ images: [first, second] }).signature;
  assert.notEqual(initial, probe({ images: [second, first] }).signature);
  assert.notEqual(initial, probe({ images: [first] }).signature);
  assert.notEqual(initial, probe({ images: [{ ...first, currentSrc: first['data-src'] }, second] }).signature);
  assert.notEqual(initial, probe({ images: [{ ...first, srcset: 'large.jpg 2x' }, second] }).signature);
});

test('oversize signatures are never passed to automatic extraction', () => {
  assert.equal(probe({ text: '文'.repeat(5 * 1024 * 1024 + 1) }).ready, false);
});

test('automatic extraction refuses text replaced after the stable probe', () => {
  const expected = probe({ text: '最初正文' }).signature;
  const result = capture({ text: '替换正文' }, expected);
  assert.equal(result.error, 'content_changed');
  assert.equal(result.html, undefined);
});

test('automatic extraction refuses content hidden after the stable probe', () => {
  const expected = probe().signature;
  for (const options of [{ contentStyle: { display: 'none' } }, { visibilityState: 'hidden' }, { readyState: 'loading' }]) {
    const result = capture(options, expected);
    assert.equal(result.error, 'content_changed');
    assert.equal(result.html, undefined);
  }
});

test('automatic extraction refuses image changes after the stable probe', () => {
  const expected = probe({ images: [{ 'data-src': 'initial.jpg' }] }).signature;
  const result = capture({ images: [{ 'data-src': 'updated.jpg' }] }, expected);
  assert.equal(result.error, 'content_changed');
  assert.equal(result.html, undefined);
});

test('automatic extraction atomically captures the still-stable document', () => {
  const result = capture({}, probe().signature);
  assert.equal(result.error, undefined);
  assert.match(result.html, /公众号完整正文/);
});

test('manual saving remains immediate without a stability signature', () => {
  const result = capture({ text: '用户手动确认的正文', readyState: 'interactive' });
  assert.equal(result.error, undefined);
  assert.match(result.html, /用户手动确认的正文/);
});

test('signature text containing JavaScript syntax is treated as data', () => {
  const options = { text: '正文 " ); throw new Error("unsafe"); // $& \\ \n尾段' };
  const result = capture(options, probe(options).signature);
  assert.equal(result.error, undefined);
  assert.match(result.html, /尾段/);
});
