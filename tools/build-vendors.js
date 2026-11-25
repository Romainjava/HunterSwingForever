// Generates VendorData.lua from data/vendors.json.
// Usage: node tools/build-vendors.js  (or bun tools/build-vendors.js)
//
// Sources of the data:
//   - pfQuest database (MIT, Copyright (c) 2017-2021 Eric Mauser (Shagu))
//   - Wowhead Classic, for which NPCs sell ammo
//   - positions corrected for WoW Forever
"use strict";

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const input = path.join(root, "data", "vendors.json");
const output = path.join(root, "VendorData.lua");

const data = JSON.parse(fs.readFileSync(input, "utf8"));

const maps = data.maps || {};
const items = data.items || [];
const vendors = data.vendors || [];

const EXPECTED = { vendors: 139, items: 10, maps: 45 };
if (vendors.length !== EXPECTED.vendors) {
  throw new Error(`expected ${EXPECTED.vendors} vendors, got ${vendors.length}`);
}
if (items.length !== EXPECTED.items) {
  throw new Error(`expected ${EXPECTED.items} items, got ${items.length}`);
}
if (Object.keys(maps).length !== EXPECTED.maps) {
  throw new Error(`expected ${EXPECTED.maps} maps, got ${Object.keys(maps).length}`);
}

const kindById = new Map(items.map((item) => [item.id, item.kind]));

function quote(text) {
  return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function number(value) {
  if (!Number.isFinite(value)) {
    throw new Error(`not a number: ${value}`);
  }
  return String(value);
}

const lines = [];
lines.push("-- Hunter Swing Forever by Illusion");
lines.push("-- GENERATED FILE, do not edit by hand: run `node tools/build-vendors.js`.");
lines.push("--");
lines.push("-- Sources:");
lines.push("--   pfQuest database, MIT licence, Copyright (c) 2017-2021 Eric Mauser (Shagu)");
lines.push("--   Wowhead Classic: which NPCs sell ammo");
lines.push("--   positions corrected for WoW Forever");
lines.push("local ADDON, ns = ...");
lines.push("");
lines.push("ns.vendorItems = {");
for (const item of items) {
  lines.push(
    `\t[${item.id}] = { name = ${quote(item.name)}, kind = ${quote(item.kind)}, level = ${number(
      item.requiredLevel
    )} },`
  );
}
lines.push("}");
lines.push("");
lines.push("ns.vendorMaps = {");
for (const [id, name] of Object.entries(maps)) {
  lines.push(`\t[${id}] = ${quote(name)},`);
}
lines.push("}");
lines.push("");
lines.push("ns.vendorRows = {");
for (const vendor of vendors) {
  const firstKnown = (vendor.items || []).find((id) => kindById.has(id));
  if (firstKnown === undefined) {
    throw new Error(`vendor ${vendor.npc} (${vendor.name}) sells no known ammo item`);
  }
  const kind = kindById.get(firstKnown);
  const itemList = (vendor.items || []).join(", ");
  const note = vendor.note ? `, note = ${quote(vendor.note)}` : "";
  lines.push(
    `\t{ mapId = ${number(vendor.mapId)}, x = ${number(vendor.x)}, y = ${number(vendor.y)}, npc = ${number(
      vendor.npc
    )}, name = ${quote(vendor.name)}, faction = ${quote(vendor.faction)}, kind = ${quote(
      kind
    )}, items = { ${itemList} }${note} },`
  );
}
lines.push("}");
lines.push("");

const notes = vendors.filter((vendor) => vendor.note);
lines.push("ns.vendorNotes = {");
for (const vendor of notes) {
  lines.push(`\t[${vendor.npc}] = ${quote(vendor.note)},`);
}
lines.push("}");
lines.push("");

fs.writeFileSync(output, lines.join("\n"), { encoding: "utf8" });

const counts = vendors.reduce((acc, vendor) => {
  acc[vendor.faction] = (acc[vendor.faction] || 0) + 1;
  return acc;
}, {});
console.log(
  `VendorData.lua: ${vendors.length} vendors (A ${counts.A || 0}, H ${counts.H || 0}, N ${
    counts.N || 0
  }), ${items.length} items, ${Object.keys(maps).length} maps, ${notes.length} note(s).`
);
