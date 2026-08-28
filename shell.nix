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
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64.zip";
                hash = "sha256-lR7iruhV8IWVruxiJSJqKY0/6oOj3NZGXAnLzN9+hI8=";
              };
              "aarch64-linux" = final.fetchurl {
                url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-aarch64.zip";
                hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
              };
            }
            .${final.stdenv.hostPlatform.system}
              or (throw "bun 1.3.14: unsupported system ${final.stdenv.hostPlatform.system}");
        });
      })
    ];
  }).bun;

in
  import (fetchTarball "https://github.com/devenv/devenv/archive/main.tar.gz").outPath {}
