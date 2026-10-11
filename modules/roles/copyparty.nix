# NAS file server for a host with a data disk: github:9001/copyparty serving
# /data, published through the publicProxy gateways (modules/public-proxy/).
# Everyone may read and download; the account `admin` may also upload, move
# and delete. Its password is generated with agenix-rekey (`agenix generate`,
# then `agenix rekey -a`).
#
#   roles = [ "disko-root-impermanence" "disko-raid" "copyparty" ];
#
# The host also has to be in `publicProxy.origins`, and the flake needs a
# zone and a gateway (see modules/public-proxy/module.nix). The address is
# `files.<defaultZone>`; change it with `publicProxy.expose.copyparty`.
#
# The NixOS module comes from the copyparty flake (nixpkgs has none), the
# package from nixpkgs.
{ withInputs, ... }:
withInputs
  {
    copyparty = {
      url = "github:9001/copyparty";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    { inputs, self, ... }:
    {
      flake.modules.nixos.copyparty =
        { config, lib, ... }:
        let
          port = 3923;
        in
        {
          imports = [
            inputs.copyparty.nixosModules.default
            self.modules.nixos.persist
          ];

          age.secrets.copyparty-admin = {
            owner = config.services.copyparty.user;
            generator = {
              script = "alnum";
              tags = [ "password" ];
            };
          };

          services.copyparty = {
            enable = true;
            settings = {
              # the gateways reach it through the tunnel only
              i = config.publicProxy.tunnelAddresses;
              p = [ port ];
              # the gateway is the only client: believe the address it forwards
              # (`lan` covers the private tunnel addresses); the last entry of
              # X-Forwarded-For is the gateway's view, earlier ones are the
              # client's to forge
              rproxy = -1;
              xff-src = "lan";
              # the module's defaults, which setting `settings` drops
              no-reload = true;
              hist = "/var/cache/copyparty";
            };
            accounts.admin.passwordFile = config.age.secrets.copyparty-admin.path;
            volumes."/" = {
              path = "/data";
              access = {
                r = "*";
                rwmd = [ "admin" ];
              };
            };
          };

          # the module only creates the volume path, it does not take over an
          # existing mount point
          systemd.tmpfiles.rules = [
            "z /data 0755 ${config.services.copyparty.user} ${config.services.copyparty.group}"
          ];

          publicProxy.expose.copyparty = {
            subdomain = lib.mkDefault "files";
            inherit port;
            maxBodySize = lib.mkDefault "0"; # uploads of any size
          };

          # the index of /data: rebuilding it hashes every file again
          persist.directories = [ "/var/cache/copyparty" ];
        };
    }
  )
