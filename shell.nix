{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    bash coreutils curl openssl python3
    kdePackages.kdeconnect-kde android-tools qrencode
    kdePackages.kdialog zenity shellcheck
  ];

  shellHook = ''
    echo "Maidshare dev shell"
  '';
}
