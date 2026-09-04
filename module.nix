{
  self,
  isHomeManager,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.hermes-desktop;
in
{
  options.programs.hermes-desktop = {
    enable = lib.mkEnableOption "Hermes Desktop (Electron client for a remote Hermes server)";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "hermes-desktop-nix.packages.\${system}.default";
      description = "Hermes Desktop package to wrap and install.";
    };

    remoteUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://hermes.example.com";
      description = ''
        Gateway URL for `hermes serve` on the remote host. Sets
        HERMES_DESKTOP_REMOTE_URL so the app skips local backend spawn.
        Leave null to configure the connection in the first-launch UI.
      '';
    };

    sessionTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/hermes-desktop-token";
      description = ''
        Runtime path whose contents are read at each launch into
        HERMES_DESKTOP_REMOTE_TOKEN. Must be an absolute path that exists
        on the machine (sops-nix/agenix `.path`), never a Nix path — that
        would copy the token into the world-readable store.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      wrapped = cfg.package.override {
        extraEnv = lib.optionalAttrs (cfg.remoteUrl != null) {
          HERMES_DESKTOP_REMOTE_URL = cfg.remoteUrl;
        };
        extraRun = lib.optionals (cfg.sessionTokenFile != null) [
          ''export HERMES_DESKTOP_REMOTE_TOKEN="$(tr -d '[:space:]' < ${lib.escapeShellArg cfg.sessionTokenFile})"''
        ];
      };
    in
    if isHomeManager then
      { home.packages = [ wrapped ]; }
    else
      { environment.systemPackages = [ wrapped ]; }
  );
}
