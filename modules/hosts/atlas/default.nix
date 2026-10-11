# Home server (ASUS PRIME N100I-D D4, Intel N100): NAS, web pages, Minecraft
# servers, Jellyfin and the like. Running: copyparty, and a vanilla Minecraft
# server at mc.greb.es (role `minecraft-server`).
#
# Atlas is the Titan who carries the sky on his shoulders, Prometheus's
# brother: this machine carries the weight of everything else.
#
# Disks: root on the SSD with the wiped-every-boot root, no LUKS (it has to
# boot without anyone there), 24 GiB swap; the two 4 TB IronWolfs as a
# RAID 1 at /data, served by copyparty at nas.grebes.net through the gateway
# phoebe. Static address 192.168.178.10.
{ config, lib, ... }:
{
  registry.hosts.atlas = {
    path = ./.;
    stateVersion = "26.11";
    roles = [
      "disko-root-impermanence"
      "disko-raid"
      "copyparty"
      "minecraft-server"
    ];
    # deployed through the hub (modules/hosts/phoebe), from anywhere; the LAN
    # address below for a reinstall by kexec, or `deploy --target` when the
    # tunnel is down
    deploy.targetHost = lib.head config.wireguard.resolved.hub.members.atlas.addresses;
    provision.targetUser = "root";
    provision.targetHost = "192.168.178.10";

    modules = [
      {
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # /data/share at https://nas.grebes.net, login with name and
        # password: admin may do anything everywhere, the top is admin's
        # only, `public` is read by everyone and edited by the family,
        # `video`, `music` and `images` are the family's (guests see nothing)
        copyparty.accounts = [
          "admin"
          "joni"
          "anni"
        ];
        copyparty.groups.family = [
          "joni"
          "anni"
        ];
        copyparty.usernames = true;
        # SFTP only through the encrypted hub tunnel (modules/hosts/phoebe),
        # with SSH keys: sftp -P 3922 joni@10.10.0.55:/video (start in a
        # folder: only admin may list `/` over SFTP)
        copyparty.sftp.addresses = config.wireguard.resolved.hub.members.atlas.addresses;
        # a plain key per person (FIDO2 keys do not work); joni's is made by
        # `agenix generate` for prometheus (modules/hosts/prometheus)
        copyparty.sftp.keys.joni =
          let
            pub = config.registry.secretsDir + "/generated/copyparty-sftp-joni.pub";
          in
          lib.optional (builtins.pathExists pub) (lib.fileContents pub);
        networking.firewall.interfaces.${config.wireguard.resolved.hub.interface}.allowedTCPPorts = [
          3922
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
                "@family"
              ];
            };
          };
        }
        // lib.genAttrs [ "/video" "/music" "/images" ] (url: {
          path = "/data/share${url}";
          access.rwmd = [
            "admin"
            "@family"
          ];
        });

        # through the gateway phoebe
        publicProxy.expose.copyparty = {
          subdomain = "nas";
          zone = "grebes.net";
          # per request; bounds what a stolen login can fill in one go
          maxBodySize = "50G";
        };
        # in the page titles instead of the host name
        services.copyparty.settings = {
          bname = "nas.grebes.net";
          doctitle = "nas.grebes.net";
        };

        # newest vanilla at mc.greb.es, port 25565; more servers (modded too)
        # go next to it, see modules/roles/minecraft-server.nix
        services.minecraft-servers.servers.vanilla.enable = true;
        publicProxy.expose.minecraft-vanilla.subdomain = "mc";

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
