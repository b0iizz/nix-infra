# Lock screen, imported by the quickshell role: the `LockScreen` overlay, its
# PAM services and a "Lock" power action. Idle locking and a key bind are not
# part of it.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-lock =
    { config, pkgs, ... }:
    {
      imports = with self.modules.nixos; [
        desktop
        desktop-auth
      ];

      # The screen runs two conversations at once (see LockScreen.qml): the
      # stock service with the unix password only, and one with the reader only.
      security.pam.services.quickshell-lock.fprintAuth = false;
      security.pam.services.quickshell-lock-fingerprint = lib.mkIf config.desktop.fingerprint {
        text = ''
          auth    required ${config.services.fprintd.package}/lib/security/pam_fprintd.so
          account required ${pkgs.linux-pam}/lib/security/pam_permit.so
        '';
      };

      desktop.overlays.LockScreen.qml =
        builtins.replaceStrings
          [ "FINGERPRINT" ]
          [
            (lib.boolToString config.desktop.fingerprint)
          ]
          (builtins.readFile ./LockScreen.qml);

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
