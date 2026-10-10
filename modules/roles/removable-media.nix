# External drives: udisks2 for the mounting and udiskie, started with the
# session, to mount them the moment they are plugged in (under
# /run/media/<user>/<label>) and say so in a notification.
#
#   roles = [ "workstation" "removable-media" "quickshell" ];
#
# With the quickshell role there is also a `Drives` bar item, which shows up
# while an external drive is connected, and a menu (a click on the item, or
# "Drives" in the launcher) to mount, unmount and eject them. Both are plain
# contributions to `desktop.*` (modules/desktop/options.nix): without the shell they do
# nothing, and the drives are still mounted by udiskie.
#
# External means what the kernel reports as hotplug (USB sticks and disks, SD
# card readers). Encrypted drives are not offered by the menu; udiskie unlocks
# them only with a password prompt of its own, which is not set up here.
{ self, ... }:
{
  flake.modules.nixos.removable-media =
    { lib, pkgs, ... }:
    {
      imports = [ self.modules.nixos.desktop ];

      services.udisks2.enable = true;

      # the compositors start `desktop.startup` with the session
      desktop.startup = [ "${lib.getExe pkgs.udiskie} --automount --notify --no-tray" ];

      desktop.bar.items.Drives = {
        position = "right";
        order = 350;
        qml = ../desktop/drives/Drives.qml;
      };
      desktop.overlays.DrivesMenu.qml = ../desktop/drives/DrivesMenu.qml;
      desktop.components.DriveList.qml = ../desktop/drives/DriveList.qml;

      desktop.launcher.entries.drives-menu = {
        name = "Drives";
        exec = self.lib.quickshellIpc "drivesmenu" "toggle";
      };
    };
}
