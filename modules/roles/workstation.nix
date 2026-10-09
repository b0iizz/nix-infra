# What a machine someone sits at needs, whatever compositor it runs: UEFI boot,
# NetworkManager, removable media, file sharing and the home directories that
# matter. Nothing in it is specific to a model or a person.
#
#   roles = [ "workstation" "quickshell" "niri" "greeter" ];
#
# The groups in `registry.userPolicy.roleGroups.workstation` (flake-root.nix)
# are the ones this role creates (`networkmanager`) or NixOS always has.
#
# On a host with `disko-root-impermanence` it keeps the saved networks, paired
# devices and the home directories below; more are added through `persist.*`.
{ self, lib, ... }:
{
  flake.modules.nixos.workstation =
    { config, pkgs, ... }:
    {
      imports = [ self.modules.nixos.persist ];

      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

      networking.networkmanager = {
        enable = true;
        plugins = [ pkgs.networkmanager-openvpn ];
      };

      services.gvfs.enable = true;
      programs.localsend.enable = true;

      persist = {
        directories = [
          "/var/lib/NetworkManager"
          "/etc/NetworkManager/system-connections"
          # backlight and rfkill state, timers that catch up after a reboot
          "/var/lib/systemd/backlight"
          "/var/lib/systemd/rfkill"
          "/var/lib/systemd/timers"
        ]
        ++ lib.optional config.hardware.bluetooth.enable "/var/lib/bluetooth";

        home = {
          directories = [
            "Documents"
            "Downloads"
            "Pictures"
            "Videos"
            "Music"
          ];
          # not the directory: the key in it is placed at every activation
          files = [ ".ssh/known_hosts" ];
        };
      };
    };

  # Power management of a machine on battery.
  flake.modules.nixos.laptop =
    { ... }:
    {
      imports = [ self.modules.nixos.persist ];

      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      persist.directories = [
        "/var/lib/power-profiles-daemon"
        "/var/lib/upower"
      ];
    };
}
