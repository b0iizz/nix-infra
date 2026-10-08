# What the desktop roles of one host agree on, so none of them has to know
# the others. `nixos.desktop` is imported by each of them, and the options
# exist only on hosts that have one.
#
# Roles contribute data and programs that can use it pick it up. A
# contribution nobody consumes does nothing, and a consumer without
# contributions just has less to show: the hyprland role registers its
# workspaces whether or not the quickshell role is there, and quickshell works
# without hyprland.
#
#   desktop.workspaces        { name, monitor }  the workspace layout
#   desktop.bar.items.<Name>  a QML component for the bar: `position`, `order`
#                             and `qml` (source text or a path). <Name> is the
#                             QML type name, so it starts with a capital.
#   desktop.launcher.entries  { name, exec (argv), icon }  launcher entries
#   desktop.startup           commands the compositor starts with the session
#   desktop.launcherCommand   command that toggles the launcher, if there is one
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  flake.modules.nixos.desktop = {
    # imported by every desktop role, so the options must be declared once
    key = "modules/desktop.nix";

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

      startup = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      launcherCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  # The roles are independent: each combination of them evaluates, and takes
  # from the others only what they registered.
  #
  #   nix build .#checks.x86_64-linux.desktop-roles
  perSystem =
    { pkgs, ... }:
    let
      host =
        roles:
        (inputs.nixpkgs.lib.nixosSystem {
          modules = [
            {
              nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              boot.loader.grub.enable = false;
              system.stateVersion = "26.05";
            }
          ]
          ++ map (r: self.modules.nixos.${r}) roles;
        }).config;

      full = host [
        "hyprland"
        "quickshell"
        "alacritty"
        "librewolf"
      ];
      hyprOnly = host [
        "hyprland"
        "alacritty"
      ];
      shellOnly = host [ "quickshell" ];
      hypr = c: c.programs.hyprland.package.passthru.settings;
      quickshellPackage =
        c:
        lib.findFirst (
          p: (p.passthru.wrapperName or null) == "quickshell"
        ) null c.environment.systemPackages;
      quickshell = c: (quickshellPackage c).passthru.settings;

      tests = {
        testShellGetsTheRegistrations = {
          expr = {
            entries = lib.attrNames (quickshell full).launcherEntries;
            items = lib.attrNames (quickshell full).barItems;
            workspaces = lib.length (quickshell full).workspaces;
          };
          expected = {
            entries = [
              "alacritty"
              "librewolf"
            ];
            items = [ "Workspaces" ];
            workspaces = 9;
          };
        };
        testShellAlone = {
          expr = {
            items = (quickshell shellOnly).barItems;
            workspaces = (quickshell shellOnly).workspaces;
          };
          expected = {
            items = { };
            workspaces = [ ];
          };
        };
        testFullHost = {
          expr = {
            entries = lib.attrNames full.desktop.launcher.entries;
            items = lib.attrNames full.desktop.bar.items;
            launcher = (hypr full).launcher != null;
            startup = lib.length (hypr full).startup;
          };
          expected = {
            entries = [
              "alacritty"
              "librewolf"
            ];
            items = [ "Workspaces" ];
            launcher = true;
            startup = 1;
          };
        };
        testHyprlandAlone = {
          expr = {
            launcher = (hypr hyprOnly).launcher;
            startup = (hypr hyprOnly).startup;
          };
          expected = {
            launcher = null;
            startup = [ ];
          };
        };
      };
      failed = lib.runTests tests;
    in
    {
      checks.desktop-roles = pkgs.runCommand "check-desktop-roles" { } (
        if failed == [ ] then
          # the bar item of one role ends up in the tree of the other's wrapper
          "test -e ${(quickshellPackage full).passthru.config.dir}/Workspaces.qml && touch $out"
        else
          ''
            echo ${lib.escapeShellArg (lib.generators.toPretty { } failed)} >&2
            exit 1
          ''
      );
    };
}
