# Wallpaper daemon (awww, the successor of swww, for its transitions) and the
# widget to change it. Imported by the quickshell role.
#
#   desktop.wallpaper.directory   where the picker looks for images, by default
#                                 a collection fetched from GitHub (below)
#   desktop.wallpaper.default     shown when there is nothing to restore
#   desktop.wallpaper.transition  what awww animates between two wallpapers
#
# The daemon is started with the session (`desktop.startup`); it keeps the
# last image in its own cache and shows it again when it starts, so the choice
# is not stored here. Only when it has nothing to show (first start, or the
# remembered file is gone) the default is set. The widget is the
# `WallpaperPicker` overlay: a grid of
# thumbnails, a click sets the wallpaper. Open it with
# `quickshell ipc call wallpaper toggle`, from the "Wallpaper" launcher
# entry or the bar button.
{
  self,
  lib,
  ...
}:
{
  flake.modules.nixos.desktop-wallpaper =
    { config, pkgs, ... }:
    let
      cfg = config.desktop.wallpaper;
      awww = lib.getExe pkgs.awww;

      # Not a flake input: those are fetched again by every `nix flake update`.
      # To take newer images, change the rev and the hash.
      wallpapers = pkgs.fetchFromGitHub {
        owner = "b0iizz";
        repo = "wallpapers";
        rev = "4f8ae72e22c8fd160660f9cde6097acc8477731d";
        hash = "sha256-D4btmZ3E3eNdQZ9vqn3jHDGknkVjH4cC9aL5zezHTdc=";
      };

      # awww shows a plain color until it is given an image. Without anything
      # to restore, set the default; the daemon needs a moment to start.
      setDefault = pkgs.writeShellApplication {
        name = "wallpaper-default";
        runtimeInputs = [
          pkgs.awww
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          for _ in $(seq 50); do
            awww query >/dev/null 2>&1 && break
            sleep 0.2
          done
          if awww query | grep -q 'displaying: color'; then
            awww img ${lib.escapeShellArg cfg.default} --transition-type none
          fi
        '';
      };
    in
    {
      key = "modules/desktop/wallpaper.nix";

      imports = [ self.modules.nixos.desktop ];

      options.desktop.wallpaper = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = "${wallpapers}";
          defaultText = "github:b0iizz/wallpapers, pinned in the module";
          description = "Directory with the images; a leading `~` is the home directory.";
        };

        default = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "${wallpapers}/22.png";
          defaultText = "22.png of the pinned collection";
          description = "Image to show when there is nothing to restore; null for none.";
        };

        transition = {
          type = lib.mkOption {
            type = lib.types.enum [
              "none"
              "simple"
              "fade"
              "left"
              "right"
              "top"
              "bottom"
              "wipe"
              "wave"
              "grow"
              "center"
              "any"
              "outer"
              "random"
            ];
            default = "grow";
          };
          duration = lib.mkOption {
            type = lib.types.numbers.positive;
            default = 1.5;
            description = "Seconds; not used by `simple`.";
          };
          fps = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60;
            description = "At least what the monitors do.";
          };
        };
      };

      config = {
        desktop.startup = [
          (lib.getExe' pkgs.awww "awww-daemon")
        ]
        ++ lib.optional (cfg.default != null) (lib.getExe setDefault);

        desktop.overlays.WallpaperPicker.qml = ./WallpaperPicker.qml;
        desktop.data.wallpaper = {
          inherit (cfg) directory;
          inherit awww;
          transition = [
            "--transition-type"
            cfg.transition.type
            "--transition-duration"
            (toString cfg.transition.duration)
            "--transition-fps"
            (toString cfg.transition.fps)
          ];
        };

        desktop.bar.items.WallpaperButton = {
          position = "right";
          order = 900;
          qml = ./WallpaperButton.qml;
        };

        desktop.launcher.entries.wallpaper = {
          name = "Wallpaper";
          exec = [
            "quickshell"
            "ipc"
            "call"
            "wallpaper"
            "toggle"
          ];
        };
      };
    };
}
