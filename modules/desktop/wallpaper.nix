# Wallpaper daemon (awww, the successor of swww, for its transitions) and the
# widget to change it. Imported by the quickshell role.
#
#   desktop.wallpaper.directory   where the picker looks for images
#   desktop.wallpaper.transition  what awww animates between two wallpapers
#
# The daemon is started with the session (`desktop.startup`); it keeps the
# last image in its own cache and shows it again when it starts, so nothing
# is stored here. The widget is the `WallpaperPicker` overlay: a grid of
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
    in
    {
      key = "modules/desktop/wallpaper.nix";

      imports = [ self.modules.nixos.desktop ];

      options.desktop.wallpaper = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = "~/Pictures/Wallpapers";
          description = "Directory with the images; a leading `~` is the home directory.";
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
        desktop.startup = [ (lib.getExe' pkgs.awww "awww-daemon") ];

        desktop.overlays.WallpaperPicker.qml =
          builtins.replaceStrings
            [ "WALLPAPER_DIRECTORY" "AWWW_BIN" "TRANSITION_ARGS" ]
            [
              (builtins.toJSON cfg.directory)
              (builtins.toJSON awww)
              (builtins.toJSON [
                "--transition-type"
                cfg.transition.type
                "--transition-duration"
                (toString cfg.transition.duration)
                "--transition-fps"
                (toString cfg.transition.fps)
              ])
            ]
            (builtins.readFile ./WallpaperPicker.qml);

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
