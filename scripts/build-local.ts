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

// --- native addon: ensure sentinel matches current package version ---
const nativesPackageJson = (await Bun.file(
	path.join(repoRoot, "packages", "natives", "package.json"),
).json()) as { version: string };
const nativesVersion = nativesPackageJson.version;
const platformTag = `${process.platform}-${process.arch}`;
const nodeFilename =
	process.arch === "x64"
		? `pi_natives.${platformTag}-gnu.node`
		: `pi_natives.${platformTag}.node`;
const nodeFilePath = path.join(repoRoot, "packages", "natives", "native", nodeFilename);
const versionSentinel = `__piNativesV${nativesVersion.replace(/[^A-Za-z0-9]/g, "_")}`;

// Search for the sentinel symbol name in the binary — a missing or wrong-version .node
// will not contain it and needs a cargo rebuild.
const sentinelFound =
	(await $`grep -qF ${versionSentinel} ${nodeFilePath}`.nothrow().quiet()).exitCode === 0;

if (!sentinelFound) {
	console.log(`Native addon missing sentinel ${versionSentinel} — rebuilding from source...`);

	// Cargo lives under ~/.cargo/bin; cmake (from homebrew) may not be on PATH in mise envs.
	const cargoBin = Bun.which("cargo") ?? path.join(os.homedir(), ".cargo", "bin", "cargo");
	const cargoDir = path.dirname(cargoBin);
	// Collect extra PATH dirs for system build tools cargo invokes (cmake, cc, etc.).
	const extraDirs = [cargoDir, "/opt/homebrew/bin", "/usr/local/bin"].filter(d => {
		try { return require("node:fs").statSync(d).isDirectory(); } catch { return false; }
	});
	const napiEnv = {
		...Bun.env,
		PATH: [...new Set([...extraDirs, ...(Bun.env.PATH ?? "").split(":")])].join(":"),
		// pkg-config for homebrew-installed libs (e.g. opus) so audiopus_sys skips cmake.
		PKG_CONFIG_PATH: [
			"/opt/homebrew/lib/pkgconfig",
			"/usr/local/lib/pkgconfig",
			...(Bun.env.PKG_CONFIG_PATH ?? "").split(":").filter(Boolean),
		].join(":"),
		// cmake 4.x dropped compat with old cmake_minimum_required — pass the override
		// as fallback in case pkg-config misses and cmake is invoked anyway.
		CMAKE_ARGS: "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
	};

	await $`bun node_modules/.bin/napi build --platform --release --no-js --package-json-path packages/natives/package.json --manifest-path crates/pi-natives/Cargo.toml --output-dir packages/natives/native/`
		.cwd(repoRoot)
		.env(napiEnv);

	// Clear the stale versioned cache so the new binary re-extracts the fresh addon.
	const staleCache = path.join(os.homedir(), ".omp", "natives", nativesVersion);
	await fs.rm(staleCache, { recursive: true, force: true });
	console.log("Native addon rebuilt.");
}

// --- generate embedded assets (stats client, tool views) ---
console.log("Generating embedded assets...");
await $`bun run gen:stats`.cwd(repoRoot).quiet();
await $`bun --cwd=packages/collab-web run gen:tool-views`.cwd(repoRoot).quiet();

// --- embed native addon ---
console.log("Embedding native addon...");
await $`bun run gen:native`.cwd(repoRoot).quiet();

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
