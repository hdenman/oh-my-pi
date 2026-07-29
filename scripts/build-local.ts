#!/usr/bin/env bun
/**
 * Build a local omp binary from the current working tree and install it.
 *
 * Output:  ~/.local/bin/omp.<short-sha>.<YYYYMMDD>
 * Symlink: ~/.local/bin/omp -> above (force-replaced)
 */

import * as fs from "node:fs/promises";
import { createRequire } from "node:module";
import * as os from "node:os";
import * as path from "node:path";
import { $ } from "bun";
import { compileCodingAgent } from "../packages/coding-agent/scripts/compile-binary";

const repoRoot = path.join(import.meta.dir, "..");
const entrypoint = path.join(repoRoot, "packages", "coding-agent", "src", "cli.ts");

const transformersManifest: unknown = createRequire(import.meta.url)(
	"@huggingface/transformers/package.json",
);
if (
	typeof transformersManifest !== "object" ||
	transformersManifest === null ||
	!("version" in transformersManifest) ||
	typeof transformersManifest.version !== "string"
) {
	throw new Error("@huggingface/transformers package manifest has no string version");
}
const transformersVersion = transformersManifest.version;

// --- stamp ---
const shortSha = (await $`git -C ${repoRoot} rev-parse --short HEAD`.quiet().text()).trim();
const date = new Date()
	.toISOString()
	.slice(0, 10)
	.replace(/-/g, "");
const stamp = `${shortSha}.${date}`;

const localBin = path.join(os.homedir(), ".local", "bin");
const outfile = path.join(localBin, `omp.${stamp}`);
const symlink = path.join(localBin, "omp");

await fs.mkdir(localBin, { recursive: true });

// --- build ---
console.log(`Building omp.${stamp} ...`);
const isDarwin = process.platform === "darwin";
await compileCodingAgent({
	repoRoot,
	entrypoint,
	outfile,
	transformersVersion,
	// local build: no minification, no cross-compile
	skipBuiltinCodesign: isDarwin,
});

if (isDarwin) {
	await $`codesign --force --sign - ${outfile}`.quiet();
}

// --- link ---
// Remove whatever is already at the symlink path (file, symlink, or nothing).
await fs.rm(symlink, { force: true });
await fs.symlink(outfile, symlink);

console.log(`Installed: ${symlink} -> ${outfile}`);
