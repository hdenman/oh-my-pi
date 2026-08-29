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
      (self: super: {
        bun = super.bun_1_3_13.overrideAttrs (oldAttrs: {
          version = "1.3.14";
          src = self.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-x64.zip";
            sha256 = "sha256-n6kLgQ2p5E0P5hP+M8fXk1V9X50E5N3E4N7Q1C1D1F1G1H1I1J1K1L1M1N1O1P1Q1R1S1T1U1V1W1X1Y1Z1a1b1c1d1e1f1g1h1i1j1k1l1m1n1o1p1q1r1s1t1u1v1w1x1y1z1"; # replace with actual sha256
          };
        });
      })
    ];
  }).bun;

in
  import (fetchTarball "https://github.com/devenv/devenv/archive/main.tar.gz").outPath {}
