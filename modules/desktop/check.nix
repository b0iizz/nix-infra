# `checks.desktop-roles`: the desktop roles are independent, each combination
# of them evaluates and takes from the others only what they registered, and
# what they registered ends up in the tree of the shell and the greeter.
#
#   nix build .#checks.x86_64-linux.desktop-roles
#
# The contract it tests is in options.nix.
{
  lib,
  self,
  inputs,
  ...
}:
{
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
      twoCompositors = host [
        "hyprland"
        "niri"
        "quickshell"
        "greeter"
      ];
      threeCompositors = host [
        "hyprland"
        "niri"
        "sway"
        "quickshell"
        "swaybg"
      ];
      bothDaemons = host [
        "quickshell"
        "swaybg"
        "awww"
      ];
      withDrives = host [
        "quickshell"
        "removable-media"
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
              "network-menu"
              "power-lock"
              "power-logout"
              "power-menu"
              "power-poweroff"
              "power-reboot"
              "power-suspend"
              "wallpaper"
            ];
            items = [
              "Brightness"
              "Clock"
              "Network"
              "PowerButton"
              "Volume"
              "WallpaperButton"
              "Workspaces"
            ];
            overlays = [
              "Idle"
              "LockScreen"
              "NetworkMenu"
              "Notifications"
              "PolkitAgent"
              "PowerMenu"
              "WallpaperPicker"
            ];
            workspaces = 9;
          };
        };
        # wifi, bluetooth and battery follow the hardware; any item can be switched off
        testWidgetHardware =
          let
            report.hardware = {
              bluetooth = [ { } ];
              network_interface = [
                {
                  unix_device_names = [ "lo" ];
                }
                {
                  unix_device_names = [ "wlp170s0" ];
                }
              ];
              system.form_factor = "desktop";
            };
            facter = self.lib.facter;
          in
          {
            expr = {
              wifi = facter.hasWifi report;
              bluetooth = facter.hasBluetooth report;
              battery = facter.hasBattery report;
              noWifi = facter.hasWifi { hardware.network_interface = [ { unix_device_names = null; } ]; };
              laptop = facter.hasBattery { hardware.system.form_factor = "laptop"; };
              noReport = [
                (facter.hasWifi null)
                (facter.hasBluetooth null)
                (facter.hasBattery null)
              ];
            };
            expected = {
              wifi = true;
              bluetooth = true;
              battery = false;
              noWifi = false;
              laptop = true;
              noReport = [
                false
                false
                false
              ];
            };
          };
        testWidgetSwitch = {
          expr =
            let
              c = hostWith {
                desktop.bar.items.Clock.enable = false;
                desktop.bar.items.Battery.enable = true;
              } [ "quickshell" ];
              items = lib.attrNames (quickshell c).barItems;
              overlays = lib.attrNames (quickshell c).overlays;
              menus = hostWith { desktop.bar.items.Wifi.enable = true; } [ "quickshell" ];
            in
            {
              clock = lib.elem "Clock" items;
              battery = lib.elem "Battery" items;
              upower = c.services.upower.enable;
              wifi = lib.elem "Wifi" items;
              # a menu goes with its widget
              networkMenu = lib.elem "NetworkMenu" overlays;
              wifiMenu = lib.elem "WifiMenu" overlays;
              wifiMenuWhenOn = lib.elem "WifiMenu" (lib.attrNames (quickshell menus).overlays);
              # and so does its launcher entry
              wifiEntry = (quickshell c).launcherEntries ? wifi-menu;
              wifiEntryWhenOn = (quickshell menus).launcherEntries ? wifi-menu;
            };
          expected = {
            clock = false;
            battery = true;
            upower = true;
            wifi = false;
            networkMenu = true;
            wifiMenu = false;
            wifiMenuWhenOn = true;
            wifiEntry = false;
            wifiEntryWhenOn = true;
          };
        };
        # the idle daemon is on, the battery warnings follow the hardware; both can be switched
        testIdleAndBattery =
          let
            overlays = c: lib.attrNames (quickshell c).overlays;
            off = hostWith {
              desktop.idle.enable = false;
              desktop.batteryWarning.enable = true;
            } [ "quickshell" ];
          in
          {
            expr = {
              idle = lib.elem "Idle" (overlays shellOnly);
              warnings = lib.elem "BatteryWarning" (overlays shellOnly);
              idleOff = lib.elem "Idle" (overlays off);
              warningsOn = lib.elem "BatteryWarning" (overlays off);
              data = (quickshell shellOnly).data.idle;
              libnotify = lib.length (
                lib.filter (p: p.pname or "" == "libnotify") off.environment.systemPackages
              );
            };
            expected = {
              idle = true;
              warnings = false;
              idleOff = false;
              warningsOn = true;
              data = {
                dim = 240;
                lock = 300;
                suspend = 900;
                lockCommand = [
                  "quickshell"
                  "ipc"
                  "call"
                  "lock"
                  "lock"
                ];
                suspendCommand = [
                  "sh"
                  "-c"
                  "quickshell ipc call lock lock; sleep 1; systemctl suspend"
                ];
              };
              libnotify = 1;
            };
          };
        # the launcher runs terminal applications in the terminal's role, and hides them without one
        testTerminal = {
          expr = {
            alacritty = map (a: baseNameOf a) (quickshell full).data.terminal;
            none = (quickshell shellOnly).data.terminal;
          };
          expected = {
            alacritty = [
              "alacritty"
              "-e"
            ];
            none = null;
          };
        };
        # Hibernate is offered where there is a resume device, and locks first
        testHibernate =
          let
            withSwap = hostWith { boot.resumeDevice = "/dev/disk/by-label/swap"; } [ "quickshell" ];
          in
          {
            expr = {
              noSwap = shellOnly.desktop.power.actions ? hibernate;
              swap = withSwap.desktop.power.actions ? hibernate;
              exec = withSwap.desktop.power.actions.hibernate.exec;
              entry = (quickshell withSwap).launcherEntries ? power-hibernate;
              menu = map (a: a.name) (quickshell withSwap).data.powerActions;
            };
            expected = {
              noSwap = false;
              swap = true;
              exec = [
                "sh"
                "-c"
                "quickshell ipc call lock lock; sleep 1; systemctl hibernate"
              ];
              entry = true;
              menu = [
                "Lock"
                "Shut down"
                "Reboot"
                "Suspend"
                "Hibernate"
              ];
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
              "network-menu"
              "power-lock"
              "power-menu"
              "power-poweroff"
              "power-reboot"
              "power-suspend"
              "wallpaper"
            ];
            items = [
              "Brightness"
              "Clock"
              "Network"
              "PowerButton"
              "Volume"
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
            # the shell, the wallpaper daemon, the default wallpaper and the
            # lock before sleep
            startup = 4;
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
        # bitwarden brings gnome-keyring, unlocked by the greeter's password;
        # keepassxc is the keyring itself, started with the session, and wins
        testKeyring =
          let
            bitwarden = host [
              "niri"
              "greeter"
              "bitwarden"
            ];
            keepassxc = host [
              "niri"
              "keepassxc"
            ];
          in
          {
            expr = {
              unlocks = lib.hasInfix "pam_gnome_keyring" (pam bitwarden "quickshell-greeter-auth").text;
              startsDaemon = lib.hasInfix "auto_start" (pam bitwarden "login").text;
              keepassxcKeyring = keepassxc.services.gnome.gnome-keyring.enable;
              keepassxcStarts = lib.any (lib.hasInfix "keepassxc") keepassxc.desktop.startup;
              # with both roles KeePassXC is the keyring
              both =
                (host [
                  "niri"
                  "keepassxc"
                  "bitwarden"
                ]).services.gnome.gnome-keyring.enable;
            };
            expected = {
              unlocks = true;
              startsDaemon = true;
              keepassxcKeyring = false;
              both = false;
              keepassxcStarts = true;
            };
          };
        # the compositors don't collide: both are sessions, there is one log out
        testTwoCompositors = {
          expr = {
            sessions = map (s: s.name) (
              lib.sortOn (s: s.order) (lib.attrValues twoCompositors.desktop.sessions)
            );
            logout = lib.attrNames (lib.filterAttrs (n: _: n == "logout") twoCompositors.desktop.power.actions);
            niriLauncher = twoCompositors.programs.niri.package.passthru.settings.launcher != null;
          };
          expected = {
            sessions = [
              "Hyprland"
              "niri"
            ];
            logout = [ "logout" ];
            niriLauncher = true;
          };
        };
        # every compositor has its own workspace widget, and swaybg is used
        # unless awww is there too
        testThreeCompositors = {
          expr = {
            items = lib.attrNames (quickshell threeCompositors).barItems;
            sway = threeCompositors.programs.sway.enable;
            daemons = [
              full.desktop.wallpaper.daemon
              threeCompositors.desktop.wallpaper.daemon
              bothDaemons.desktop.wallpaper.daemon
            ];
          };
          expected = {
            items = [
              "Brightness"
              "Clock"
              "Network"
              "NiriWorkspaces"
              "PowerButton"
              "SwayWorkspaces"
              "Volume"
              "WallpaperButton"
              "Workspaces"
            ];
            sway = true;
            daemons = [
              "awww"
              "swaybg"
              "awww"
            ];
          };
        };
        # external drives: the item, its menu and the launcher entry reach the
        # shell, and udiskie is started with the session
        testRemovableMedia = {
          expr = {
            item = (quickshell withDrives).barItems ? Drives;
            overlay = (quickshell withDrives).overlays ? DrivesMenu;
            entry = (quickshell withDrives).launcherEntries ? drives-menu;
            udiskie = lib.any (lib.hasInfix "udiskie") withDrives.desktop.startup;
            udisks = withDrives.services.udisks2.enable;
          };
          expected = {
            item = true;
            overlay = true;
            entry = true;
            udiskie = true;
            udisks = true;
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
        # an output's scale reaches every compositor
        testOutputs =
          let
            c = hostWith { desktop.outputs.eDP-1.scale = 1.5; } [
              "hyprland"
              "niri"
              "sway"
            ];
            extra = p: p.passthru.settings.extraConfig;
          in
          {
            expr = {
              hyprland = lib.last (hypr c).monitors;
              niri = lib.hasInfix ''output "eDP-1" { scale 1.5; }'' (extra c.programs.niri.package);
              sway = lib.hasInfix "output eDP-1 scale 1.5" (extra c.programs.sway.package);
            };
            expected = {
              hyprland = {
                output = "eDP-1";
                scale = 1.5;
                mode = "preferred";
                position = "auto";
              };
              niri = true;
              sway = true;
            };
          };
        # the copy of the current wallpaper: the user may write it, the login screen read it
        testWallpaperCopy = {
          expr = lib.elem "f /var/lib/wallpaper/joni 0644 joni users -" full.systemd.tmpfiles.rules;
          expected = true;
        };
      };
      failed = lib.runTests tests;

      # what ShellData holds on the full host
      shellData = pkgs.writeText "shell-data.json" (
        builtins.toJSON (
          (quickshell full).data
          // {
            inherit ((quickshell full)) workspaces;
            launcherEntries = lib.attrValues (quickshell full).launcherEntries;
          }
        )
      );
    in
    {
      checks.desktop-roles = pkgs.runCommand "check-desktop-roles" { nativeBuildInputs = [ pkgs.jq ]; } (
        if failed == [ ] then
          # what the roles registered ends up in the tree of the wrapper
          ''
            tree=${(quickshellPackage full).passthru.config.dir}
            test -e $tree/Workspaces.qml
            test -e $tree/PowerButton.qml
            grep -q '"Log out"' $tree/ShellData.qml
            grep -q 'PowerMenu {}' $tree/shell.qml
            grep -q 'LockScreen {}' $tree/shell.qml
            grep -q 'PolkitAgent {}' $tree/shell.qml
            grep -q 'Notifications {}' $tree/shell.qml
            grep -q 'WallpaperPicker {}' $tree/shell.qml
            test -e $tree/WallpaperButton.qml
            grep -q 'bin/wallpaper-set"' $tree/ShellData.qml
            grep -q -- '--transition-type grow' ${full.desktop.data.wallpaper.set}

            # every ShellData.<name>.<key> the QML reads is set by some module
            grep -oh 'ShellData\.[A-Za-z]*\.[A-Za-z]*' $tree/*.qml | sort -u |
              while IFS=. read -r _ name key; do
                jq -e --arg n "$name" --arg k "$key" 'has($n) and (.[$n] | type != "object" or has($k))' \
                  ${shellData} >/dev/null || { echo "QML reads ShellData.$name.$key, nothing sets it" >&2; exit 1; }
              done

            # both setters keep the copy the lock and login screens show
            grep -q 'cp -- "$1" "/var/lib/wallpaper/' ${full.desktop.data.wallpaper.set}
            grep -q 'cp -- "$1" "/var/lib/wallpaper/' ${threeCompositors.desktop.data.wallpaper.set}

            # every sleep locks first, the lid's too
            grep -q "before-sleep 'quickshell ipc call lock lock; sleep 1'" ${
              lib.findFirst (lib.hasInfix "lock-before-sleep") "" full.desktop.startup
            }

            # the swaybg scripts build (shellcheck) and the sway session finds its config
            ${lib.concatMapStringsSep "\n" (c: "test -x ${c}") threeCompositors.desktop.startup}
            grep -q -- '--config /nix/store' ${lib.getExe' threeCompositors.programs.sway.package "sway"}

            # the drives widget and its menu are in the tree
            dtree=${(quickshellPackage withDrives).passthru.config.dir}
            grep -q 'DrivesMenu {}' $dtree/shell.qml
            grep -q 'Drives {}' $dtree/Bar.qml
            test -e $dtree/DriveList.qml
            grep -q 'DriveList' $dtree/qmldir

            # everything started with the session exists
            ${lib.concatMapStringsSep "\n" (c: "test -x ${c}") full.desktop.startup}

            # the picker offers the fetched collection, and the default is in it
            grep -qF '${full.desktop.wallpaper.directory}' $tree/ShellData.qml
            test -e '${full.desktop.wallpaper.default}'
            grep -q 'AuthView' $tree/qmldir
            grep -q 'WheelArea' $tree/qmldir
            grep -q 'AuthView {' $tree/LockScreen.qml
            grep -q 'AuthForm {' $tree/PolkitAgent.qml
            grep -q 'fingerprint' $tree/ShellData.qml

            # the greeter gets the users and the compositor's start command
            greeter=${lib.last (lib.splitString " " withGreeter.services.greetd.settings.default_session.command)}
            gtree=$(grep -o "path /nix/store/[^ ']*" $greeter | head -1 | cut -d' ' -f2)
            grep -q '"joni"' $gtree/GreeterData.qml
            grep -q 'bin/start-hyprland' $gtree/GreeterData.qml
            grep -q '"saved":"/var/lib/wallpaper"' $gtree/GreeterData.qml

            # with two compositors the greeter offers both, hyprland first
            g2=${lib.last (lib.splitString " " twoCompositors.services.greetd.settings.default_session.command)}
            g2tree=$(grep -o "path /nix/store/[^ ']*" $g2 | head -1 | cut -d' ' -f2)
            grep -q 'start-hyprland.*niri-session' $g2tree/GreeterData.qml
            # the session of the niri wrapper finds its config
            grep -q 'NIRI_CONFIG' ${lib.getExe' twoCompositors.programs.niri.package "niri-session"}

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
