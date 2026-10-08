# Shutdown menu and shutdown launcher entries. Imported by the quickshell role.
#
# The actions are `desktop.power.actions` (modules/desktop.nix): shut down,
# reboot and suspend are set here, a compositor role adds its own log out.
# Every action is a launcher entry, and the same list is the menu that
# `quickshell ipc call powermenu toggle` opens and the bar button toggles.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-power =
    { config, ... }:
    let
      actions = lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name)) (
        lib.attrValues config.desktop.power.actions
      );
    in
    {
      imports = [ self.modules.nixos.desktop ];

      desktop.power.actions = {
        poweroff = lib.mkDefault {
          name = "Shut down";
          exec = [
            "systemctl"
            "poweroff"
          ];
          order = 10;
        };
        reboot = lib.mkDefault {
          name = "Reboot";
          exec = [
            "systemctl"
            "reboot"
          ];
          order = 20;
        };
        suspend = lib.mkDefault {
          name = "Suspend";
          exec = [
            "systemctl"
            "suspend"
          ];
          order = 30;
        };
      };

      desktop.launcher.entries = lib.mapAttrs' (
        id: a: lib.nameValuePair "power-${id}" { inherit (a) name exec; }
      ) config.desktop.power.actions;

      desktop.overlays.PowerMenu.qml =
        builtins.replaceStrings
          [ "ACTIONS_JSON" ]
          [
            (builtins.toJSON (map (a: { inherit (a) name exec; }) actions))
          ]
          (builtins.readFile ./PowerMenu.qml);

      desktop.bar.items.PowerButton = {
        position = "right";
        order = 1000;
        qml = ./PowerButton.qml;
      };
    };
}
