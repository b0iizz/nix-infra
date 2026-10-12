# Minecraft servers, vanilla or modded, from github:Infinidoge/nix-minecraft,
# each published through the publicProxy gateways (modules/public-proxy/) on
# its own port with an SRV record.
#
#   roles = [ "minecraft-server" ];
#
# A thin wrapper: define the servers on the host with the module's own
# options, one port each. The package defaults to the newest vanilla
# release; modded ones come from the overlay (`pkgs.fabricServers`,
# `neoforgeServers`, `paperServers`, ...), mods through `symlinks.mods`:
#
#   services.minecraft-servers.servers.vanilla.enable = true;
#   # a module function, for pkgs
#   ({ pkgs, ... }: {
#     services.minecraft-servers.servers.fabric = {
#       enable = true;
#       package = pkgs.fabricServers.fabric;
#       serverProperties.server-port = 25566;
#       symlinks.mods = pkgs.linkFarmFromDrvs "mods" [ (pkgs.fetchurl { ... }) ];
#     };
#   })
#
# Server `<name>` is at `<name>.mc.<defaultZone>`, the SRV record carries the
# port, so players type the name alone. Change it with
# `publicProxy.expose.minecraft-<name>`. Newer releases: `nix flake update
# nix-minecraft`. Console: `sudo tmux -S /run/minecraft/<name>.sock attach`,
# from another machine `ssh -t <host> sudo tmux ...` (tmux needs the tty);
# leave with Ctrl-b d, since `stop` or Ctrl-c stops the server.
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
        in
        {
          imports = [
            inputs.nix-minecraft.nixosModules.minecraft-servers
            self.modules.nixos.persist
            # Ctrl-d at the start of a console line ends the server's input:
            # its console reader quits for good without a log line, and the
            # unit's ExecStop, which types `stop` there, hangs until it is
            # killed. Each server has its own tmux server, so catch the key there.
            {
              options.services.minecraft-servers.servers = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule (
                    { name, config, ... }:
                    {
                      config.extraStartPost = lib.mkIf config.managementSystem.tmux.enable ''
                        ${lib.getExe pkgs.tmux} -S ${config.managementSystem.tmux.socketPath name} bind-key -n C-d display-message "Ctrl-d would end the console input; leave with Ctrl-b d"
                      '';
                    }
                  )
                );
              };
            }
          ];

          # for the console: the servers run in the module's tmux, the same
          # `pkgs.tmux`, which nothing else puts on PATH
          environment.systemPackages = [ pkgs.tmux ];

          # the servers are unfreeRedistributable
          nixpkgs.config.allowUnfree = lib.mkDefault true;
          # newest vanilla as `pkgs.minecraft-server`, and the modded servers
          nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

          services.minecraft-servers = {
            enable = true;
            eula = true;
          };

          # the firewall stays shut: the proxy opens each port on the tunnel only
          publicProxy.expose = lib.mapAttrs' (
            name: s:
            lib.nameValuePair "minecraft-${name}" {
              protocol = "tcp";
              subdomain = lib.mkDefault "${name}.mc";
              port = s.serverProperties.server-port or 25565;
              dns.srv.service = "minecraft";
              # ponytail: no PROXY protocol (vanilla cannot read it), so every
              # player comes from the gateway's address and IP bans hit everyone;
              # set `proxyProtocol` on a server that reads it (Paper, a Fabric mod)
            }
          ) (lib.filterAttrs (_: s: s.enable) svc.servers);

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
