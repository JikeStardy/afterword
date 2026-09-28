#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const rootDir = path.resolve(__dirname, "..");
const outFile = path.join(rootDir, "lib/ui/afterword_vector_data.g.dart");
const iconsApi = require(path.join(rootDir, "docs/branding/fox-kit/icons.js"));
const scenesApi = require(path.join(rootDir, "docs/branding/fox-kit/scenes.js"));

const supportedAttrs = new Set([
  "xmlns",
  "viewBox",
  "width",
  "height",
  "role",
  "aria-label",
  "style",
  "color",
  "class",
  "transform",
  "fill",
  "stroke",
  "stroke-width",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-dasharray",
  "opacity",
  "d",
  "cx",
  "cy",
  "r",
  "x",
  "y",
  "rx",
]);

function fail(message) {
  throw new Error(message);
}

function tokenizeXml(source) {
  const tokens = [];
  const re = /<!--[\s\S]*?-->|<![^>]*>|<[^>]+>|[^<]+/g;
  let match;
  while ((match = re.exec(source))) {
    const raw = match[0];
    if (!raw.startsWith("<")) continue;
    if (raw.startsWith("<!--") || raw.startsWith("<!")) continue;
    if (/^<\?/.test(raw)) continue;
    if (/^<\//.test(raw)) {
      tokens.push({ type: "close", name: raw.slice(2, -1).trim() });
      continue;
    }
    const selfClosing = /\/>$/.test(raw);
    const inner = raw.slice(1, selfClosing ? -2 : -1).trim();
    const space = inner.search(/\s/);
    const name = space === -1 ? inner : inner.slice(0, space);
    const attrs = {};
    const rest = space === -1 ? "" : inner.slice(space + 1);
    let index = 0;
    const attrRe = /\s*([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*"([^"]*)"/gy;
    while (index < rest.length) {
      attrRe.lastIndex = index;
      const attr = attrRe.exec(rest);
      if (!attr) fail(`Unsupported XML attribute syntax near <${name}>: ${rest.slice(index)}`);
      if (!supportedAttrs.has(attr[1])) fail(`Unsupported SVG attribute: ${attr[1]} on <${name}>`);
      attrs[attr[1]] = decodeEntities(attr[2]);
      index = attrRe.lastIndex;
    }
    tokens.push({ type: "open", name, attrs, selfClosing });
  }
  return tokens;
}

function decodeEntities(value) {
  return value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function parseXml(source) {
  const root = { name: "#root", attrs: {}, children: [] };
  const stack = [root];
  for (const token of tokenizeXml(source)) {
    if (token.type === "open") {
      if (!["svg", "title", "g", "path", "circle", "rect"].includes(token.name)) {
        fail(`Unsupported SVG tag: <${token.name}>`);
      }
      const node = { name: token.name, attrs: token.attrs, children: [] };
      stack[stack.length - 1].children.push(node);
      if (!token.selfClosing && !["path", "circle", "rect"].includes(token.name)) stack.push(node);
    } else {
      if (stack.length === 1 || stack[stack.length - 1].name !== token.name) {
        fail(`Mismatched SVG close tag: </${token.name}>`);
      }
      stack.pop();
    }
  }
  if (stack.length !== 1) fail("Unclosed SVG element.");
  const svgs = root.children.filter((node) => node.name === "svg");
  if (svgs.length !== 1) fail("Expected exactly one SVG root.");
  return svgs[0];
}

function parseNumber(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) fail(`Invalid ${label}: ${value}`);
  return parsed;
}

function parseOpacity(value) {
  if (value == null) return 1;
  const parsed = parseNumber(value, "opacity");
  if (parsed < 0 || parsed > 1) fail(`Opacity outside 0..1: ${value}`);
  return parsed;
}

function parseInk(value, inherited, attr) {
  if (value == null) return inherited;
  const normalized = String(value).trim();
  if (normalized === "none") return "VectorInk.none";
  if (normalized === "currentColor") return "VectorInk.primary";
  if (/^var\(--fox-eye,\s*#[0-9a-fA-F]{3,8}\)$/.test(normalized)) return "VectorInk.eye";
  fail(`Unsupported ${attr} value: ${value}`);
}

function parseDash(value) {
  if (value == null) return [];
  if (value === "none") return [];
  return value
    .trim()
    .split(/[,\s]+/)
    .filter(Boolean)
    .map((part) => parseNumber(part, "stroke-dasharray"));
}

function parseTransform(value) {
  if (value == null) return { dx: 0, dy: 0, scaleX: 1, scaleY: 1 };
  let dx = 0;
  let dy = 0;
  let scaleX = 1;
  let scaleY = 1;
  const re = /(translate|scale)\(([^)]*)\)/g;
  let pos = 0;
  let match;
  while ((match = re.exec(value))) {
    if (value.slice(pos, match.index).trim()) fail(`Unsupported transform syntax: ${value}`);
    const nums = match[2].trim().split(/[,\s]+/).filter(Boolean).map((v) => parseNumber(v, "transform"));
    if (match[1] === "translate") {
      if (nums.length < 1 || nums.length > 2) fail(`Unsupported translate arity: ${value}`);
      dx += scaleX * nums[0];
      dy += scaleY * (nums.length === 2 ? nums[1] : 0);
    } else {
      if (nums.length < 1 || nums.length > 2) fail(`Unsupported scale arity: ${value}`);
      scaleX *= nums[0];
      scaleY *= nums.length === 2 ? nums[1] : nums[0];
    }
    pos = re.lastIndex;
  }
  if (value.slice(pos).trim()) fail(`Unsupported transform syntax: ${value}`);
  return { dx, dy, scaleX, scaleY };
}

function parsePathData(d) {
  const tokens = [];
  const re = /([AaCcHhLlMmQqVvZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)/g;
  let pos = 0;
  let match;
  while ((match = re.exec(d))) {
    if (d.slice(pos, match.index).replace(/[,\s]+/g, "") !== "") fail(`Unsupported path token near: ${d.slice(pos)}`);
    tokens.push(match[1] || Number(match[2]));
    pos = re.lastIndex;
  }
  if (d.slice(pos).replace(/[,\s]+/g, "") !== "") fail(`Unsupported path tail: ${d.slice(pos)}`);

  const ops = [];
  let index = 0;
  let cmd = null;
  let x = 0;
  let y = 0;
  let sx = 0;
  let sy = 0;

  const isCmd = (v) => typeof v === "string";
  const read = () => {
    if (index >= tokens.length || isCmd(tokens[index])) fail(`Missing path parameter for ${cmd}`);
    return tokens[index++];
  };
  const hasNumber = () => index < tokens.length && !isCmd(tokens[index]);
  const absolutePoint = (relative, px, py) => (relative ? [x + px, y + py] : [px, py]);

  while (index < tokens.length) {
    if (isCmd(tokens[index])) cmd = tokens[index++];
    if (!cmd) fail("Path data must start with a command.");
    const lower = cmd.toLowerCase();
    const relative = cmd !== cmd.toUpperCase();
    if (!"mlhv cqaz".replace(/\s/g, "").includes(lower)) fail(`Unsupported path command: ${cmd}`);
    if (lower === "z") {
      ops.push({ op: "close" });
      x = sx;
      y = sy;
      cmd = null;
      continue;
    }
    let firstMove = lower === "m";
    while (hasNumber()) {
      if (lower === "m") {
        const [nx, ny] = absolutePoint(relative, read(), read());
        ops.push({ op: "moveTo", x: nx, y: ny });
        x = nx;
        y = ny;
        if (firstMove) {
          sx = nx;
          sy = ny;
          firstMove = false;
        } else {
          ops[ops.length - 1].op = "lineTo";
        }
      } else if (lower === "l") {
        const [nx, ny] = absolutePoint(relative, read(), read());
        ops.push({ op: "lineTo", x: nx, y: ny });
        x = nx;
        y = ny;
      } else if (lower === "h") {
        const nx = relative ? x + read() : read();
        ops.push({ op: "lineTo", x: nx, y });
        x = nx;
      } else if (lower === "v") {
        const ny = relative ? y + read() : read();
        ops.push({ op: "lineTo", x, y: ny });
        y = ny;
      } else if (lower === "c") {
        const [x1, y1] = absolutePoint(relative, read(), read());
        const [x2, y2] = absolutePoint(relative, read(), read());
        const [nx, ny] = absolutePoint(relative, read(), read());
        ops.push({ op: "cubicTo", x1, y1, x2, y2, x: nx, y: ny });
        x = nx;
        y = ny;
      } else if (lower === "q") {
        const [x1, y1] = absolutePoint(relative, read(), read());
        const [nx, ny] = absolutePoint(relative, read(), read());
        ops.push({ op: "quadraticBezierTo", x1, y1, x: nx, y: ny });
        x = nx;
        y = ny;
      } else if (lower === "a") {
        const rx = read();
        const ry = read();
        const rotation = read();
        const largeArc = read();
        const sweep = read();
        const [nx, ny] = absolutePoint(relative, read(), read());
        if (![0, 1].includes(largeArc) || ![0, 1].includes(sweep)) fail(`Invalid arc flags in ${d}`);
        ops.push({ op: "arcToPoint", x: nx, y: ny, rx, ry, rotation, largeArc: largeArc === 1, clockwise: sweep === 1 });
        x = nx;
        y = ny;
      }
      if (lower === "m") cmd = relative ? "l" : "L";
    }
  }
  return ops;
}

function dartNum(value) {
  if (Object.is(value, -0)) value = 0;
  if (Number.isInteger(value)) return `${value}.0`;
  return `${Number(value.toFixed(6))}`;
}

function dartString(value) {
  return `'${String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
}

function pathExpressionFromOps(ops) {
  const lines = ["Path()"];
  for (const op of ops) {
    if (op.op === "moveTo") lines.push(`..moveTo(${dartNum(op.x)}, ${dartNum(op.y)})`);
    else if (op.op === "lineTo") lines.push(`..lineTo(${dartNum(op.x)}, ${dartNum(op.y)})`);
    else if (op.op === "cubicTo") lines.push(`..cubicTo(${dartNum(op.x1)}, ${dartNum(op.y1)}, ${dartNum(op.x2)}, ${dartNum(op.y2)}, ${dartNum(op.x)}, ${dartNum(op.y)})`);
    else if (op.op === "quadraticBezierTo") lines.push(`..quadraticBezierTo(${dartNum(op.x1)}, ${dartNum(op.y1)}, ${dartNum(op.x)}, ${dartNum(op.y)})`);
    else if (op.op === "arcToPoint") {
      lines.push(`..arcToPoint(Offset(${dartNum(op.x)}, ${dartNum(op.y)}), radius: Radius.elliptical(${dartNum(op.rx)}, ${dartNum(op.ry)}), rotation: ${dartNum(op.rotation)}, largeArc: ${op.largeArc}, clockwise: ${op.clockwise})`);
    } else if (op.op === "close") lines.push("..close()");
    else fail(`Unsupported generated path op: ${op.op}`);
  }
  return lines.join("\n");
}

function rectPath(attrs) {
  const x = parseNumber(attrs.x || "0", "rect x");
  const y = parseNumber(attrs.y || "0", "rect y");
  const width = parseNumber(attrs.width, "rect width");
  const height = parseNumber(attrs.height, "rect height");
  const rx = attrs.rx == null ? 0 : parseNumber(attrs.rx, "rect rx");
  if (rx === 0) {
    return `Path()..addRect(Rect.fromLTWH(${dartNum(x)}, ${dartNum(y)}, ${dartNum(width)}, ${dartNum(height)}))`;
  }
  return `Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(${dartNum(x)}, ${dartNum(y)}, ${dartNum(width)}, ${dartNum(height)}), Radius.circular(${dartNum(rx)})))`;
}

function circlePath(attrs) {
  const cx = parseNumber(attrs.cx, "circle cx");
  const cy = parseNumber(attrs.cy, "circle cy");
  const r = parseNumber(attrs.r, "circle r");
  return `Path()..addOval(Rect.fromCircle(center: Offset(${dartNum(cx)}, ${dartNum(cy)}), radius: ${dartNum(r)}))`;
}

function styleFor(node, parent) {
  const style = {
    fill: parseInk(node.attrs.fill, parent.fill, "fill"),
    stroke: parseInk(node.attrs.stroke, parent.stroke, "stroke"),
    strokeWidth: node.attrs["stroke-width"] == null ? parent.strokeWidth : parseNumber(node.attrs["stroke-width"], "stroke-width"),
    opacity: parent.opacity * parseOpacity(node.attrs.opacity),
    dash: node.attrs["stroke-dasharray"] == null ? parent.dash : parseDash(node.attrs["stroke-dasharray"]),
  };
  for (const attr of ["stroke-linecap", "stroke-linejoin"]) {
    if (node.attrs[attr] != null && node.attrs[attr] !== "round") fail(`Unsupported ${attr}: ${node.attrs[attr]}`);
  }
  return style;
}

function buildNodes(node, inherited) {
  if (node.name === "title") return [];
  if (node.name === "svg") {
    const style = styleFor(node, inherited);
    return node.children.flatMap((child) => buildNodes(child, style));
  }
  const style = styleFor(node, inherited);
  if (node.name === "g") {
    const children = node.children.flatMap((child) => buildNodes(child, style));
    const transform = parseTransform(node.attrs.transform);
    const args = [];
    if (node.attrs.class) args.push(`part: ${dartString(node.attrs.class)}`);
    if (transform.dx !== 0) args.push(`dx: ${dartNum(transform.dx)}`);
    if (transform.dy !== 0) args.push(`dy: ${dartNum(transform.dy)}`);
    if (transform.scaleX !== 1) args.push(`scaleX: ${dartNum(transform.scaleX)}`);
    if (transform.scaleY !== 1) args.push(`scaleY: ${dartNum(transform.scaleY)}`);
    if (args.length === 0) return children;
    return [`VectorGroup(<VectorNode>[\n${indent(children.join(",\n"), 2)}\n], ${args.join(", ")})`];
  }
  let pathExpr;
  if (node.attrs.transform != null) fail(`Unsupported transform on <${node.name}>.`);
  if (node.name === "path") pathExpr = pathExpressionFromOps(parsePathData(node.attrs.d));
  else if (node.name === "circle") pathExpr = circlePath(node.attrs);
  else if (node.name === "rect") pathExpr = rectPath(node.attrs);
  else fail(`Unsupported SVG node: ${node.name}`);
  const args = [];
  if (style.fill !== "VectorInk.none") args.push(`fill: ${style.fill}`);
  if (style.stroke !== "VectorInk.none") args.push(`stroke: ${style.stroke}`);
  if (style.strokeWidth !== 1.75) args.push(`strokeWidth: ${dartNum(style.strokeWidth)}`);
  if (style.opacity !== 1) args.push(`opacity: ${dartNum(style.opacity)}`);
  if (style.dash.length) args.push(`dash: <double>[${style.dash.map(dartNum).join(", ")}]`);
  return [`VectorPath(\n${indent(pathExpr, 2)},\n${indent(args.join(",\n"), 2)}${args.length ? "," : ""}\n)`];
}

function indent(text, spaces) {
  const pad = " ".repeat(spaces);
  return String(text)
    .split("\n")
    .map((line) => (line.length ? pad + line : line))
    .join("\n");
}

function factorySource(key, svg) {
  const nodes = buildNodes(parseXml(svg), {
    fill: "VectorInk.none",
    stroke: "VectorInk.none",
    strokeWidth: 1.75,
    opacity: 1,
    dash: [],
  });
  return `  ${dartString(key)}: () => <VectorNode>[\n${indent(nodes.join(",\n"), 4)}\n  ],`;
}

function collectFactories() {
  const entries = [];
  for (const icon of iconsApi.icons) {
    entries.push([`icon:${icon.id}`, iconsApi.svg(icon.id)]);
    if (icon.selectedBody) entries.push([`icon:${icon.id}-selected`, iconsApi.svg(icon.id, { selected: true })]);
  }
  for (const scene of scenesApi.scenes) entries.push([`scene:${scene.id}`, scenesApi.svg(scene.id)]);
  entries.push(["brand:fox", scenesApi.fox()]);
  return entries;
}

function collectMaterialMap() {
  const seen = new Set();
  const lines = [];
  for (const icon of iconsApi.icons) {
    for (const material of icon.material) {
      if (seen.has(material)) continue;
      seen.add(material);
      lines.push(`  Icons.${material}: ${dartString(icon.id)},`);
    }
  }
  return lines;
}

function generate() {
  const factories = collectFactories().map(([key, svg]) => factorySource(key, svg));
  const material = collectMaterialMap();
  return `// GENERATED CODE - DO NOT MODIFY BY HAND.\n// Generated by tool/generate_afterword_vectors.cjs from docs/branding/fox-kit.\n\npart of 'afterword_vectors.dart';\n\nfinal Map<String, List<VectorNode> Function()> afterwordVectorFactories = <String, List<VectorNode> Function()>{\n${factories.join("\n")}\n};\n\nfinal Map<IconData, String> afterwordMaterialIds = <IconData, String>{\n${material.join("\n")}\n};\n`;
}

function resolveExecutable(command, envPath = process.env.PATH || "") {
  if (!command) return null;
  if (command.includes(path.sep)) return path.resolve(command);
  for (const dir of envPath.split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, command);
    if (fs.existsSync(candidate)) return candidate;
  }
  return command;
}

function dartFromFlutter(flutterBin) {
  const resolvedFlutter = resolveExecutable(flutterBin);
  if (!resolvedFlutter) return null;
  const sdkRoot = path.dirname(path.dirname(resolvedFlutter));
  return path.join(sdkRoot, "bin/cache/dart-sdk/bin/dart");
}

function resolveDartBin() {
  if (process.env.DART_BIN) return resolveExecutable(process.env.DART_BIN);
  const flutterDart = dartFromFlutter(process.env.FLUTTER_BIN || "flutter");
  if (flutterDart && fs.existsSync(flutterDart)) return flutterDart;
  return resolveExecutable("dart");
}

function formatDart(source) {
  const dart = resolveDartBin();
  if (!dart) fail("Could not resolve dart. Set DART_BIN or FLUTTER_BIN, or add dart to PATH.");
  const result = spawnSync(dart, ["format", "--output=show"], {
    input: source,
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 16,
  });
  if (result.status !== 0) {
    fail(`dart format failed:\n${result.error ? result.error.message : ""}\n${result.stdout || ""}${result.stderr || ""}`);
  }
  return result.stdout;
}

function main(argv) {
  const check = argv.includes("--check");
  const raw = generate();
  const formatted = formatDart(raw);
  if (check) {
    const existing = fs.existsSync(outFile) ? fs.readFileSync(outFile, "utf8") : "";
    if (existing !== formatted) fail(`${path.relative(rootDir, outFile)} is out of date. Run node tool/generate_afterword_vectors.cjs.`);
    console.log(`${path.relative(rootDir, outFile)} is up to date.`);
    return;
  }
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, formatted);
  console.log(`Wrote ${path.relative(rootDir, outFile)}.`);
}

module.exports = {
  buildNodes,
  collectFactories,
  collectMaterialMap,
  generate,
  resolveDartBin,
  parsePathData,
  parseXml,
};

if (require.main === module) main(process.argv.slice(2));
