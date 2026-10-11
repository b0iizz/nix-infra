# Home server (ASUS PRIME N100I-D D4, Intel N100): NAS, web pages, Minecraft
# servers, Jellyfin and the like. The services are not written yet.
#
# Atlas is the Titan who carries the sky on his shoulders, Prometheus's
# brother: this machine carries the weight of everything else.
#
# Disks: root on the SSD with the wiped-every-boot root, no LUKS (it has to
# boot without anyone there), 24 GiB swap; the two 4 TB IronWolfs as a
# RAID 1 at /data, served by copyparty at nas.grebes.net through the gateway
# phoebe. Static address 192.168.178.10.
{ ... }:
{
  registry.hosts.atlas = {
    path = ./.;
    stateVersion = "26.11";
    roles = [
      "disko-root-impermanence"
      "disko-raid"
      "copyparty"
    ];
    # the static address below, for deploy and for a reinstall by kexec
    deploy.targetHost = "192.168.178.10";
    provision.targetUser = "root";
    provision.targetHost = "192.168.178.10";

    modules = [
      {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # /data/share at https://nas.grebes.net: the top is for admin only,
        # `public` is read by everyone and edited by family, `private` is
        # for family and admin alone (guests see nothing)
        copyparty.accounts = [
          "admin"
          "family"
        ];
        copyparty.volumes = {
          "/" = {
            path = "/data/share";
            access.rwmd = [ "admin" ];
          };
          "/public" = {
            path = "/data/share/public";
            access = {
              r = "*";
              rwmd = [
                "admin"
                "family"
              ];
            };
          };
          "/private" = {
            path = "/data/share/private";
            access.rwmd = [
              "admin"
              "family"
            ];
          };
        };

        # through the gateway phoebe
        publicProxy.expose.copyparty = {
          subdomain = "nas";
          zone = "grebes.net";
        };

        # 8 GiB of RAM for Minecraft and Jellyfin: a 24 GiB swap partition
        # for what does not fit, zram in front of it for speed
        disko-layouts.swap.size = "24GiB";
        zramSwap.enable = true;

        # 192.168.178.10, below the Fritz!Box DHCP range (from .20); matched by
        # the MAC so the interface name does not matter
        networking.useDHCP = false;
        networking.useNetworkd = true;
        networking.nameservers = [ "192.168.178.1" ];
        systemd.network.enable = true;
        systemd.network.networks."10-lan" = {
          matchConfig.MACAddress = "a0:ad:9f:14:18:b7";
          address = [ "192.168.178.10/24" ];
          gateway = [ "192.168.178.1" ];
        };
      }
    ];
  };
}
