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
        # Override to bun 1.4.0: fixes bun build --compile segfault on NixOS (bun issue #31023,
        # fixed in 1.4.0 via PR #31024 — patchelf PT_LOAD selection bug in write_bun_section).
        # Sources keyed by system — mirrors the upstream passthru.sources pattern.
        bun = prev.bun.overrideAttrs (old: rec {
          version = "1.4.0";
          src =
            {
              "aarch64-darwin" = final.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-darwin-aarch64.zip";
                hash = "sha256-xmnpf2Fk4cluBwF0jbmN+ndJKQjL2DlMdVcTSnNd44E=";
              };
              "x86_64-linux" = final.fetchurl {
                # baseline build: no AVX2 required (works on older x86_64 CPUs e.g. Celeron J3455)
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64-baseline.zip";
                hash = "sha256-GE+0WV8NQBohfPfHjBvEMLqDMU2reouUgFurv3+nCX8=";
              };
              "aarch64-linux" = final.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-aarch64.zip";
                hash = "sha256-SxozLuhhmD65O8/m93D/+U4+MbLDiL2uo8jtNeWO7Q4=";
              };
            }
            .${final.stdenv.hostPlatform.system}
              or (throw "bun 1.4.0: unsupported system ${final.stdenv.hostPlatform.system}");
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
    pkgs.pkg-config
    pkgs.libopus # audiopus_sys links opus; pkg-config finds it, skipping cmake
    pkgs.cmake   # fallback if pkg-config path isn't found

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

    # Point pkg-config at nix-provided libopus so audiopus_sys skips cmake.
    export PKG_CONFIG_PATH="${pkgs.libopus.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    # cmake policy compat flag (cmake 4.x dropped old minimum_required handling)
    export CMAKE_ARGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 ''${CMAKE_ARGS:-}"
  '';
}
