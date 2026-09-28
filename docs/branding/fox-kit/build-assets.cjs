#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const kitDir = __dirname;
const repoRoot = path.resolve(kitDir, "../../..");
const iconsApi = require(path.join(kitDir, "icons.js"));
const scenesApi = require(path.join(kitDir, "scenes.js"));

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function writeFile(file, content) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, content.endsWith("\n") ? content : content + "\n", "utf8");
}

function readDartFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return readDartFiles(fullPath);
    if (entry.isFile() && entry.name.endsWith(".dart")) return [fullPath];
    return [];
  });
}

function extractSourceGlyphs() {
  const libDir = path.join(repoRoot, "lib");
  const glyphs = new Map();
  const pattern = /\bIcons\.([A-Za-z0-9_]+)/g;
  for (const file of readDartFiles(libDir)) {
    const source = fs.readFileSync(file, "utf8");
    let match;
    while ((match = pattern.exec(source))) {
      const glyph = match[1];
      const rel = path.relative(repoRoot, file);
      const record = glyphs.get(glyph) || { glyph, count: 0, files: [] };
      record.count += 1;
      if (!record.files.includes(rel)) record.files.push(rel);
      glyphs.set(glyph, record);
    }
  }
  return Array.from(glyphs.values()).sort((a, b) => a.glyph.localeCompare(b.glyph));
}

function glyphMapFromIcons(icons) {
  const map = new Map();
  for (const icon of icons) {
    for (const glyph of icon.material || []) {
      if (!map.has(glyph)) map.set(glyph, []);
      map.get(glyph).push(icon.id);
    }
  }
  return map;
}

function validateIcons(icons) {
  const ids = new Set();
  const errors = [];
  for (const icon of icons) {
    if (!icon.id || ids.has(icon.id)) errors.push(`duplicate-or-missing id: ${icon.id}`);
    ids.add(icon.id);
    if (!icon.label) errors.push(`${icon.id}: missing label`);
    if (!icon.category) errors.push(`${icon.id}: missing category`);
    if (!Array.isArray(icon.tags)) errors.push(`${icon.id}: tags must be an array`);
    if (!Array.isArray(icon.material) || icon.material.length === 0) errors.push(`${icon.id}: material mapping missing`);
    if (!icon.body || !icon.body.includes("currentColor")) errors.push(`${icon.id}: body missing SVG geometry`);
  }
  if (errors.length) throw new Error(errors.join("\n"));
}

function stableJson(value) {
  return JSON.stringify(value, null, 2);
}

function buildCoverage(sourceGlyphs, icons) {
  const materialToIconIds = glyphMapFromIcons(icons);
  const covered = [];
  const missing = [];
  for (const item of sourceGlyphs) {
    const iconIds = materialToIconIds.get(item.glyph) || [];
    const row = { ...item, iconIds };
    if (iconIds.length) covered.push(row);
    else missing.push(row);
  }

  const sourceGlyphSet = new Set(sourceGlyphs.map((item) => item.glyph));
  const extraMaterial = Array.from(materialToIconIds.entries())
    .filter(([glyph]) => !sourceGlyphSet.has(glyph))
    .map(([glyph, iconIds]) => ({ glyph, iconIds }))
    .sort((a, b) => a.glyph.localeCompare(b.glyph));

  const categoryCounts = icons.reduce((acc, icon) => {
    acc[icon.category] = (acc[icon.category] || 0) + 1;
    return acc;
  }, {});

  return {
    source: "lib/**/*.dart Icons.* extraction",
    totalSourceGlyphs: sourceGlyphs.length,
    totalIconAssets: icons.length,
    categoryCounts,
    coveredSourceGlyphs: covered.length,
    missingSourceGlyphs: missing,
    covered,
    extraMaterialMappings: extraMaterial,
    originalGlyphMap: Object.fromEntries(
      Array.from(materialToIconIds.entries())
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([glyph, iconIds]) => [glyph, iconIds.slice().sort()])
    ),
  };
}

function sceneSvg(id) {
  return scenesApi.svg(id);
}

function cleanGeneratedFiles() {
  for (const section of ["icons", "scenes", "brand"]) {
    const dir = path.join(kitDir, section);
    if (fs.existsSync(dir)) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isFile() && entry.name.endsWith(".svg")) fs.unlinkSync(path.join(dir, entry.name));
      }
    }
    ensureDir(dir);
  }
}

function main() {
  validateIcons(iconsApi.icons);
  cleanGeneratedFiles();

  for (const icon of iconsApi.icons) {
    writeFile(path.join(kitDir, "icons", `${icon.id}.svg`), iconsApi.svg(icon.id));
    if (icon.selectedBody) {
      writeFile(path.join(kitDir, "icons", `${icon.id}-selected.svg`), iconsApi.svg(icon.id, { selected: true }));
    }
  }

  const scenes = Array.isArray(scenesApi.scenes) ? scenesApi.scenes : [];
  const motions = Array.isArray(scenesApi.motions) ? scenesApi.motions : [];
  if (typeof scenesApi.fox !== "function" || typeof scenesApi.svg !== "function") {
    throw new TypeError("scenes.js must export fox(options) and svg(id, options).");
  }

  writeFile(
    path.join(kitDir, "brand", "afterword-fox-primary.svg"),
    scenesApi.fox({ color: "#476b4f", eyeColor: "#faf8f3" })
  );
  writeFile(
    path.join(kitDir, "brand", "afterword-fox-reversed.svg"),
    scenesApi.fox({ color: "#faf8f3", eyeColor: "#476b4f" })
  );
  writeFile(
    path.join(kitDir, "brand", "afterword-fox-app-tile.svg"),
    scenesApi.fox({ color: "#faf8f3", background: "#476b4f", eyeColor: "#476b4f", rounded: true })
  );
  writeFile(
    path.join(kitDir, "brand", "afterword-fox-layered.svg"),
    scenesApi.fox({ color: "#476b4f", eyeColor: "#faf8f3" })
  );
  for (const scene of scenes) {
    writeFile(path.join(kitDir, "scenes", `${scene.id}.svg`), sceneSvg(scene.id));
  }

  const sourceGlyphs = extractSourceGlyphs();
  const coverage = buildCoverage(sourceGlyphs, iconsApi.icons);
  const catalog = {
    name: "有下文 · Afterword Fox Kit",
    strokeWidth: iconsApi.strokeWidth,
    defaultColor: iconsApi.defaultColor,
    icons: iconsApi.icons.map((icon) => ({
      id: icon.id,
      label: icon.label,
      category: icon.category,
      tags: icon.tags,
      material: icon.material,
      hasSelectedState: Boolean(icon.selectedBody),
      svg: `icons/${icon.id}.svg`,
      selectedSvg: icon.selectedBody ? `icons/${icon.id}-selected.svg` : null,
    })),
    scenes: scenes.map((scene) => ({
      id: scene.id,
      label: scene.label,
      description: scene.description,
      svg: `scenes/${scene.id}.svg`,
    })),
    motions: motions.map((motion) => ({
      id: motion.id,
      label: motion.label,
      description: motion.description,
      duration: motion.duration,
      loop: motion.loop,
      sceneId: motion.sceneId,
      type: motion.type,
    })),
    originalGlyphMap: coverage.originalGlyphMap,
  };

  writeFile(path.join(kitDir, "catalog.json"), stableJson(catalog));
  writeFile(path.join(kitDir, "coverage.json"), stableJson(coverage));

  if (coverage.missingSourceGlyphs.length) {
    console.error(
      `Afterword icon coverage failed: ${coverage.missingSourceGlyphs.map((item) => item.glyph).join(", ")}`
    );
    process.exitCode = 1;
    return;
  }

  console.log(
    `Afterword fox kit exported ${iconsApi.icons.length} icons, ${scenes.length} scenes, ${motions.length} motions. ${coverage.coveredSourceGlyphs}/${coverage.totalSourceGlyphs} source glyphs covered.`
  );
}

main();
