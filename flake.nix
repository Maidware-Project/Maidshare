{
  description = "Maidshare - send files and links from linux to android (Maidware)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        py = pkgs.python3;
        runtimePath = pkgs.lib.makeBinPath [
          pkgs.bash pkgs.coreutils pkgs.curl pkgs.openssl py
          pkgs.kdePackages.kdeconnect-kde pkgs.android-tools pkgs.qrencode
          pkgs.kdialog pkgs.zenity
        ];
        guiRuntime = pkgs.lib.makeBinPath [ py pkgs.qt6.qtbase ];
        maidshare = pkgs.stdenv.mkDerivation {
          pname = "maidshare";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.makeWrapper pkgs.wrapGAppsHook3 pkgs.qt6.wrapQtAppsHook ];
          dontWrapGApps = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/libexec/maidshare $out/share/maidshare
            cp -a bin/* $out/libexec/maidshare/
            chmod +x $out/libexec/maidshare/maidshare $out/libexec/maidshare/backends/*.sh 2>/dev/null || true
            chmod +x $out/libexec/maidshare/maidshare-gui $out/libexec/maidshare/maid-cert.sh 2>/dev/null || true
            makeWrapper $out/libexec/maidshare/maidshare $out/bin/maidshare \
              --prefix PATH : ${runtimePath}
            if [ -f $out/libexec/maidshare/maidshare-gui ]; then
              makeWrapper $out/libexec/maidshare/maidshare-gui $out/bin/maidshare-gui \
                --prefix PATH : ${runtimePath}:${guiRuntime}
            fi
            [ -d desktop ] && mkdir -p $out/share/applications && cp -a desktop/*.desktop $out/share/applications/ 2>/dev/null || true
            [ -d servicemenu ] && mkdir -p $out/share/kio/servicemenus && cp -a servicemenu/* $out/share/kio/servicemenus/ 2>/dev/null || true
            cp -a README.md LICENSE THIRD-PARTY-NOTICES.md $out/share/maidshare/ 2>/dev/null || true
            runHook postInstall
          '';
          postFixup = ''
            for f in $out/bin/maidshare-gui; do [ -f "$f" ] && wrapQtApp "$f" || true; done
          '';
          meta = with pkgs.lib; {
            description = "send files and links from linux to android (Maidware)";
            homepage = "https://github.com/Maidware-Project/Maidshare";
            license = licenses.gpl3Plus;
            platforms = platforms.linux;
            mainProgram = "maidshare";
          };
        };
      in {
        packages.default = maidshare;
        packages.maidshare = maidshare;
        apps.default = { type = "app"; program = "${maidshare}/bin/maidshare"; };
        apps.gui = { type = "app"; program = "${maidshare}/bin/maidshare-gui"; };
      }
    ) // {
      homeManagerModules.default = { config, lib, pkgs, ... }: {
        options.programs.maidshare.enable = lib.mkEnableOption "Maidshare (Maidware)";
        config = lib.mkIf config.programs.maidshare.enable {
          home.packages = [ self.packages.${pkgs.system}.default ];
        };
      };
    };
}
