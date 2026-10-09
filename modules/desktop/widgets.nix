# Status widgets for the bar, imported by the quickshell role: clock, volume,
# brightness and network are always there, wifi, bluetooth and battery only on
# hosts whose facter report (modules/lib/facter.nix) has that hardware. The
# others are not even compiled into the shell.
#
# Every one is a `desktop.bar.items.<Name>` and is switched with its `enable`:
#
#   desktop.bar.items.Clock.enable = false;
#   desktop.bar.items.Wifi.enable = true;   # report missing or out of date
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-widgets =
    { config, ... }:
    let
      # absent on the hosts of the desktop-roles check, which have no registry
      report = (config.host-context or { }).facter.report or null;
      facter = self.lib.facter;
      items = config.desktop.bar.items;
    in
    {
      imports = [ self.modules.nixos.desktop ];

      desktop.bar.items = {
        Clock = {
          position = "center";
          qml = ./Clock.qml;
        };
        Brightness = {
          position = "right";
          order = 100;
          qml = ./Brightness.qml;
        };
        Volume = {
          position = "right";
          order = 200;
          qml = ./Volume.qml;
        };
        Bluetooth = {
          enable = lib.mkDefault (facter.hasBluetooth report);
          position = "right";
          order = 300;
          qml = ./Bluetooth.qml;
        };
        Wifi = {
          enable = lib.mkDefault (facter.hasWifi report);
          position = "right";
          order = 400;
          qml = ./Wifi.qml;
        };
        Network = {
          position = "right";
          order = 500;
          qml = ./Network.qml;
        };
        Battery = {
          enable = lib.mkDefault (facter.hasBattery report);
          position = "right";
          order = 600;
          qml = ./Battery.qml;
        };
      };

      # the right click menus; a widget that is off leaves its menu out as
      # well. Their frame is also the power menu's and the wallpaper picker's.
      desktop.components = {
        Menu.qml = ./Menu.qml;
        MenuRow.qml = ./MenuRow.qml;
        # the scrolling of Brightness and Volume
        WheelArea.qml = ./WheelArea.qml;
      };
      desktop.overlays = lib.mkMerge [
        (lib.mkIf items.Network.enable { NetworkMenu.qml = ./NetworkMenu.qml; })
        (lib.mkIf items.Wifi.enable { WifiMenu.qml = ./WifiMenu.qml; })
        (lib.mkIf items.Bluetooth.enable { BluetoothMenu.qml = ./BluetoothMenu.qml; })
      ];

      # and the same menus from the launcher, for what has no bar widget to click
      desktop.launcher.entries =
        let
          menu = name: target: {
            inherit name;
            exec = [
              "quickshell"
              "ipc"
              "call"
              target
              "toggle"
            ];
          };
        in
        lib.mkMerge [
          (lib.mkIf items.Network.enable { network-menu = menu "Network" "networkmenu"; })
          (lib.mkIf items.Wifi.enable { wifi-menu = menu "Wifi" "wifimenu"; })
          (lib.mkIf items.Bluetooth.enable { bluetooth-menu = menu "Bluetooth" "bluetoothmenu"; })
        ];

      # what the widgets read from
      hardware.bluetooth.enable = lib.mkIf items.Bluetooth.enable (lib.mkDefault true);
      services.upower.enable = lib.mkIf items.Battery.enable (lib.mkDefault true);
    };
}
