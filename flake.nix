{
  description = "Hermes Desktop — Electron client for a remote Hermes Agent server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Release tag, not main. flake = false so we don't evaluate uv2nix / the agent.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.9.11";
      flake = false;
    };
    npm-lockfile-fix = {
      url = "github:jeslie0/npm-lockfile-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      hermes-agent,
      npm-lockfile-fix,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      hermesDesktop =
        pkgs:
        pkgs.callPackage ./package.nix {
          hermes-src = hermes-agent;
          npm-lockfile-fix = npm-lockfile-fix.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          hermes-desktop = hermesDesktop (pkgsFor system);
        in
        {
          inherit hermes-desktop;
          default = hermes-desktop;
        }
      );

      overlays.default = final: _prev: {
        hermes-desktop = hermesDesktop final;
      };

      nixosModules.default = import ./module.nix {
        inherit self;
        isHomeManager = false;
      };

      homeManagerModules.default = import ./module.nix {
        inherit self;
        isHomeManager = true;
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      checks = forAllSystems (system: {
        hermes-desktop = self.packages.${system}.hermes-desktop;
      });
    };
}
