#!/usr/bin/env node
/** Generate LVGL 9 ARGB8888 C assets from Phosphor SVGs (light + fill weights). */

import { Resvg } from "@resvg/resvg-js";
import { PNG } from "pngjs";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT_DIR = path.join(
  ROOT,
  "firmware/tab5/components/modulus_zig/assets/icons/generated"
);
const COLOR = "#E8EAED";
const SIZES = [24, 32];
const SIZE40_ICONS = new Set(["power", "gear_six"]);

/** @type {Record<string, { stem: string, weight?: "light" | "fill" | "regular" }>} */
const ICONS = {
  power: { stem: "power", weight: "light" },
  gear: { stem: "gear", weight: "light" },
  gear_six: { stem: "gear-six", weight: "light" },
  battery_full: { stem: "battery-vertical-full", weight: "light" },
  battery_high: { stem: "battery-vertical-high", weight: "light" },
  battery_medium: { stem: "battery-vertical-medium", weight: "light" },
  battery_low: { stem: "battery-vertical-low", weight: "light" },
  battery_empty: { stem: "battery-vertical-empty", weight: "light" },
  battery_charging: { stem: "battery-charging-vertical", weight: "light" },
  battery_warning: { stem: "battery-warning-vertical", weight: "light" },
  play: { stem: "play", weight: "fill" },
  pause: { stem: "pause", weight: "fill" },
  stop: { stem: "stop", weight: "fill" },
  spindle: { stem: "arrows-clockwise", weight: "light" },
  coolant: { stem: "drop", weight: "light" },
  fan: { stem: "fan", weight: "light" },
  single_step: { stem: "steps", weight: "light" },
  house: { stem: "house", weight: "light" },
  house_fill: { stem: "house", weight: "fill" },
  arrow_up: { stem: "arrow-up", weight: "regular" },
  arrow_down: { stem: "arrow-down", weight: "regular" },
  caret_up: { stem: "caret-up", weight: "light" },
  caret_down: { stem: "caret-down", weight: "light" },
  x: { stem: "x", weight: "light" },
  mpg: { stem: "joystick", weight: "light" },
  cnc: { stem: "cpu", weight: "light" },
  monitor: { stem: "monitor", weight: "light" },
  speaker: { stem: "speaker-high", weight: "light" },
  wifi: { stem: "wifi-high", weight: "light" },
  bluetooth: { stem: "bluetooth", weight: "light" },
  broadcast: { stem: "broadcast", weight: "light" },
  eye: { stem: "eye", weight: "light" },
  storage: { stem: "hard-drives", weight: "light" },
  lightning: { stem: "lightning", weight: "light" },
  backspace: { stem: "backspace", weight: "light" },
  check: { stem: "check", weight: "light" },
  zero: { stem: "number-circle-zero", weight: "regular" },
  cloud_fog: { stem: "cloud-fog", weight: "light" },
  scroll: { stem: "scroll", weight: "light" },
  crosshair: { stem: "crosshair", weight: "light" },
  spindle_ccw: { stem: "arrows-counter-clockwise", weight: "light" },
};

async function fetchSvg(stem, weight) {
  let base;
  let suffix;
  if (weight === "fill") {
    base = "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/fill";
    suffix = "-fill";
  } else if (weight === "regular") {
    base = "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/regular";
    suffix = "";
  } else {
    base = "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/light";
    suffix = "-light";
  }
  const url = `${base}/${stem}${suffix}.svg`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`missing ${url}: ${res.status}`);
  return await res.text();
}

function tintSvg(svg) {
  let out = svg;
  if (out.includes('fill="currentColor"')) {
    out = out.replace(/fill="currentColor"/g, `fill="${COLOR}"`);
  } else {
    out = out.replace("<svg ", `<svg fill="${COLOR}" `, 1);
  }
  if (out.includes('stroke="currentColor"')) {
    out = out.replace(/stroke="currentColor"/g, `stroke="${COLOR}"`);
  }
  return out;
}

function rasterize(svg, size) {
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: size },
    background: "rgba(0,0,0,0)",
  });
  const pngData = resvg.render().asPng();
  const png = PNG.sync.read(pngData);
  if (png.width !== size || png.height !== size) {
    throw new Error(`expected ${size}x${size}, got ${png.width}x${png.height}`);
  }
  return png;
}

function toLvglA8(name, png) {
  /* Alpha-only masks: LVGL image_recolor tints icons at runtime (F3 ROM + draw cost). */
  const rows = [];
  for (let y = 0; y < png.height; y++) {
    const bytes = [];
    for (let x = 0; x < png.width; x++) {
      const i = (png.width * y + x) << 2;
      bytes.push(png.data[i + 3]);
    }
    rows.push("    " + bytes.map((b) => `0x${b.toString(16).padStart(2, "0")}`).join(", ") + ",");
  }
  const sym = `mod_icon_${name}`;
  return `const LV_ATTRIBUTE_MEM_ALIGN uint8_t ${sym}_map[] = {\n${rows.join("\n")}\n};\n\nconst lv_image_dsc_t ${sym} = {\n    .header.w = ${png.width},\n    .header.h = ${png.height},\n    .header.stride = ${png.width},\n    .header.cf = LV_COLOR_FORMAT_A8,\n    .data = ${sym}_map,\n    .data_size = sizeof(${sym}_map),\n};`;
}

function writeSizeFile(size, chunks) {
  const p = path.join(OUT_DIR, `icon_assets_${size}.c`);
  const body = [
    '#include "icon_decl.h"',
    "",
    "#ifndef LV_ATTRIBUTE_MEM_ALIGN",
    "#define LV_ATTRIBUTE_MEM_ALIGN",
    "#endif",
    "",
    chunks.join("\n\n"),
    "",
  ].join("\n");
  fs.writeFileSync(p, body);
  console.log(`wrote ${p} (${chunks.length} icons)`);
}

function writeDecl(ids) {
  const lines = ["#pragma once", "#include <lvgl.h>", ""];
  for (const size of SIZES) {
    for (const id of ids) {
      lines.push(`LV_IMAGE_DECLARE(mod_icon_${id}_${size});`);
    }
  }
  for (const id of ids) {
    if (SIZE40_ICONS.has(id)) {
      lines.push(`LV_IMAGE_DECLARE(mod_icon_${id}_40);`);
    }
  }
  lines.push("");
  fs.writeFileSync(path.join(OUT_DIR, "icon_decl.h"), lines.join("\n"));
  console.log(`wrote ${path.join(OUT_DIR, "icon_decl.h")}`);
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const ids = Object.keys(ICONS);
  const bySize = Object.fromEntries(SIZES.map((s) => [s, []]));
  const by40 = [];

  for (const [iconId, spec] of Object.entries(ICONS)) {
    const weight = spec.weight ?? "light";
    const svg = tintSvg(await fetchSvg(spec.stem, weight));
    for (const size of SIZES) {
      const png = rasterize(svg, size);
      bySize[size].push(toLvglA8(`${iconId}_${size}`, png));
    }
    if (SIZE40_ICONS.has(iconId)) {
      const png = rasterize(svg, 40);
      by40.push(toLvglA8(`${iconId}_40`, png));
    }
  }

  for (const size of SIZES) writeSizeFile(size, bySize[size]);
  writeSizeFile(40, by40);
  writeDecl(ids);
  console.log("done");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
