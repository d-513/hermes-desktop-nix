# Hermes Desktop for Nix

[Hermes Desktop](https://github.com/NousResearch/hermes-agent/tree/main/apps/desktop)
as an Electron **client** for a Hermes Agent server that already runs somewhere
else (VPS, home box, Tailscale). MIT; not affiliated with Nous Research.

This is **not** the Hermes Server / CLI package, and it is **not**
`nix run github:NousResearch/hermes-agent#desktop`. That official output wraps
a Nix-built local `hermes` binary and is the right choice only if the agent
should run on the same machine. This flake builds the UI from the same source
and leaves the agent off the machine.

```sh
nix run github:d-513/hermes-desktop-nix
```

On first launch, choose **Connect to existing Hermes** and point it at
`hermes serve` (typically port 9119). Or set the URL declaratively (below).

## Install

### NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hermes-desktop-nix = {
      url = "github:d-513/hermes-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

```nix
{ inputs, ... }:
{
  imports = [ inputs.hermes-desktop-nix.nixosModules.default ];
  programs.hermes-desktop = {
    enable = true;
    remoteUrl = "https://hermes.example.com";
    sessionTokenFile = "/run/secrets/hermes-desktop-token";
  };
}
```

`sessionTokenFile` must be a **runtime** path (sops-nix/agenix `.path`). A Nix
path would copy the token into the world-readable store.

Without the module, put the package on `environment.systemPackages` and configure
the gateway in the app.

### Home Manager

Same flake input, then:

```nix
{ inputs, ... }:
{
  imports = [ inputs.hermes-desktop-nix.homeManagerModules.default ];
  programs.hermes-desktop = {
    enable = true;
    remoteUrl = "https://hermes.example.com";
    sessionTokenFile = "/run/secrets/hermes-desktop-token";
  };
}
```

### Overlay (`pkgs.hermes-desktop`)

```nix
{
  nixpkgs.overlays = [ inputs.hermes-desktop-nix.overlays.default ];
  environment.systemPackages = [ pkgs.hermes-desktop ];
}
```

### Profile

```sh
nix profile install github:d-513/hermes-desktop-nix
```

## Remote server

On the host that should run the agent (not this flake):

```sh
hermes serve --host 0.0.0.0 --port 9119
```

Use whatever bind/auth your network needs (Tailscale, OAuth, a pinned session
token). Desktop talks to that process; it does not start it.

## Wayland

```nix
environment.sessionVariables.NIXOS_OZONE_WL = "1";
```

Without that, it runs under XWayland/X11.

## Updates

The in-app updater cannot write into the Nix store. This flake pins a
**GitHub Release tag** of `NousResearch/hermes-agent` (not `main`).
`.github/workflows/update.yml` runs `./update.sh` every six hours and pushes
when a new release appears.

On your machine:

```sh
./update.sh                 # latest non-prerelease
./update.sh v2026.8.31      # pin a specific tag
nix flake update hermes-desktop-nix
```

then rebuild. `nix flake update` without an attribute also updates nixpkgs.
`nix flake update hermes-agent` only re-fetches the already-pinned tag.

## Why not the official flake?

| | `hermes-agent#desktop` | this flake |
| --- | --- | --- |
| Builds | Electron UI + Python agent (uv2nix) | Electron UI only |
| Default backend | local Nix-wrapped `hermes` | remote gateway / first-launch connect UI |
| Closure | agent + skills + runtime tools | electron + renderer |
