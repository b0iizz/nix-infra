# Wallpaper daemon (awww, the successor of swww, for its transitions, or the
# lighter swaybg) and the widget to change it. Imported by the quickshell role
# and by the `awww` and `swaybg` roles, which choose the daemon.
#
#   desktop.wallpaper.daemon      "awww" or "swaybg"
#   desktop.wallpaper.directory   where the picker looks for images, by default
#                                 a collection fetched from GitHub (below)
#   desktop.wallpaper.default     shown when there is nothing to restore
#   desktop.wallpaper.transition  what awww animates between two wallpapers
#
# The daemon is started with the session (`desktop.startup`). awww keeps the
# last image in its own cache and shows it again when it starts; only when it
# has nothing to show (first start, or the remembered file is gone) the
# default is set. The widget is the `WallpaperPicker` overlay: a grid of
# thumbnails, a click sets the wallpaper. Open it with
# `quickshell ipc call wallpaper toggle`, from the "Wallpaper" launcher
# entry or the bar button.
#
# Setting one also copies it to /var/lib/wallpaper/<user>, readable by all:
# the lock screen shows it, and so does the login screen, which runs as
# another user and cannot look into the homes; swaybg starts from it. Both
# screens show the default for a user who has not chosen one yet.
{
  self,
  lib,
  ...
}:
{
  # Choose the daemon by role. Both are plain layer-shell clients, so they work
  # in every compositor role. With both roles awww (priority 800) beats swaybg
  # (900); with neither the option's default is awww.
  flake.modules.nixos.awww = {
    imports = [ self.modules.nixos.desktop-wallpaper ];
    desktop.wallpaper.daemon = lib.mkOverride 800 "awww";
  };
  flake.modules.nixos.swaybg = {
    imports = [ self.modules.nixos.desktop-wallpaper ];
    desktop.wallpaper.daemon = lib.mkOverride 900 "swaybg";
  };

  flake.modules.nixos.desktop-wallpaper =
    { config, pkgs, ... }:
    let
      cfg = config.desktop.wallpaper;
      awww = lib.getExe pkgs.awww;

      # each user's current wallpaper, `<saved>/<user>` (see the top)
      saved = "/var/lib/wallpaper";
      current = "${saved}/$(id -un)";

      # The picker runs `wallpaper-set <image>`, whatever the daemon is. The
      # copy comes last: if it fails, the wallpaper is changed all the same.
      setAwww = pkgs.writeShellApplication {
        name = "wallpaper-set";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          ${awww} img "$1" \
            --transition-type ${cfg.transition.type} \
            --transition-duration ${toString cfg.transition.duration} \
            --transition-fps ${toString cfg.transition.fps}
          cp -- "$1" "${current}"
        '';
      };

      # swaybg has no memory and shows one image per process: start the new
      # process, then end the old ones.
      setSwaybg = pkgs.writeShellApplication {
        name = "wallpaper-set";
        runtimeInputs = [
          pkgs.swaybg
          pkgs.coreutils
          pkgs.procps
          pkgs.util-linux
        ];
        text = ''
          mapfile -t old < <(pgrep -x swaybg || true)
          setsid swaybg -i "$1" -m fill >/dev/null 2>&1 &
          sleep 0.5
          [ ''${#old[@]} -eq 0 ] || kill "''${old[@]}"
          cp -- "$1" "${current}"
        '';
      };
      # Not through wallpaper-set: the copy would be copied onto itself.
      restoreSwaybg = pkgs.writeShellApplication {
        name = "wallpaper-restore";
        runtimeInputs = [
          pkgs.swaybg
          pkgs.coreutils
        ];
        text = ''
          file="${current}"
          [ -s "$file" ] || file=${lib.escapeShellArg (toString cfg.default)}
          if [ -f "$file" ]; then exec swaybg -i "$file" -m fill; fi
        '';
      };

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

      imports = with self.modules.nixos; [
        desktop
        persist
      ];

      options.desktop.wallpaper = {
        daemon = lib.mkOption {
          type = lib.types.enum [
            "awww"
            "swaybg"
          ];
          default = "awww";
          description = ''
            awww has transitions, swaybg is the lighter one. Normally chosen by
            the `awww` and `swaybg` roles; a host with both gets awww.
          '';
        };

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
        # awww's memory of the last image
        persist.home.directories = lib.optional (cfg.daemon == "awww") ".cache/awww";
        persist.directories = [ saved ];

        # one file per user, which only that user may write
        systemd.tmpfiles.rules = [
          "d ${saved} 0755 root root -"
        ]
        ++ lib.mapAttrsToList (name: u: "f ${saved}/${name} 0644 ${name} ${u.group} -") (
          lib.filterAttrs (_: u: u.isNormalUser) config.users.users
        );

        desktop.startup =
          if cfg.daemon == "awww" then
            [ (lib.getExe' pkgs.awww "awww-daemon") ]
            ++ lib.optional (cfg.default != null) (lib.getExe setDefault)
          else
            [ (lib.getExe restoreSwaybg) ];

        desktop.overlays.WallpaperPicker.qml = ./WallpaperPicker.qml;
        desktop.data.wallpaper = {
          inherit (cfg) directory default;
          inherit saved;
          set = lib.getExe (if cfg.daemon == "awww" then setAwww else setSwaybg);
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
