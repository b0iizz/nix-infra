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
      # every generation puts its kernel and initrd (~70 MB) on the 1 GiB ESP
      boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
      boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

      nix.gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 30d";
      };

      # known_hosts lives in a directory of its own: `ssh-keygen -R` replaces
      # the file by renaming over it, which a bind-mounted file refuses
      programs.ssh.extraConfig = "UserKnownHostsFile %d/.local/share/ssh/known_hosts";

      networking.networkmanager = {
        enable = true;
        plugins = [ pkgs.networkmanager-openvpn ];
      };
      # NetworkManager does DHCP itself; facter's dhcpcd on the same interface
      # fights it for the DHCPv6 port
      hardware.facter.detected.dhcp.enable = false;

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
        ++ lib.optional config.hardware.bluetooth.enable "/var/lib/bluetooth"
        # enrolled fingerprints (some hardware profiles turn the daemon on)
        ++ lib.optional config.services.fprintd.enable "/var/lib/fprint";

        home.directories = [
          "Documents"
          "Downloads"
          "Pictures"
          "Videos"
          "Music"
          ".local/share/ssh" # known_hosts
          # evaluation and download caches, or the first deploy after
          # every boot starts from scratch; trusted flake settings
          ".cache/nix"
          ".local/share/nix"
        ];
      };
    };

  # Power management of a machine on battery.
  flake.modules.nixos.laptop =
    { config, lib, ... }:
    {
      imports = [ self.modules.nixos.persist ];

      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      # a laptop is not a server: no ssh from the café network
      services.openssh.openFirewall = lib.mkDefault false;

      # a suspended laptop with an empty battery loses its session, so it
      # moves to the hibernation image after an hour (where there is one)
      services.logind.settings.Login.HandleLidSwitch = lib.mkIf (config.boot.resumeDevice != "") (
        lib.mkDefault "suspend-then-hibernate"
      );
      systemd.sleep.settings.Sleep.HibernateDelaySec = lib.mkDefault "1h";

      persist.directories = [
        "/var/lib/power-profiles-daemon"
        "/var/lib/upower"
      ];
    };
}
