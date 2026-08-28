let
  # Pinned nixpkgs-unstable @ ede7a04 (2026-05-03) — bun 1.3.13 base, with overlay below.
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/ede7a04c7ae52bfc797a963f6bcf82bc56ed760f.tar.gz";
    sha256 = "1l1svkxkas9irwk3n5qhq998vzdnbxc879s8702chnfylnc8dp6k";
  };

  # Bun 1.3.14 via Nixpkgs unstable overlay.
  bun = (import nixpkgs {
    system = "x86_64-linux"; # only used to choose which version of bun to get
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        # Override to bun 1.3.14 to match "packageManager": "bun@1.3.14" in package.json.
        # Sources keyed by system — mirrors the upstream passthru.sources pattern.
        bun = prev.bun.overrideAttrs (old: rec {
          version = "1.3.14";
          src =
            {
              "aarch64-darwin" = final.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-aarch64.zip";
                hash = "sha256-2LliIYKK1vl6x6wKt+lYcjQa92MAHogD6CZ2UsJlJiA=";
              };
              "x86_64-linux" = final.fetchurl {
                # baseline build: no AVX2 required (works on older x86_64 CPUs e.g. Celeron J3455)
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64-baseline.zip";
                hash = "sha256-oGOQiuCLeFLKEJObvcbO7T3avOj7lALc6D1l1zs25sc=";
              };
              "aarch64-linux" = final.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-aarch64.zip";
                hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
              };
            }
            .${final.stdenv.hostPlatform.system}
              or (throw "bun 1.3.14: unsupported system ${final.stdenv.hostPlatform.system}");
          # postPatchelf runs `bun completions` inside the sandbox — always fails for
          # version bumps (binary must execute). We don't need shell completions here.
          postPhases = [ ];
          postPatchelf = "";
        });
      })
    ];
  }).bun;

in

pkgs.mkShell {
  packages = [
    pkgs.bun     # 1.3.14 (via overlay above)
    pkgs.bazelisk # reads .bazelversion (9.2.0) and downloads the right Bazel on first use
    pkgs.rustup  # manages the nightly toolchain; cargo ends up at ~/.cargo/bin

    # bazelisk's binary is named `bazelisk`; wrap it as `bazel` so build-local.ts
    # and any manual invocations work without extra thought.
    (pkgs.writeShellScriptBin "bazel" ''exec ${pkgs.bazelisk}/bin/bazelisk "$@"'')
  ];

  shellHook = ''
    # Ensure the nightly toolchain the crate requires is present.
    # Idempotent: rustup no-ops if already installed.
    export RUSTUP_HOME="''${RUSTUP_HOME:-$HOME/.rustup}"
    export CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    export PATH="$CARGO_HOME/bin:$PATH"
    if ! cargo +nightly-2026-04-29 --version >/dev/null 2>&1; then
      echo "Installing Rust nightly-2026-04-29..."
      rustup toolchain install nightly-2026-04-29 --profile minimal
    fi
  '';
}
