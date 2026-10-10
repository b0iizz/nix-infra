# KeePassXC 2.8 beta, for its remote databases and sync (a database file that
# a command of your choice downloads and uploads, set per database under
# Database Settings > Remote). nixpkgs has 2.7.12, so the role builds the beta
# from nixpkgs' recipe with Qt 6, which 2.8 needs.
#
#   roles = [ "workstation" "keepassxc" ];
#
# The host's LibreWolf and Firefox get the KeePassXC-Browser extension and its
# native messaging host (see `browser-extensions` in
# modules/wrappers/firefox/default.nix); enable "Browser Integration" in the
# program's settings. The commands you enter run with the system PATH. The databases are ordinary
# files wherever you put them; only the program's own settings are kept across
# reboots. Drop the package override once nixpkgs ships 2.8.
{ self, ... }:
{
  flake.modules.nixos.keepassxc =
    { lib, pkgs, ... }:
    let
      keepassxc = pkgs.keepassxc.overrideAttrs (old: rec {
        version = "2.8.0-beta1";
        src = pkgs.fetchFromGitHub {
          owner = "keepassxreboot";
          repo = "keepassxc";
          tag = version;
          hash = "sha256-fksThYmGZed66zxGDxlS2SHQzJYRf+T9AuZPbaNZV5Y=";
        };
        # the Darwin-only patch of the 2.7 recipe; its PCSC type fix stays (postPatch)
        patches = [ ];
        # 2.8 has other flag names (KPXC_FEATURE_*), all on by default
        cmakeFlags = [
          (lib.cmakeFeature "KEEPASSXC_BUILD_TYPE" "Release")
          (lib.cmakeBool "KPXC_FEATURE_UPDATES" false)
          (lib.cmakeBool "WITH_TESTS" false)
        ];
        doCheck = false;
        nativeBuildInputs = with pkgs; [
          asciidoctor
          cmake
          pkg-config
          qt6.wrapQtAppsHook
          qt6.qttools
          wrapGAppsHook3
        ];
        buildInputs =
          lib.filter (p: !(lib.hasPrefix "qt" (p.pname or ""))) old.buildInputs
          ++ (with pkgs; [
            keyutils
            qt6.qtbase
            qt6.qtsvg
            qt6.qtwayland
          ]);
      });
    in
    {
      imports = with self.modules.nixos; [
        persist
        browser-extensions
      ];

      environment.systemPackages = [ keepassxc ];

      # KeePassXC-Browser, and the manifest the package ships for it
      browser.extensions."keepassxc-browser@keepassxc.org" = "keepassxc-browser";
      browser.nativeMessagingHosts = [ keepassxc ];

      persist.home.directories = [
        ".config/keepassxc"
        ".cache/keepassxc"
      ];
    };
}
