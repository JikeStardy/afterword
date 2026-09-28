"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  buildNodes,
  collectFactories,
  collectMaterialMap,
  parsePathData,
  parseXml,
  resolveDartBin,
} = require("./generate_afterword_vectors.cjs");

const inherited = Object.freeze({
  fill: "VectorInk.none",
  stroke: "VectorInk.none",
  strokeWidth: 1.75,
  opacity: 1,
  dash: [],
});

test("path parser resolves relative commands and arcs to absolute Dart geometry", () => {
  const ops = parsePathData("M1 2 l3 4 h2 v-1 a5 6 45 1 0 7 8 z");

  assert.deepEqual(ops, [
    { op: "moveTo", x: 1, y: 2 },
    { op: "lineTo", x: 4, y: 6 },
    { op: "lineTo", x: 6, y: 6 },
    { op: "lineTo", x: 6, y: 5 },
    {
      op: "arcToPoint",
      x: 13,
      y: 13,
      rx: 5,
      ry: 6,
      rotation: 45,
      largeArc: true,
      clockwise: false,
    },
    { op: "close" },
  ]);
});

test("repeated move coordinates keep the subpath origin for closepath", () => {
  assert.deepEqual(parsePathData("M1 1 10 10 z l2 3"), [
    { op: "moveTo", x: 1, y: 1 },
    { op: "lineTo", x: 10, y: 10 },
    { op: "close" },
    { op: "lineTo", x: 3, y: 4 },
  ]);
});

test("group styles inherit into children and semantic parts are preserved", () => {
  const svg = parseXml(
    '<svg viewBox="0 0 24 24"><g class="fox-eye" fill="var(--fox-eye, #faf8f3)" opacity=".5" transform="translate(2 3) scale(.5)"><circle cx="4" cy="5" r="2"/></g></svg>',
  );
  const nodes = buildNodes(svg, inherited).join("\n");

  assert.match(nodes, /VectorGroup/);
  assert.match(nodes, /part: 'fox-eye'/);
  assert.match(nodes, /dx: 2\.0/);
  assert.match(nodes, /dy: 3\.0/);
  assert.match(nodes, /scaleX: 0\.5/);
  assert.match(nodes, /fill: VectorInk\.eye/);
  assert.match(nodes, /opacity: 0\.5/);
  assert.match(nodes, /addOval/);
});

test("transform order is preserved for scale and translate groups", () => {
  const scaledFirst = buildNodes(
    parseXml('<svg viewBox="0 0 24 24"><g transform="scale(2) translate(2 3)"><path d="M0 0L1 1"/></g></svg>'),
    inherited,
  ).join("\n");
  const translatedFirst = buildNodes(
    parseXml('<svg viewBox="0 0 24 24"><g transform="translate(2 3) scale(2)"><path d="M0 0L1 1"/></g></svg>'),
    inherited,
  ).join("\n");

  assert.match(scaledFirst, /dx: 4\.0/);
  assert.match(scaledFirst, /dy: 6\.0/);
  assert.match(scaledFirst, /scaleX: 2\.0/);
  assert.match(translatedFirst, /dx: 2\.0/);
  assert.match(translatedFirst, /dy: 3\.0/);
  assert.match(translatedFirst, /scaleX: 2\.0/);
});

test("root svg styles inherit and leaf transforms fail loudly", () => {
  const styledRoot = buildNodes(
    parseXml('<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M0 0L1 1"/></svg>'),
    inherited,
  ).join("\n");

  assert.match(styledRoot, /fill: VectorInk\.primary/);
  assert.doesNotMatch(styledRoot, /stroke: VectorInk\.primary/);
  assert.throws(
    () =>
      buildNodes(
        parseXml('<svg viewBox="0 0 24 24"><path transform="translate(1 2)" d="M0 0L1 1"/></svg>'),
        inherited,
      ),
    /Unsupported transform on <path>/,
  );
});

test("unsupported svg tags and path commands fail loudly", () => {
  assert.throws(
    () => parseXml('<svg viewBox="0 0 1 1"><line x1="0" y1="0" x2="1" y2="1"/></svg>'),
    /Unsupported SVG (attribute|tag)/,
  );
  assert.throws(() => parsePathData("M0 0 S1 1 2 2"), /Unsupported path (command|token)/);
});

test("current icon catalog produces factories and first material aliases", () => {
  const factories = collectFactories();
  const material = collectMaterialMap();

  assert.equal(factories.length, 108);
  assert.equal(factories[0][0], "icon:today");
  assert.ok(factories.some(([key]) => key === "icon:today-selected"));
  assert.ok(factories.some(([key]) => key === "scene:today-clear"));
  assert.equal(factories.at(-1)[0], "brand:fox");
  assert.ok(material.includes("  Icons.today_outlined: 'today',"));
  assert.ok(material.includes("  Icons.today: 'today',"));
  assert.ok(material.includes("  Icons.collections_bookmark: 'library',"));
});

test("every Material icon referenced by application UI has a vector mapping", () => {
  const root = path.resolve(__dirname, '..');
  const mapped = new Set(collectMaterialMap().map((line) => line.match(/Icons\.([a-zA-Z0-9_]+)/)[1]));
  const files = ['lib/main.dart', ...fs.readdirSync(path.join(root, 'lib/ui')).filter((name) => name.endsWith('.dart') && !name.startsWith('afterword')).map((name) => 'lib/ui/' + name)];
  for (const file of files) {
    for (const match of fs.readFileSync(path.join(root, file), 'utf8').matchAll(/\bIcons\.([a-zA-Z0-9_]+)/g)) {
      assert.ok(mapped.has(match[1]), file + ': unmapped ' + match[1]);
    }
  }
});

test("dart resolver honors DART_BIN and derives SDK dart from FLUTTER_BIN", () => {
  const original = {
    DART_BIN: process.env.DART_BIN,
    FLUTTER_BIN: process.env.FLUTTER_BIN,
    PATH: process.env.PATH,
  };
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "afterword-dart-resolver-"));
  try {
    const pathDartDir = path.join(temp, "path-dart");
    fs.mkdirSync(pathDartDir, { recursive: true });
    const pathDart = path.join(pathDartDir, "dart");
    fs.writeFileSync(pathDart, "");
    process.env.PATH = pathDartDir;
    delete process.env.DART_BIN;
    delete process.env.FLUTTER_BIN;
    assert.equal(resolveDartBin(), pathDart);

    const explicit = path.join(temp, "explicit-dart");
    process.env.DART_BIN = explicit;
    assert.equal(resolveDartBin(), explicit);

    delete process.env.DART_BIN;
    const sdk = path.join(temp, "flutter-sdk");
    const flutter = path.join(sdk, "bin", "flutter");
    const sdkDart = path.join(sdk, "bin", "cache", "dart-sdk", "bin", "dart");
    fs.mkdirSync(path.dirname(flutter), { recursive: true });
    fs.mkdirSync(path.dirname(sdkDart), { recursive: true });
    fs.writeFileSync(flutter, "");
    fs.writeFileSync(sdkDart, "");
    process.env.FLUTTER_BIN = flutter;
    assert.equal(resolveDartBin(), sdkDart);
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(temp, { recursive: true, force: true });
  }
});
