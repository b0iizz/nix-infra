# What the desktop modules agree on, so none of them has to know the others.
#
# `perSystem.desktop` is a registry: data that modules contribute and the
# programs that can use it pick up. A registration nobody consumes does
# nothing, and a consumer without registrations just has less to show. So the
# hyprland wrapper registers its workspaces and a bar item whether or not the
# quickshell wrapper exists, and the quickshell wrapper works without hyprland.
#
#   desktop.workspaces        { name, monitor }  the workspace layout
#   desktop.bar.items.<Name>  a QML component for the bar: `position`, `order`
#                             and `qml` (source text or a path). <Name> is the
#                             QML type name, so it starts with a capital.
#   desktop.launcher.entries  { name, exec (argv), icon }  launcher entries
#
# `nixos.desktop` is the same for things that differ per host, since the
# wrappers above are flake-wide. The roles `hyprland` and `quickshell` import
# it and are otherwise independent:
#
#   desktop.startup    commands the compositor starts with the session
#   desktop.launcher   command that toggles the launcher, if the host has one
{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.desktop = {
      workspaces = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              monitor = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };

      bar.items = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              position = mkOption {
                type = types.enum [
                  "left"
                  "center"
                  "right"
                ];
              };
              order = mkOption {
                type = types.int;
                default = 100;
              };
              qml = mkOption { type = types.either types.lines types.path; };
            };
          }
        );
        default = { };
      };

      launcher.entries = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              exec = mkOption { type = types.listOf types.str; };
              icon = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
            };
          }
        );
        default = { };
      };
    };
  };

  config.flake.modules.nixos.desktop =
    { lib, ... }:
    {
      options.desktop = {
        startup = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        launcher = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    };
}
