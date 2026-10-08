# Lock screen, imported by the quickshell role: the `LockScreen` overlay, a
# PAM service for it and a "Lock" power action. Idle locking and a key bind
# are not part of it.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-lock = {
    imports = [ self.modules.nixos.desktop ];

    # the stock service: unix password of the current user
    security.pam.services.quickshell-lock = { };

    desktop.overlays.LockScreen.qml = ./LockScreen.qml;

    desktop.power.actions.lock = lib.mkDefault {
      name = "Lock";
      exec = [
        "quickshell"
        "ipc"
        "call"
        "lock"
        "lock"
      ];
      order = 5;
    };
  };
}
