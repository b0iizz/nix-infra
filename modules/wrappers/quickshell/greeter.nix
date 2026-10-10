# The login screen: a second quickshell wrapper, run by greetd inside cage (a
# kiosk compositor, so the greeter is a plain fullscreen window), themed like
# the shell. It authenticates through greetd and then runs the session command.
#
#   settings.users    names to offer
#   settings.sessions [ { name, exec } ] to choose from, the first is the default
#                     (greetd runs the argv as the user)
#   settings.fingerprint  mention the reader in the hint
#   settings.wallpaper    `{ saved, default }`: behind the form the chosen
#                         user's current image, `<saved>/<user>`, or `default`
#                         (modules/desktop/wallpaper/wallpaper.nix); null for none
#
# The role `greeter` fills these from the host: its normal users and
# `desktop.sessions`, which the compositor roles fill. As each is the wrapped
# compositor's own start command, logging in starts it with its config, no
# session file involved.
#
# The screen is the lock screen's: AuthView and AuthForm are the same files
# (modules/desktop/auth/), copied into this tree.
{ self, lib, ... }:
let
  w = self.lib.wrappers;
  qml = self.lib.quickshell;

  program = pkgs: [
    (w.withPackage pkgs.quickshell)
    {
      passthru.settings = {
        users = _: [ ];
        sessions = _: [ ];
        fingerprint = _: false;
        wallpaper = _: null;
      };
    }
    (
      final:
      let
        s = final.passthru.settings;
      in
      {
        passthru.files = {
          "shell.qml" = _: ''
            import Quickshell

            ShellRoot {
                Greeter {}
            }
          '';
          "qmldir" =
            _:
            qml.qmldir
              [
                "Theme"
                "GreeterData"
              ]
              [
                "Theme"
                "GreeterData"
                "Greeter"
                "AuthForm"
                "AuthView"
              ];
          "Theme.qml" = _: qml.theme final.passthru.theme;
          "GreeterData.qml" =
            _:
            qml.singleton (
              lib.concatStringsSep "\n" [
                (qml.property "var" "users" (builtins.toJSON s.users))
                (qml.property "var" "sessions" (builtins.toJSON s.sessions))
                (qml.property "bool" "fingerprint" (lib.boolToString s.fingerprint))
                (qml.property "var" "wallpaper" (builtins.toJSON s.wallpaper))
              ]
            );
          "Greeter.qml" = _: ./Greeter.qml;
          "AuthForm.qml" = _: ../../desktop/auth/AuthForm.qml;
          "AuthView.qml" = _: ../../desktop/auth/AuthView.qml;
        };

        passthru.wrapper.flags.__append = [ "--path ${final.passthru.config.dir}" ];
      }
    )
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrappers.quickshell-greeter = w.program (program pkgs);
    };

  # Opt-in per host (`roles = [ "greeter" ]`) next to a compositor role.
  flake.modules.nixos.greeter =
    { config, pkgs, ... }:
    let
      greeter = self.packages.${pkgs.stdenv.hostPlatform.system}.quickshell-greeter.extend {
        passthru.settings = {
          users = _: lib.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);
          sessions =
            _:
            map (s: { inherit (s) name exec; }) (
              lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name)) (
                lib.attrValues config.desktop.sessions
              )
            );
          fingerprint = _: config.desktop.fingerprint;
          wallpaper = _: { inherit (config.desktop.data.wallpaper) saved default; };
        };
      };
    in
    {
      imports = with self.modules.nixos; [
        desktop
        desktop-auth
        desktop-session
        desktop-wallpaper
      ];

      # greetd's stack is `auth substack login`, with the reader first. Swap
      # the substack for one of our own that has the password first, so that
      # the password prompt is there at once (the reason is in
      # modules/desktop/auth/polkit.nix). `login`, the console's, stays as it is.
      security.pam.services.quickshell-greeter-auth.rules.auth.fprintd.order =
        config.security.pam.services.quickshell-greeter-auth.rules.auth.unix.order + 10;
      security.pam.services.greetd.rules.auth.login.modulePath = lib.mkForce "quickshell-greeter-auth";

      assertions = [
        {
          assertion = config.desktop.sessions != { };
          message = "the greeter role needs a compositor role that adds to `desktop.sessions` (hyprland, niri)";
        }
      ];

      services.greetd = {
        enable = true;
        settings.default_session = {
          user = "greeter";
          # -d: no title bar; cage asks clients to draw their own otherwise
          command = "${lib.getExe pkgs.cage} -d -s -- ${lib.getExe greeter}";
        };
      };
    };
}
