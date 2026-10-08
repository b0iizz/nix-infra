# Quickshell, wrapped: a QML tree assembled from `passthru.settings` and
# `passthru.theme`, started with `--path`.
#
#   settings.workspaces       [ { name, monitor } ]
#   settings.barItems         <Name> -> { position, order, qml }. Only the bar
#                             and qmldir are made from it: whoever sets it also
#                             adds `passthru.files."<Name>.qml"`, as file names
#                             cannot come from the finished wrapper.
#   settings.overlays         <Name> -> { qml }, instantiated in shell.qml. Same
#                             rule as for the bar items.
#   settings.components       <Name> -> { qml }, in the tree and the qmldir but
#                             not instantiated. Same rule as for the bar items.
#   settings.launcherEntries  <name> -> { name, exec, icon }: what the launcher
#                             offers besides the desktop entries it finds
#                             itself (Quickshell's DesktopEntries)
#   settings.data             <name> -> JSON-able value, read as `ShellData.<name>`
#
# On a host the quickshell role fills these from `desktop.*`
# (modules/desktop.nix); the bare wrapper has an empty bar.
#
#   Theme.qml       singleton: colors (base00..), fonts, sizes, opacities of
#                   `passthru.theme`, e.g. `Theme.base0D`, `Theme.fontMonospace`,
#                   `Theme.opacityDesktop`
#   ShellData.qml   singleton: `workspaces` and `launcherEntries`
#   Bar.qml         one panel per screen; the bar items by position and order
#   Launcher.qml    toggled with `quickshell ipc call launcher toggle`
#   <Item>.qml      one per bar item; may use Theme and ShellData
#
# The tree is flat on purpose: QML finds the types next to it through the
# generated qmldir. Nothing in it knows about Hyprland or any other module.
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  cap = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;

  # QML source for the trees of the shell and the greeter (`self.lib.quickshell`)
  qml = {
    singleton = body: ''
      pragma Singleton
      import QtQuick
      import Quickshell

      Singleton {
      ${body}
      }
    '';

    property =
      type: name: value:
      "    readonly property ${type} ${name}: ${value}";

    # Theme.qml from `passthru.theme`
    theme =
      t:
      qml.singleton (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (n: v: qml.property "color" n (builtins.toJSON "#${v}")) t.colors
          ++ lib.mapAttrsToList (n: v: qml.property "string" "font${cap n}" (builtins.toJSON v)) t.fonts
          ++ lib.mapAttrsToList (n: v: qml.property "int" "size${cap n}" (toString v)) t.sizes
          ++ lib.mapAttrsToList (n: v: qml.property "real" "opacity${cap n}" (builtins.toJSON v)) t.opacity
          ++ [ (qml.property "bool" "dark" (lib.boolToString (t.polarity == "dark"))) ]
        )
      );

    # qmldir listing `types`; those in `singletons` as singletons
    qmldir =
      singletons: types:
      lib.concatMapStringsSep "\n" (
        t: "${lib.optionalString (builtins.elem t singletons) "singleton "}${t} 1.0 ${t}.qml"
      ) types
      + "\n";
  };

  program = pkgs: [
    (w.withPackage pkgs.quickshell)
    {
      passthru.settings = {
        workspaces = _: [ ];
        barItems = _: { };
        overlays = _: { };
        components = _: { };
        launcherEntries = _: { };
        data = _: { };
      };
    }
    (
      final:
      let
        s = final.passthru.settings;
        t = final.passthru.theme;

        items = lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name)) (
          lib.mapAttrsToList (name: i: i // { inherit name; }) s.barItems
        );
        overlays = lib.attrNames s.overlays;
        components = lib.attrNames s.components;
        badNames = lib.filter (n: builtins.match "[A-Z][A-Za-z0-9]*" n == null) (
          map (i: i.name) items ++ overlays ++ components
        );
        inPosition =
          p: lib.concatMapStringsSep "\n" (i: "${i.name} {}") (lib.filter (i: i.position == p) items);

        shellData = qml.singleton (
          lib.concatStringsSep "\n" (
            [
              (qml.property "var" "workspaces" (builtins.toJSON s.workspaces))
              (qml.property "var" "launcherEntries" (builtins.toJSON (lib.attrValues s.launcherEntries)))
            ]
            ++ lib.mapAttrsToList (n: v: qml.property "var" n (builtins.toJSON v)) s.data
          )
        );

        bar = ''
          import QtQuick
          import QtQuick.Layouts
          import Quickshell

          Scope {
              Variants {
                  model: Quickshell.screens

                  PanelWindow {
                      required property var modelData

                      screen: modelData
                      anchors {
                          top: true
                          left: true
                          right: true
                      }
                      implicitHeight: 32
                      color: Qt.alpha(Theme.base00, Theme.opacityDesktop)

                      RowLayout {
                          anchors {
                              left: parent.left
                              leftMargin: 8
                              verticalCenter: parent.verticalCenter
                          }
                          spacing: 8
          ${inPosition "left"}
                      }

                      RowLayout {
                          anchors.centerIn: parent
                          spacing: 8
          ${inPosition "center"}
                      }

                      RowLayout {
                          anchors {
                              right: parent.right
                              rightMargin: 8
                              verticalCenter: parent.verticalCenter
                          }
                          spacing: 8
          ${inPosition "right"}
                      }
                  }
              }
          }
        '';
      in
      {
        passthru.files = {
          "shell.qml" = _: ''
            import Quickshell

            ShellRoot {
                Bar {}
                Launcher {}
            ${lib.concatMapStringsSep "\n" (n: "    ${n} {}") overlays}
            }
          '';
          "qmldir" =
            _:
            qml.qmldir
              [
                "Theme"
                "ShellData"
              ]
              (
                [
                  "Theme"
                  "ShellData"
                  "Bar"
                  "Launcher"
                ]
                ++ map (i: i.name) items
                ++ overlays
                ++ components
              );
          "Theme.qml" = _: qml.theme t;
          "ShellData.qml" = _: shellData;
          # the check is in a value: the names of the files may not depend on `final`
          "Bar.qml" =
            _:
            assert lib.assertMsg (badNames == [ ])
              "quickshell: bar items, overlays and components are QML types and need a capitalised name: ${toString badNames}";
            bar;
          "Launcher.qml" = _: ./Launcher.qml;
        };

        passthru.wrapper.flags.__append = [ "--path ${final.passthru.config.dir}" ];
      }
    )
  ];
in
{
  flake.lib.quickshell = qml;

  perSystem =
    { pkgs, ... }:
    {
      wrappers.quickshell = w.program (program pkgs);
    };

  # Opt-in per host (`roles = [ "quickshell" ]`). Takes what the host's roles
  # registered in `desktop.*` (modules/desktop.nix); Hyprland (or whatever
  # compositor) picks the start command and the launcher key up from there.
  #
  # Comes with what every desktop needs: the shutdown menu (desktop/power.nix),
  # the lock screen (desktop/lock.nix), the polkit agent (desktop/polkit.nix),
  # the wallpaper daemon and picker (desktop/wallpaper.nix) and the session
  # basics (desktop/session.nix).
  flake.modules.nixos.quickshell =
    { config, pkgs, ... }:
    let
      quickshell = self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell.extend [
        {
          passthru.settings = {
            workspaces = _: config.desktop.workspaces;
            barItems = _: config.desktop.bar.items;
            overlays = _: config.desktop.overlays;
            components = _: config.desktop.components;
            launcherEntries = _: config.desktop.launcher.entries;
            data = _: config.desktop.data;
          };
        }
        # file names cannot come from the settings, see modules/wrappers/files.nix
        {
          passthru.files = lib.mapAttrs' (name: c: lib.nameValuePair "${name}.qml" (_: c.qml)) (
            config.desktop.bar.items // config.desktop.overlays // config.desktop.components
          );
        }
      ];
    in
    {
      imports = with self.modules.nixos; [
        desktop
        desktop-power
        desktop-lock
        desktop-polkit
        desktop-wallpaper
        desktop-session
      ];

      environment.systemPackages = [ quickshell ];
      desktop.startup = [ (lib.getExe quickshell) ];
      desktop.launcherCommand = "${lib.getExe quickshell} ipc call launcher toggle";
    };
}
