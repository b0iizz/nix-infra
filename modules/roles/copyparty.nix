# NAS file server for a host with a data disk: github:9001/copyparty serving
# folders of the disk, published through the publicProxy gateways
# (modules/public-proxy/).
#
#   roles = [ "disko-root-impermanence" "disko-raid" "copyparty" ];
#
# Out of the box: /data at `/`, readable by everyone, and the account `admin`
# may also upload, move and delete. Logins and folders are options of the
# host:
#
#   copyparty.accounts = [ "admin" "alice" ];
#   copyparty.volumes."/private" = {
#     path = "/data/private";
#     access.rwmd = [ "alice" ];   # permission letters -> "*" or account names
#   };
#   copyparty.volumes."/" = { ... };   # replaces the default
#
# A volume at a deeper URL takes over that folder from its parent: its
# access list is the only one that counts there. Permission letters, flags:
# `copyparty --help-flags`, or the options of `services.copyparty.volumes`.
#
# Each account's password is generated with agenix-rekey (`agenix generate`,
# then `agenix rekey -a`); read it with `agenix edit` on
# `copyparty-<host>-<account>`.
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
          inherit (lib) mkOption types;
          cfg = config.copyparty;
          svc = config.services.copyparty;
          port = 3923;
          secretOf = name: "copyparty-${config.host-context.hostName}-${name}";
        in
        {
          imports = [
            inputs.copyparty.nixosModules.default
            self.modules.nixos.persist
          ];

          options.copyparty = {
            accounts = mkOption {
              type = types.listOf types.str;
              default = [ "admin" ];
              description = "Logins. Each gets a generated password.";
            };

            volumes = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    path = mkOption {
                      type = types.str;
                      example = "/data/photos";
                      description = "Folder on the host.";
                    };
                    access = mkOption {
                      type = types.attrsOf (types.either types.str (types.listOf types.str));
                      default = { };
                      example = {
                        r = "*";
                        rwmd = [ "alice" ];
                      };
                      description = ''
                        Permission letters (r read, w write, m move, d delete,
                        g get, a admin; see `services.copyparty.volumes`) to
                        `"*"` (everyone) or a list of accounts.
                      '';
                    };
                    flags = mkOption {
                      type = types.attrs;
                      default = { };
                      description = "Volume flags, e.g. `{ fk = 4; }`; `copyparty --help-flags`.";
                    };
                  };
                }
              );
              default = { };
              description = "Folders served, by URL path. `/` defaults to /data, see the top.";
            };
          };

          config = {
            # a default per URL, not of the option, so that adding a folder
            # does not drop `/`
            copyparty.volumes."/" = lib.mkDefault {
              path = "/data";
              access = {
                r = "*";
                rwmd = [ "admin" ];
              };
            };

            assertions = lib.concatLists (
              lib.mapAttrsToList (
                url: v:
                lib.mapAttrsToList (perm: who: {
                  assertion = lib.all (a: a == "*" || lib.elem a cfg.accounts) (lib.toList who);
                  message = "copyparty: volume ${url} grants `${perm}` to an account missing from `copyparty.accounts`";
                }) v.access
              ) cfg.volumes
            );

            age.secrets = lib.genAttrs (map secretOf cfg.accounts) (_: {
              owner = svc.user;
              generator = {
                script = "alnum";
                tags = [ "password" ];
              };
            });

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
              accounts = lib.genAttrs cfg.accounts (name: {
                passwordFile = config.age.secrets.${secretOf name}.path;
              });
              volumes = lib.mapAttrs (_: v: { inherit (v) path access flags; }) cfg.volumes;
            };

            # the module only creates a missing volume path, it does not take
            # over one that exists (a mount point)
            systemd.tmpfiles.rules = lib.mapAttrsToList (
              _: v: "z ${v.path} - ${svc.user} ${svc.group}"
            ) cfg.volumes;

            publicProxy.expose.copyparty = {
              subdomain = lib.mkDefault "files";
              inherit port;
              maxBodySize = lib.mkDefault "0"; # uploads of any size
            };

            # the index of the volumes: rebuilding it hashes every file again
            persist.directories = [ "/var/cache/copyparty" ];
          };
        };
    }
  )
