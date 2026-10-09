# Idle daemon, imported by the quickshell role: the `Idle` overlay dims the
# screen, locks it and suspends the machine after the screen has been idle
# for the given seconds. Programs that inhibit idling (a video player) hold
# all of it back. Everything is on by default; `null` leaves a step out.
#
#   desktop.idle.enable    the whole daemon
#   desktop.idle.dim       seconds until the screen is dimmed (brightness comes
#                          back on the first input)
#   desktop.idle.lock      seconds until the lock screen, if there is one
#   desktop.idle.suspend   seconds until suspend, only while on battery (locked
#                          first, as in the "Suspend" power action)
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-idle =
    { config, ... }:
    let
      cfg = config.desktop.idle;
      seconds =
        default:
        lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          inherit default;
        };
    in
    {
      key = "modules/desktop/idle.nix";

      imports = [ self.modules.nixos.desktop ];

      options.desktop.idle = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        dim = seconds 240;
        lock = seconds 300;
        suspend = seconds 900;
      };

      config = lib.mkIf cfg.enable {
        desktop.overlays.Idle.qml = ./Idle.qml;
        desktop.data.idle = {
          inherit (cfg) dim lock suspend;
          lockCommand = config.desktop.lock.command;
          suspendCommand = config.desktop.power.actions.suspend.exec or null;
        };

        # tells the daemon whether the machine is on battery
        services.upower.enable = lib.mkIf (cfg.suspend != null) (lib.mkDefault true);
      };
    };
}
