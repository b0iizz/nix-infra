# What the places that ask for a password share: the QML they are built from
# (AuthForm, AuthView) and the fingerprint daemon. Imported by the lock screen,
# the polkit agent and (through its own tree) the greeter.
#
# Note that `services.fprintd` makes NixOS try the reader first in every PAM
# service that doesn't opt out (sudo, login, ...), it is a system-wide switch.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-auth =
    { config, ... }:
    {
      key = "modules/desktop/auth.nix";

      imports = with self.modules.nixos; [
        desktop
        persist
      ];

      # the enrolled fingerprints
      persist.directories = lib.optional config.services.fprintd.enable "/var/lib/fprint";

      desktop.components.AuthForm.qml = ./AuthForm.qml;
      desktop.components.AuthView.qml = ./AuthView.qml;
      desktop.data.fingerprint = config.desktop.fingerprint;

      services.fprintd.enable = lib.mkIf config.desktop.fingerprint (lib.mkDefault true);
    };
}
