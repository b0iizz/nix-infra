# The notification daemon, imported by the quickshell role: the `Notifications`
# overlay owns org.freedesktop.Notifications and shows popups top right.
{ self, ... }:
{
  flake.modules.nixos.desktop-notifications = {
    imports = [ self.modules.nixos.desktop ];

    desktop.overlays.Notifications.qml = ./Notifications.qml;
  };
}
