# Hermes Desktop Nix flake

Electron **client** for a remote `hermes serve`. Not Hermes Server, and not
`github:NousResearch/hermes-agent#desktop` (that output wraps a Nix-built
local `hermes` via `HERMES_DESKTOP_HERMES`).

## Why this exists

Upstream Desktop can bootstrap a local Python agent into `~/.hermes`. Official
Nix packaging always points the app at that agent. This flake builds only the
UI and forces remote-client resolver behaviour:

- no `HERMES_DESKTOP_HERMES` / `HERMES_DESKTOP_HERMES_ROOT`
- `HERMES_DESKTOP_IGNORE_EXISTING=1` so a PATH `hermes` is not used
- optional `HERMES_DESKTOP_REMOTE_URL` + token-from-file

## Layout

- `flake.nix` — packages, overlay, NixOS + Home Manager modules
- `package.nix` — renderer via upstream `nix/lib.nix`, client wrapper
- `module.nix` — `programs.hermes-desktop` (`remoteUrl`, `sessionTokenFile`)
- `update.sh` — pin `hermes-agent` to a GitHub Release tag

`hermes-agent` is a `flake = false` input of a **release tag**, not `main`.
`./update.sh` rewrites that tag and refreshes `flake.lock`. `npm-lockfile-fix`
is required by upstream `nix/lib.nix`. Do not add uv2nix / pyproject-nix.

A stale pin still builds: the tag is immutable. You only get a hash mismatch
if GitHub rewrote the tag. `.github/workflows/update.yml` runs every six hours
and pushes when `releases/latest` moves.

## Wrap pitfalls

- Secrets: `sessionTokenFile` (module) or `extraRun` (package override). Never `extraEnv`.
- `makeShellWrapper` so `${NIXOS_OZONE_WL:+…}` expands at launch.
- node-pty is rebuilt against `electron.headers` (same ABI as nixpkgs `electron`).
- `process.resourcesPath` is patched to `$out/share/hermes-desktop`.
- In-app updater cannot write to the Nix store; bump via `./update.sh`.

## Do not

- Set `HERMES_DESKTOP_HERMES` to a dummy binary (the app will try to spawn it).
- Point `hermes-agent` at the default branch; keep a `v…` release tag.
- Copy tokens into the store with a Nix `path` type.
