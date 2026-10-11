# Vanilla Minecraft server, the newest release nix-minecraft packages,
# published through the publicProxy gateways (modules/public-proxy/) on the
# default port with an SRV record.
#
#   roles = [ "minecraft-server" ];
#
# A thin wrapper around github:Infinidoge/nix-minecraft: the server is
# `services.minecraft-servers.servers.vanilla`; set its options (whitelist,
# operators, serverProperties, jvmOpts) on the host. The address is
# `mc.<defaultZone>`; change it with `publicProxy.expose.minecraft`. Newer
# release: `nix flake update nix-minecraft`. Console:
# `sudo tmux -S /run/minecraft/vanilla.sock attach`.
#
# The host also has to be in `publicProxy.origins` (see
# modules/public-proxy/module.nix). The role accepts Mojang's EULA
# (https://aka.ms/MinecraftEULA) and allows unfree packages.
{ withInputs, ... }:
withInputs
  {
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    { inputs, self, ... }:
    {
      flake.modules.nixos.minecraft-server =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          svc = config.services.minecraft-servers;
          port = svc.servers.vanilla.serverProperties.server-port or 25565;
        in
        {
          imports = [
            inputs.nix-minecraft.nixosModules.minecraft-servers
            self.modules.nixos.persist
          ];

          # the server is unfreeRedistributable
          nixpkgs.config.allowUnfree = lib.mkDefault true;
          nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

          services.minecraft-servers = {
            enable = true;
            eula = true;
            servers.vanilla = {
              enable = true;
              package = pkgs.vanillaServers.vanilla;
            };
          };

          # the firewall stays shut: the proxy opens the port on the tunnel only
          publicProxy.expose.minecraft = {
            protocol = "tcp";
            subdomain = lib.mkDefault "mc";
            inherit port;
            dns.srv.service = "minecraft";
            # ponytail: vanilla cannot read the PROXY protocol, so every player
            # comes from the gateway's address and IP bans hit everyone; switch
            # to a server that reads it (e.g. Paper) if those are ever needed
            proxyProtocol = false;
          };

          persist.directories = [
            {
              directory = svc.dataDir;
              inherit (svc) user group;
              mode = "0770";
            }
          ];
        };
    }
  )
