// node tools/check-analysis.mjs [path to Pitwall-test]: the phones run the web's lap analysis and coach. Both apps' copies
// of pitwall-analysis.js must be the same file; with the Pitwall-test repository beside this one (or named), they must be
// its web/dist file too, and that repository's analysis test runs on the Android copy, so the phones give the same
// corners, tips and plan as the PC and the web.
import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = new URL("..", import.meta.url);
const android = fileURLToPath(new URL("app/src/main/assets/pitwall-analysis.js", root)), ios = fileURLToPath(new URL("ios/Resources/pitwall-analysis.js", root));
const a = readFileSync(android, "utf8"), i = readFileSync(ios, "utf8");
if (a !== i) { console.log("The Android and iOS copies of pitwall-analysis.js differ: run tools/sync-analysis.sh"); process.exit(1); }
const pt = process.argv[2] || fileURLToPath(new URL("../Pitwall-test", root));
const web = pt + "/web/dist/pitwall-analysis.js";
if (!existsSync(web)) { console.log("analysis: both copies are the same (no Pitwall-test beside this repository to compare with)"); process.exit(0); }
if (readFileSync(web, "utf8") !== a) { console.log("The phones' pitwall-analysis.js is not the web's: run tools/sync-analysis.sh"); process.exit(1); }
execFileSync(process.execPath, [pt + "/cloud/test/analysis.test.mjs"], { cwd: pt, env: { ...process.env, PW_ANALYSIS_FILE: android }, stdio: "inherit" });
console.log("analysis: the phones' copy is the web's and gives the fixture's answers");
