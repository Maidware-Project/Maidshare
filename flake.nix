{
  description = "Maidshare - send files and links from linux to android (Maidware)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          py = pkgs.python3;
          runtimePath = pkgs.lib.makeBinPath [
            pkgs.bash pkgs.coreutils pkgs.curl pkgs.openssl py
            pkgs.kdePackages.kdeconnect-kde pkgs.android-tools pkgs.qrencode
            pkgs.kdialog pkgs.zenity
          ];
          maidshare = pkgs.stdenv.mkDerivation {
            pname = "maidshare";
            version = "0.1.0";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper pkgs.qt6.wrapQtAppsHook ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin $out/libexec/maidshare $out/share/maidshare $out/share/applications
              cp -a bin/* $out/libexec/maidshare/
              chmod +x $out/libexec/maidshare/maidshare 2>/dev/null || true
              find $out/libexec/maidshare -name '*.sh' -exec chmod +x {} +
              chmod +x $out/libexec/maidshare/maidshare-gui $out/libexec/maidshare/maid-cert.sh 2>/dev/null || true
              makeWrapper $out/libexec/maidshare/maidshare $out/bin/maidshare --prefix PATH : ${runtimePath}
              if [ -f $out/libexec/maidshare/maidshare-gui ]; then
                makeWrapper $out/libexec/maidshare/maidshare-gui $out/bin/maidshare-gui --prefix PATH : ${runtimePath}
              fi
              [ -d desktop ] && cp -a desktop/*.desktop $out/share/applications/ 2>/dev/null || true
              [ -d servicemenu ] && mkdir -p $out/share/kio/servicemenus && cp -a servicemenu/* $out/share/kio/servicemenus/ 2>/dev/null || true
              cp -a README.md LICENSE THIRD-PARTY-NOTICES.md $out/share/maidshare/ 2>/dev/null || true
              runHook postInstall
            '';
            postFixup = ''
              for f in $out/bin/maidshare-gui; do [ -f "$f" ] && wrapQtApp "$f" || true; done
            '';
            meta = with pkgs.lib; { description = "send files and links from linux to android (Maidware)"; homepage = "https://github.com/Maidware-Project/Maidshare"; license = licenses.gpl3Plus; platforms = platforms.linux; mainProgram = "maidshare"; };
          };
        in { default = maidshare; maidshare = maidshare; });

      apps = forAllSystems (system: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/maidshare"; };
        gui = { type = "app"; program = "${self.packages.${system}.default}/bin/maidshare-gui"; };
      });
      checks = forAllSystems (system: { package = self.packages.${system}.default; });

      # easy: imports = [ inputs.maidshare.homeManagerModules.default ]; programs.maidshare.enable = true;
      homeManagerModules.default = { config, lib, pkgs, ... }: {
        options.programs.maidshare = {
          enable = lib.mkEnableOption "Maidshare (Maidware)";
          package = lib.mkOption { type = lib.types.package; default = self.packages.${pkgs.system}.default; };
        };
        config = lib.mkIf config.programs.maidshare.enable { home.packages = [ config.programs.maidshare.package ]; };
      };
      nixosModules.default = { lib, ... }: { options.programs.maidshare.enableNote = lib.mkEnableOption "Maidshare (use home-manager module)"; };
    };
}
