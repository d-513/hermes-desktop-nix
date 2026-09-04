{
  lib,
  stdenv,
  callPackage,
  makeShellWrapper,
  writeText,
  electron,
  xdg-utils,
  addDriverRunpath,
  hermes-src,
  npm-lockfile-fix,
  # GUI launchers do not read the shell profile. The module passes
  # HERMES_DESKTOP_REMOTE_URL here. Never put secrets in extraEnv: --set
  # values land in the Nix store.
  extraEnv ? { },
  extraRun ? [ ],
}:

let
  hermesNpmLib = callPackage (hermes-src + "/nix/lib.nix") {
    inherit npm-lockfile-fix;
  };

  extraEnvFlags = lib.concatMapStrings (
    name:
    " \\\n      --set ${lib.escapeShellArg name} ${lib.escapeShellArg (toString extraEnv.${name})}"
  ) (lib.attrNames extraEnv);

  extraRunFlags = lib.concatMapStrings (line: " \\\n      --run ${lib.escapeShellArg line}") extraRun;

  targetArch =
    if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else if stdenv.hostPlatform.isx86_64 then
      "x64"
    else
      throw "hermes-desktop: unsupported host arch for node-pty staging";

  renderer = hermesNpmLib.buildNpmPackage {
    dirs = [
      "apps/desktop"
      "apps/shared"
    ];
    pname = "hermes-desktop-renderer";

    doCheck = true;

    buildPhase = ''
      runHook preBuild

      patchShebangs .

      pushd apps/desktop
        npm exec -- tsc -b
        npm exec -- vite build
        node scripts/bundle-electron-main.mjs

        ${lib.getExe hermesNpmLib.node-gyp} rebuild \
          --directory=../../node_modules/node-pty \
          --build-from-source \
          --runtime=electron \
          --target=${electron.version} \
          --nodedir=${electron.headers} \
          --disturl="" \
          --offline

        node scripts/stage-native-deps.mjs linux ${targetArch}
      popd

      runHook postBuild
    '';

    checkPhase = ''
      runHook preCheck

      pushd apps/desktop
        npm run postbuild
        STAGED_PTY_NODE="./dist/node_modules/node-pty/build/Release/pty.node"
        if [ ! -f "$STAGED_PTY_NODE" ]; then
          echo "FATAL: Missing staged node-pty native binary at $STAGED_PTY_NODE"
          exit 1
        fi
      popd

      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -rn apps/desktop/dist $out/
      echo '{"schemaVersion":1,"commit":"nix-dummy-commit","branch":"nix","dirty":false,"source":"nix"}' > $out/install-stamp.json
      cp -n apps/desktop/package.json $out/
      runHook postInstall
    '';
  };

  desktopFile = writeText "hermes.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Hermes
    Comment=Desktop client for a remote Hermes Agent server
    Exec=@out@/bin/hermes-desktop %U
    Icon=hermes
    StartupWMClass=Hermes
    Categories=Development;Utility;
    MimeType=x-scheme-handler/hermes;
  '';
in
stdenv.mkDerivation {
  pname = "hermes-desktop";
  inherit (renderer) version;

  dontUnpack = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = [ makeShellWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/hermes-desktop $out/bin $out/share/applications
    cp -r ${renderer}/* $out/share/hermes-desktop/

    substituteInPlace $out/share/hermes-desktop/dist/electron-main.mjs \
      --replace-fail "process.resourcesPath" "'$out/share/hermes-desktop'"

    install -Dm644 ${hermes-src}/apps/desktop/assets/icon.png \
      $out/share/icons/hicolor/1024x1024/apps/hermes.png

    substitute ${desktopFile} $out/share/applications/hermes.desktop \
      --subst-var-by out "$out"

    # Client-only: ignore PATH hermes so first launch offers a remote gateway.
    makeShellWrapper ${lib.getExe electron} $out/bin/hermes-desktop \
      --add-flags "$out/share/hermes-desktop" \
      --add-flags --class=Hermes \
      --add-flags --name=Hermes \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${addDriverRunpath.driverLink}/lib \
      --prefix XDG_DATA_DIRS : "$out/share" \
      --set-default CHROME_DESKTOP hermes.desktop \
      --set ELECTRON_IS_DEV 0 \
      --unset HERMES_DESKTOP_HERMES \
      --unset HERMES_DESKTOP_HERMES_ROOT \
      --set HERMES_DESKTOP_IGNORE_EXISTING 1${extraEnvFlags}${extraRunFlags} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

    runHook postInstall
  '';

  passthru = {
    updateScript = ./update.sh;
  };

  meta = {
    description = "Hermes Desktop Electron client (remote Hermes Agent server)";
    homepage = "https://github.com/NousResearch/hermes-agent";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "hermes-desktop";
  };
}
