# Low battery warnings, imported by the quickshell role: the `BatteryWarning`
# overlay sends a notification when the charge falls to `low` percent and an
# urgent one at `critical`, once each per discharge. On by default on hosts
# whose facter report says they have a battery.
#
#   desktop.batteryWarning.enable
#   desktop.batteryWarning.low        percent
#   desktop.batteryWarning.critical   percent
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-battery =
    { config, pkgs, ... }:
    let
      cfg = config.desktop.batteryWarning;
      # absent on the hosts of the desktop-roles check, which have no registry
      report = (config.host-context or { }).facter.report or null;
      percent =
        default:
        lib.mkOption {
          type = lib.types.ints.between 1 100;
          inherit default;
        };
    in
    {
      key = "modules/desktop/battery.nix";

      imports = [ self.modules.nixos.desktop ];

      options.desktop.batteryWarning = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = self.lib.facter.hasBattery report;
          defaultText = "whether the facter report has a battery";
        };
        low = percent 20;
        critical = percent 10;
      };

      config = lib.mkIf cfg.enable {
        desktop.overlays.BatteryWarning.qml = ./BatteryWarning.qml;
        desktop.data.batteryWarning = { inherit (cfg) low critical; };

        # the warnings are notifications, and the charge comes from upower
        environment.systemPackages = [ pkgs.libnotify ];
        services.upower.enable = lib.mkDefault true;
      };
    };
}
