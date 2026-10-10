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
# The rest of this folder is what the quickshell role imports, one folder per
# feature with its QML next to the module that registers it (bar/, power/,
# auth/, wallpaper/), plus session.nix, theme.nix and notifications.nix.
# drives/ is the QML of the removable-media role. The tests of this contract
# are in check.nix. `self.lib.quickshellIpc target function` is the argv of a
# shell menu's `quickshell ipc call`.
#
#   desktop.workspaces       { name, monitor }  the workspace layout
#   desktop.outputs.<name>    { scale }  per connector (`eDP-1`), for every
#                             compositor; the others guess the scale themselves
#   desktop.bar.items.<Name>  a QML component for the bar: `position`, `order`
#                             and `qml` (source text or a path). <Name> is the
#                             QML type name, so it starts with a capital.
#                             `enable = false` drops it from the shell.
#   desktop.overlays.<Name>   a QML component that lives at the root of the
#                             shell (menus, notifications, ...): `qml`
#   desktop.components.<Name> a QML file other components use (AuthForm, ...),
#                             part of the tree but not instantiated
#   desktop.fingerprint       fingerprint login for lock screen, greeter and polkit
#   desktop.launcher.entries  { name, exec (argv), confirm }  launcher entries for
#                             what has no .desktop file; applications don't
#                             register, the launcher finds their entries
#   desktop.power.actions     { name, exec (argv), order, confirm }  shut down, log out, ...
#   desktop.data              values for the shell's QML (ShellData.<name>)
#   desktop.lock.command      argv that locks the screen, if there is a lock screen
#   desktop.sessions          { name, exec (argv), order }  sessions a greeter offers
#   desktop.startup         commands the compositor starts with the session
#   desktop.launcherCommand   command that toggles the launcher, if there is one
#   desktop.terminal          argv that runs a command in a terminal (alacritty role)
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;

  confirmOption = mkOption {
    type = types.bool;
    default = false;
    description = "Ask for a second Enter or click before running (for what loses unsaved work).";
  };

  qml = mkOption { type = types.either types.lines types.path; };
  qmlSet = types.attrsOf (types.submodule { options = { inherit qml; }; });

  # a name and an argv, and what else the kind of entry has
  entries =
    extra:
    mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            name = mkOption { type = types.str; };
            exec = mkOption { type = types.listOf types.str; };
          }
          // extra;
        }
      );
      default = { };
    };
  order = mkOption {
    type = types.int;
    default = 100;
  };
in
{
  # `quickshell ipc call <target> <function>`, the argv of every shell menu
  flake.lib.quickshellIpc = target: function: [
    "quickshell"
    "ipc"
    "call"
    target
    function
  ];

  flake.modules.nixos.desktop = {
    # imported by every desktop role, so the options must be declared once
    key = "modules/desktop/options.nix";

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

      outputs = mkOption {
        type = types.attrsOf (
          types.submodule {
            options.scale = mkOption { type = types.numbers.positive; };
          }
        );
        default = { };
        example.eDP-1.scale = 1.5;
      };

      bar.items = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = "Off leaves the item out of the shell: `desktop.bar.items.Clock.enable = false;`.";
              };
              position = mkOption {
                type = types.enum [
                  "left"
                  "center"
                  "right"
                ];
              };
              inherit order qml;
            };
          }
        );
        default = { };
      };

      overlays = mkOption {
        type = qmlSet;
        default = { };
      };

      components = mkOption {
        type = qmlSet;
        default = { };
      };

      fingerprint = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Fingerprint login for the lock screen, the greeter and polkit
          prompts. Turn it off on hosts without a reader.
        '';
      };

      power.actions = entries {
        inherit order;
        confirm = confirmOption;
      };

      launcher.entries = entries { confirm = confirmOption; };

      data = mkOption {
        type = types.attrsOf types.raw;
        default = { };
        description = ''
          JSON-able values for the shell's QML, read there as `ShellData.<name>`.
          The way a module hands a setting to a QML file it contributes.
        '';
      };

      lock.command = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Command that locks the screen, set by the lock screen.";
      };

      startup = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      # graphical sessions to log in to, one per compositor role; the first by
      # order is the greeter's default
      sessions = entries { inherit order; };

      launcherCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      terminal = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          argv that runs the rest of the command line in a terminal, e.g.
          `[ "alacritty" "-e" ]`; set by the terminal's role. Without it the
          launcher leaves out the applications that want a terminal.
        '';
      };
    };
  };
}
