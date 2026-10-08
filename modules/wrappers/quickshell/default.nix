# Quickshell, wrapped: a QML tree assembled from the `desktop` registry
# (modules/desktop.nix) and `passthru.theme`, started with `--path`.
#
#   Theme.qml       singleton: colors (base00..), fonts, sizes, opacities of
#                   `passthru.theme`, e.g. `Theme.base0D`, `Theme.fontMonospace`,
#                   `Theme.opacityDesktop`
#   ShellData.qml   singleton: `workspaces` and `launcherEntries` from the registry
#   Bar.qml         one panel per screen; the bar items of the registry, by
#                   position and order
#   Launcher.qml    toggled with `quickshell ipc call launcher toggle`
#   <Item>.qml      one per `desktop.bar.items.<Item>`; may use Theme and ShellData
#
# The tree is flat on purpose: QML finds the types next to it through the
# generated qmldir. Nothing in it knows about Hyprland or any other module.
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  cap = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;

  qmldir =
    types:
    lib.concatMapStringsSep "\n" (
      t:
      "${
        lib.optionalString (builtins.elem t [
          "Theme"
          "ShellData"
        ]) "singleton "
      }${t} 1.0 ${t}.qml"
    ) types
    + "\n";

  program = pkgs: desktop: [
    (w.withPackage pkgs.quickshell)
    (
      final:
      let
        t = final.passthru.theme;

        items = lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name)) (
          lib.mapAttrsToList (name: i: i // { inherit name; }) desktop.bar.items
        );
        badNames = lib.filter (i: builtins.match "[A-Z][A-Za-z0-9]*" i.name == null) items;
        inPosition =
          p: lib.concatMapStringsSep "\n" (i: "${i.name} {}") (lib.filter (i: i.position == p) items);

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

        theme = singleton (
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (n: v: property "color" n (builtins.toJSON "#${v}")) t.colors
            ++ lib.mapAttrsToList (n: v: property "string" "font${cap n}" (builtins.toJSON v)) t.fonts
            ++ lib.mapAttrsToList (n: v: property "int" "size${cap n}" (toString v)) t.sizes
            ++ lib.mapAttrsToList (n: v: property "real" "opacity${cap n}" (builtins.toJSON v)) t.opacity
            ++ [ (property "bool" "dark" (lib.boolToString (t.polarity == "dark"))) ]
          )
        );

        shellData = singleton (
          lib.concatStringsSep "\n" [
            (property "var" "workspaces" (builtins.toJSON desktop.workspaces))
            (property "var" "launcherEntries" (builtins.toJSON (lib.attrValues desktop.launcher.entries)))
          ]
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
      assert lib.assertMsg (badNames == [ ])
        "quickshell: bar items are QML types and need a capitalised name: ${
          toString (map (i: i.name) badNames)
        }";
      {
        passthru.files = {
          "shell.qml" = _: ''
            import Quickshell

            ShellRoot {
                Bar {}
                Launcher {}
            }
          '';
          "qmldir" =
            _:
            qmldir (
              [
                "Theme"
                "ShellData"
                "Bar"
                "Launcher"
              ]
              ++ map (i: i.name) items
            );
          "Theme.qml" = _: theme;
          "ShellData.qml" = _: shellData;
          "Bar.qml" = _: bar;
          "Launcher.qml" = _: ./Launcher.qml;
        }
        // lib.listToAttrs (map (i: lib.nameValuePair "${i.name}.qml" (_: i.qml)) items);

        passthru.wrapper.flags.__append = [ "--path ${final.passthru.config.dir}" ];
      }
    )
  ];
in
{
  perSystem =
    { config, pkgs, ... }:
    {
      wrappers.quickshell = w.program (program pkgs config.desktop);
    };

  # Opt-in per host (`roles = [ "quickshell" ]`). Hyprland (or whatever
  # compositor) picks the start command and the launcher key up through
  # `desktop.*`, see modules/desktop.nix.
  flake.modules.nixos.quickshell =
    { pkgs, ... }:
    let
      quickshell = self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell;
    in
    {
      imports = [ self.modules.nixos.desktop ];

      environment.systemPackages = [ quickshell ];
      desktop.startup = [ (lib.getExe quickshell) ];
      desktop.launcher = "${lib.getExe quickshell} ipc call launcher toggle";
    };
}
