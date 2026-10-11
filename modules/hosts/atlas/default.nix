# Home server (ASUS PRIME N100I-D D4, Intel N100): NAS, web pages, Minecraft
# servers, Jellyfin and the like. The services are not written yet.
#
# Atlas is the Titan who carries the sky on his shoulders, Prometheus's
# brother: this machine carries the weight of everything else.
#
# Disks: root on the SSD with the wiped-every-boot root, no LUKS (it has to
# boot without anyone there), 24 GiB swap; the two 4 TB IronWolfs as a
# RAID 1 at /data.
{ ... }:
{
  registry.hosts.atlas = {
    path = ./.;
    stateVersion = "26.11";
    roles = [
      "disko-root-impermanence"
      "disko-raid"
    ];
    provision.targetUser = "root";
    provision.targetHost = "192.168.178.44";

    modules = [
      {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # 8 GiB of RAM for Minecraft and Jellyfin: a 24 GiB swap partition
        # for what does not fit, zram in front of it for speed
        disko-layouts.swap.size = "24GiB";
        zramSwap.enable = true;
      }
    ];
  };
}
