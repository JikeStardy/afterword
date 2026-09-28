'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { masterPaths, outputs } = require('./generate_afterword_platform_icons.cjs');
const { parsePathData } = require('./generate_afterword_vectors.cjs');

test('notification and themed marks use an eye cutout, not an opaque background dot', () => {
  assert.match(masterPaths().body, /a2\.3,2\.3/);
  for (const name of ['drawable/ic_afterword_notification.xml', 'drawable/ic_afterword_monochrome.xml']) {
    const xml = outputs()[name];
    assert.match(xml, /fillType="evenOdd"/);
    assert.equal((xml.match(/<path /g) || []).length, 2);
    assert.doesNotMatch(xml, /afterword_green|afterword_paper/);
  }
});

test('adaptive foregrounds retain safe insets and older APIs do not load monochrome elements', () => {
  const all = outputs();
  assert.match(all['drawable/ic_afterword_foreground.xml'], /width="108dp"/);
  assert.doesNotMatch(all['mipmap-anydpi-v26/ic_launcher.xml'], /<monochrome/);
  assert.match(all['mipmap-anydpi-v33/ic_launcher.xml'], /<monochrome/);
});

test('every endpoint and Bezier control point fits the circular adaptive/splash safe zones', () => {
  const points = Object.values(masterPaths()).flatMap((data) => parsePathData(data).flatMap((op) => [
    [op.x, op.y], [op.x1, op.y1], [op.x2, op.y2],
  ].filter(([x, y]) => x != null && y != null)));
  for (const [file, radius] of [
    ['drawable/ic_afterword_foreground.xml', 33 * 160 / 108],
    ['drawable/ic_afterword_monochrome.xml', 33 * 160 / 108],
    ['drawable/ic_afterword_splash.xml', 160 / 3],
  ]) {
    const xml = outputs()[file];
    const value = (name) => Number(xml.match(new RegExp('android:' + name + '="([0-9.-]+)"'))[1]);
    for (const [x, y] of points) {
      const distance = Math.hypot(x * value('scaleX') + value('translateX') - 80, y * value('scaleY') + value('translateY') - 80);
      assert.ok(distance <= radius, file + ': point ' + x + ',' + y + ' outside safe circle');
    }
  }
});
