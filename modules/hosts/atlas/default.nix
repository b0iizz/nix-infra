# Home server (ASUS PRIME N100I-D D4, Intel N100): NAS, web pages, Minecraft
# servers, Jellyfin and the like. Running: copyparty, and a Fabric 26.3
# Minecraft server with performance mods at mc.greb.es (role `minecraft-server`).
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
    # the LAN when home, else through the hub (modules/hosts/phoebe)
    deploy.targetHosts = [
      "192.168.178.10"
      (lib.head config.wireguard.resolved.hub.members.atlas.addresses)
    ];
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

      # Fabric on Minecraft 26.3 at mc.greb.es, port 25565. The game version is
      # pinned; the Fabric loader moves with `nix flake update nix-minecraft`.
      # Mods from Modrinth, the newest build for 26.3 each (C2ME and ScalableLux
      # publish alphas only); bump version, file and hash together. More
      # servers go next to it, see modules/roles/minecraft-server.nix
      (
        { pkgs, ... }:
        let
          modrinth =
            id: version: file: sha512:
            pkgs.fetchurl {
              name = file;
              url = "https://cdn.modrinth.com/data/${id}/versions/${version}/${
                builtins.replaceStrings [ "+" ] [ "%2B" ] file
              }";
              inherit sha512;
            };
        in
        {
          services.minecraft-servers.servers.survival = {
            enable = true;
            # nix-minecraft's Fabric wrapper runs nixpkgs' default Java (21);
            # 26.3 needs the one its vanilla server declares (25)
            package = pkgs.fabricServers.fabric-26_3.override {
              jre_headless = pkgs.vanillaServers.vanilla-26_3.java;
            };
            symlinks.mods = pkgs.linkFarmFromDrvs "mods" [
              (modrinth "P7dR8mSH" "v2j28coa" "fabric-api-0.162.0+26.3.jar"
                "5ab70908952f1d2346d16b122ca31327f4055db59c279a1bc3c3c581ce359bb541cba15730f55b0727be7c7c4debc4a4412a183c228e0d4dea81c734f7b412ce"
              )
              (modrinth "uXXizFIs" "d5ddUdiB" "ferritecore-9.0.0-fabric.jar"
                "d81fa97e11784c19d42f89c2f433831d007603dd7193cee45fa177e4a6a9c52b384b198586e04a0f7f63cd996fed713322578bde9a8db57e1188854ae5cbe584"
              )
              (modrinth "gvQqBUqZ" "xS0Q8LSi" "lithium-fabric-0.26.2+mc26.3.jar"
                "4d7fee66132eedc71feab9390b92c95d7058edbdad0fecfac1d836a2950b97a7ca463afbede61c7ef361ce65e1f927ab9e89dde5bf2e0e0ce486afb5c5dbee40"
              )
              (modrinth "Ps1zyz6x" "g4eqNSKd" "ScalableLux-fabric-mc26.3-0.3.0-alpha.0.6-all.jar"
                "ded5a939fb20ab81c1f33b147ca9b98050773dbb28dff16df939c7d567b626809522994ec8dbfb99e7f498dc6a4e62f25e141a87d18efb43f73fc5ad1569ccc9"
              )
              (modrinth "VSNURh3q" "ODMLK8M9" "c2me-fabric-mc26.3-0.4.2-alpha.0.90.jar"
                "d0140ebdad22b7ee002c4e17685dbb254d667562840000ef98cedabafa53bc67d1011b9fc4d70f26f964fc781373e61583d39b001e7e15644ba97dd19ea1c2ce"
              )
              (modrinth "fALzjamp" "4Eotm6ov" "Chunky-Fabric-1.5.3.jar"
                "b83bfe7b218d0aa6232af977ae741dc1f82b10e50cd12bb759f65cf416b8b62beccb543e587ef0b9670abe03815660f8e091bc6823624d65cf07300571573516"
              )
              (modrinth "r0v8vy1s" "nSBWPz6x" "alternate-current-mc26.3-1.9.0.jar"
                "347fa8d0338a7e113c0cde70306d05037dbf9fc1e33c476159b4f5cf7b4fce8d3798d820ebf0e0dedd8450417802cb3a030bdcbecaf509961a83b2e43a469ad5"
              )
            ];
          };
          publicProxy.expose.minecraft-survival.subdomain = "mc";
        }
      )
    ];
  };
}
