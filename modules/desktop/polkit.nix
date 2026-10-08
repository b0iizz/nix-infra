# The polkit agent, imported by the quickshell role: the `PolkitAgent` overlay
# and a PAM service for polkit that asks for the password first and the
# fingerprint second.
#
# Polkit's helper runs a single PAM conversation, and with the reader first
# (NixOS' default) the password prompt would only show up after the reader
# gave up. With the password first, an empty answer (Enter) falls through to
# the reader.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-polkit =
    { config, ... }:
    let
      rules = config.security.pam.services.polkit-1.rules.auth;
    in
    {
      imports = with self.modules.nixos; [
        desktop
        desktop-auth
      ];

      security.polkit.enable = lib.mkDefault true;
      security.pam.services.polkit-1.rules.auth.fprintd.order = rules.unix.order + 10;

      desktop.overlays.PolkitAgent.qml =
        builtins.replaceStrings
          [ "FINGERPRINT" ]
          [
            (lib.boolToString config.desktop.fingerprint)
          ]
          (builtins.readFile ./PolkitAgent.qml);
    };
}
