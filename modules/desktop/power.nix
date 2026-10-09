# Shutdown menu and shutdown launcher entries. Imported by the quickshell role.
#
# The actions are `desktop.power.actions` (modules/desktop.nix): shut down,
# reboot and suspend are set here, and log out once there is a session.
# Every action is a launcher entry, and the same list is the menu that
# `quickshell ipc call powermenu toggle` opens and the bar button toggles.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-power =
    { config, ... }:
    let
      lock = config.desktop.lock.command;
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
          confirm = true;
        };
        reboot = lib.mkDefault {
          name = "Reboot";
          exec = [
            "systemctl"
            "reboot"
          ];
          order = 20;
          confirm = true;
        };
        # locked first, or the machine wakes up open
        suspend = lib.mkDefault {
          name = "Suspend";
          exec =
            if lock == null then
              [
                "systemctl"
                "suspend"
              ]
            else
              [
                "sh"
                "-c"
                "${lib.escapeShellArgs lock}; sleep 1; systemctl suspend"
              ];
          order = 30;
        };
      };

      # works for any compositor: logind ends the session and with it the compositor
      desktop.power.actions.logout = lib.mkIf (config.desktop.sessions != { }) (
        lib.mkDefault {
          name = "Log out";
          exec = [
            "sh"
            "-c"
            ''loginctl terminate-session "$XDG_SESSION_ID"''
          ];
          order = 40;
          confirm = true;
        }
      );

      desktop.launcher.entries = lib.mapAttrs' (
        id: a: lib.nameValuePair "power-${id}" { inherit (a) name exec confirm; }
      ) config.desktop.power.actions;

      desktop.overlays.PowerMenu.qml = ./PowerMenu.qml;
      desktop.data.powerActions = map (a: { inherit (a) name exec confirm; }) actions;

      desktop.bar.items.PowerButton = {
        position = "right";
        order = 1000;
        qml = ./PowerButton.qml;
      };
    };
}
