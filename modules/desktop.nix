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
#   desktop.overlays.<Name>   a QML component that lives at the root of the
#                             shell (menus, notifications, ...): `qml`
#   desktop.components.<Name> a QML file other components use (AuthForm, ...),
#                             part of the tree but not instantiated
#   desktop.fingerprint       fingerprint login for lock screen, greeter and polkit
#   desktop.launcher.entries  { name, exec (argv), icon }  launcher entries for
#                             what has no .desktop file; applications don't
#                             register, the launcher finds their entries
#   desktop.power.actions     { name, exec (argv), order }  shut down, log out, ...
#   desktop.session           argv that starts the graphical session (for a greeter)
#   desktop.startup         commands the compositor starts with the session
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

      overlays = mkOption {
        type = types.attrsOf (
          types.submodule {
            options.qml = mkOption { type = types.either types.lines types.path; };
          }
        );
        default = { };
      };

      components = mkOption {
        type = types.attrsOf (
          types.submodule {
            options.qml = mkOption { type = types.either types.lines types.path; };
          }
        );
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

      power.actions = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              exec = mkOption { type = types.listOf types.str; };
              order = mkOption {
                type = types.int;
                default = 100;
              };
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

      session = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Command that starts the graphical session, set by the compositor role.";
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
      hostWith =
        extra: roles:
        (inputs.nixpkgs.lib.nixosSystem {
          modules = [
            extra
            {
              nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              boot.loader.grub.enable = false;
              system.stateVersion = "26.05";
              users.users.joni.isNormalUser = true;
            }
          ]
          ++ map (r: self.modules.nixos.${r}) roles;
        }).config;
      host = hostWith { };

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
      withGreeter = host [
        "hyprland"
        "greeter"
      ];
      noReader = hostWith { desktop.fingerprint = false; } [
        "hyprland"
        "quickshell"
        "greeter"
      ];
      pam = c: name: c.security.pam.services.${name};
      # the reader is asked after the password (greetd and polkit)
      passwordFirst =
        c: name:
        let
          text = (pam c name).text;
          at = pattern: lib.stringLength (lib.head (lib.splitString pattern text));
        in
        lib.hasInfix "pam_fprintd" text && at "pam_unix" < at "pam_fprintd";
      hypr = c: c.programs.hyprland.package.passthru.settings;
      quickshellPackage =
        c:
        lib.findFirst (
          p: (p.passthru.wrapperName or null) == "quickshell"
        ) null c.environment.systemPackages;
      quickshell = c: (quickshellPackage c).passthru.settings;

      tests = {
        # the log out action comes from the hyprland role, the rest from the
        # defaults of the quickshell role
        testShellGetsTheRegistrations = {
          expr = {
            entries = lib.attrNames (quickshell full).launcherEntries;
            items = lib.attrNames (quickshell full).barItems;
            overlays = lib.attrNames (quickshell full).overlays;
            workspaces = lib.length (quickshell full).workspaces;
          };
          expected = {
            entries = [
              "power-lock"
              "power-logout"
              "power-poweroff"
              "power-reboot"
              "power-suspend"
              "wallpaper"
            ];
            items = [
              "PowerButton"
              "WallpaperButton"
              "Workspaces"
            ];
            overlays = [
              "LockScreen"
              "PolkitAgent"
              "PowerMenu"
              "WallpaperPicker"
            ];
            workspaces = 9;
          };
        };
        testShellAlone = {
          expr = {
            entries = lib.attrNames (quickshell shellOnly).launcherEntries;
            items = lib.attrNames (quickshell shellOnly).barItems;
            workspaces = (quickshell shellOnly).workspaces;
          };
          expected = {
            entries = [
              "power-lock"
              "power-poweroff"
              "power-reboot"
              "power-suspend"
              "wallpaper"
            ];
            items = [
              "PowerButton"
              "WallpaperButton"
            ];
            workspaces = [ ];
          };
        };
        testFullHost = {
          expr = {
            launcher = (hypr full).launcher != null;
            startup = lib.length (hypr full).startup;
          };
          expected = {
            launcher = true;
            # the shell, the wallpaper daemon and the default wallpaper
            startup = 3;
          };
        };
        testFingerprint = {
          expr = {
            daemon = full.services.fprintd.enable;
            polkit = passwordFirst full "polkit-1";
            greetd = passwordFirst withGreeter "quickshell-greeter-auth";
            greetdUsesIt =
              withGreeter.security.pam.services.greetd.rules.auth.login.modulePath == "quickshell-greeter-auth";
            # the lock screen's password service must not wait for the reader
            lockPasswordOnly = !(pam full "quickshell-lock").fprintAuth;
            lockReader = lib.hasInfix "pam_fprintd" (pam full "quickshell-lock-fingerprint").text;
          };
          expected = {
            daemon = true;
            polkit = true;
            greetd = true;
            greetdUsesIt = true;
            lockPasswordOnly = true;
            lockReader = true;
          };
        };
        testNoReader = {
          expr = {
            daemon = noReader.services.fprintd.enable;
            lockReaderService = noReader.security.pam.services ? quickshell-lock-fingerprint;
          };
          expected = {
            daemon = false;
            lockReaderService = false;
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
          # what the roles registered ends up in the tree of the wrapper
          ''
            tree=${(quickshellPackage full).passthru.config.dir}
            test -e $tree/Workspaces.qml
            test -e $tree/PowerButton.qml
            grep -q '"Log out"' $tree/PowerMenu.qml
            ! grep -q ACTIONS_JSON $tree/PowerMenu.qml
            grep -q 'PowerMenu {}' $tree/shell.qml
            grep -q 'LockScreen {}' $tree/shell.qml
            grep -q 'PolkitAgent {}' $tree/shell.qml
            grep -q 'WallpaperPicker {}' $tree/shell.qml
            test -e $tree/WallpaperButton.qml
            grep -q 'bin/awww"' $tree/WallpaperPicker.qml
            grep -q '"--transition-type","grow"' $tree/WallpaperPicker.qml
            ! grep -q 'WALLPAPER_DIRECTORY\|AWWW_BIN\|TRANSITION_ARGS' $tree/WallpaperPicker.qml

            # everything started with the session exists
            ${lib.concatMapStringsSep "\n" (c: "test -x ${c}") full.desktop.startup}

            # the picker offers the fetched collection, and the default is in it
            grep -qF '${full.desktop.wallpaper.directory}' $tree/WallpaperPicker.qml
            test -e '${full.desktop.wallpaper.default}'
            grep -q 'AuthView' $tree/qmldir
            grep -q 'AuthView {' $tree/LockScreen.qml
            grep -q 'AuthForm {' $tree/PolkitAgent.qml
            ! grep -q FINGERPRINT $tree/LockScreen.qml $tree/PolkitAgent.qml

            # the greeter gets the users and the compositor's start command
            greeter=${lib.last (lib.splitString " " withGreeter.services.greetd.settings.default_session.command)}
            gtree=$(grep -o "path /nix/store/[^ ']*" $greeter | head -1 | cut -d' ' -f2)
            grep -q '"joni"' $gtree/GreeterData.qml
            grep -q 'bin/start-hyprland' $gtree/GreeterData.qml

            # the lock screen and the login screen are the same files
            cmp $tree/AuthView.qml $gtree/AuthView.qml
            cmp $tree/AuthForm.qml $gtree/AuthForm.qml
            grep -q 'AuthView {' $gtree/Greeter.qml
            touch $out
          ''
        else
          ''
            echo ${lib.escapeShellArg (lib.generators.toPretty { } failed)} >&2
            exit 1
          ''
      );
    };
}
