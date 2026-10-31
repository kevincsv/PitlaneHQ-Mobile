// node tools/check-strings.mjs: the phones' texts are one list. Android's ui/I18n.kt is the source and iOS's I18n.swift
// follows it; this says which keys one of them lacks and which texts differ, and fails when there is any.
import { readFileSync } from "node:fs";
const root = new URL("..", import.meta.url);
const read = (p) => readFileSync(new URL(p, root), "utf8");
const S = String.raw`"((?:[^"\\]|\\.)*)"`;
// a Kotlin "\$" is a "$" in Swift; both unescape the same otherwise
const un = (s) => s.replace(/\\\$/g, "$").replace(/\\"/g, '"').replace(/\\\\/g, "\\");
function parse(src, re) {
  const m = new Map();
  for (const x of src.matchAll(re)) m.set(x[1], [un(x[2]), un(x[3]), un(x[4])]);
  return m;
}
const kt = parse(read("app/src/main/java/com/pitlanehq/android/ui/I18n.kt"), new RegExp(`${S}\\s+to\\s+L\\(\\s*${S}\\s*,\\s*${S}\\s*,\\s*${S}\\s*\\)`, "g"));
const sw = parse(read("ios/PitlaneHQ/I18n.swift"), new RegExp(`${S}\\s*:\\s*\\(\\s*${S}\\s*,\\s*${S}\\s*,\\s*${S}\\s*\\)`, "g"));
const onlyKt = [...kt.keys()].filter((k) => !sw.has(k)), onlySw = [...sw.keys()].filter((k) => !kt.has(k));
const differ = [...kt.keys()].filter((k) => sw.has(k) && kt.get(k).join("\u0001") !== sw.get(k).join("\u0001"));
if (onlyKt.length) console.log("Only on Android (" + onlyKt.length + "): " + onlyKt.join(", "));
if (onlySw.length) console.log("Only on iOS (" + onlySw.length + "): " + onlySw.join(", "));
for (const k of differ) console.log(`Different "${k}":\n  Android ${JSON.stringify(kt.get(k))}\n  iOS     ${JSON.stringify(sw.get(k))}`);
console.log(`strings: ${kt.size} on Android, ${sw.size} on iOS`);
if (onlyKt.length || onlySw.length || differ.length) process.exit(1);
