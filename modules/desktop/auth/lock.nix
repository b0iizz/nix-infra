# Lock screen, imported by the quickshell role: the `LockScreen` overlay, its
# PAM services, a "Lock" power action and the lock before every sleep. Idle
# locking and a key bind are not part of it.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-lock =
    { config, pkgs, ... }:
    let
      # Every sleep locks first, also the lid's, which logind starts without
      # asking the shell: swayidle holds it back until the command is done,
      # and the lock screen needs a moment to show up.
      lockBeforeSleep = pkgs.writeShellApplication {
        name = "lock-before-sleep";
        text = "exec ${lib.getExe pkgs.swayidle} -w before-sleep ${lib.escapeShellArg "${lib.escapeShellArgs config.desktop.lock.command}; sleep 1"}";
      };
    in
    {
      imports = with self.modules.nixos; [
        desktop
        desktop-auth
        desktop-wallpaper
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

      desktop.overlays.LockScreen.qml = ./LockScreen.qml;

      desktop.lock.command = lib.mkDefault (self.lib.quickshellIpc "lock" "lock");

      desktop.startup = [ (lib.getExe lockBeforeSleep) ];

      desktop.power.actions.lock = lib.mkDefault {
        name = "Lock";
        exec = config.desktop.lock.command;
        order = 5;
      };
    };
}
