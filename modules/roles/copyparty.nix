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
#   copyparty.groups.family = [ "alice" "bob" ];   # grant to "@family"
#   copyparty.homes = "/data/homes";   # /home/<account>, for its owner only
#   copyparty.usernames = true;        # log in with name and password
#
# A volume at a deeper URL takes over that folder from its parent: its
# access list is the only one that counts there. Permission letters, flags:
# `copyparty --help-flags`, or the options of `services.copyparty.volumes`.
# Messages to the server log (the 📟 box) are off for everyone.
#
# Each account's password is generated with agenix-rekey (`agenix generate`,
# then `agenix rekey -a`); read it with `agenix edit` on
# `copyparty-<host>-<account>`.
#
# The host also has to be in `publicProxy.origins`, and the flake needs a
# zone and a gateway (see modules/public-proxy/module.nix). The address is
# `files.<defaultZone>`; change it with `publicProxy.expose.copyparty`.
#
# The look is copyparty's flat light theme, restyled by the stylesheet in
# copyparty-head.html (appended to every page, with the font inlined). Its
# one accent colour is `copyparty.accent.light` and `.dark`. The name in the
# page titles is the host's: `services.copyparty.settings.bname` and
# `doctitle`.
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
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (lib) mkOption types;
          cfg = config.copyparty;
          svc = config.services.copyparty;
          port = 3923;
          secretOf = name: "copyparty-${config.host-context.hostName}-${name}";
          # it ends up in the stylesheet
          hexColour = types.strMatching "#[0-9a-fA-F]{6}";
          # who an access list may name
          grantee =
            a:
            a == "*"
            || lib.elem a cfg.accounts
            || lib.elem a (map (g: "@${g}") (lib.attrNames cfg.groups ++ [ "acct" ]));

          # copyparty-head.html after the font (Atkinson Hyperlegible Next, a
          # Latin woff2 subset inlined so visitors fetch nothing elsewhere)
          # and the accent colours
          head =
            pkgs.runCommand "copyparty-head.html"
              {
                nativeBuildInputs = [
                  pkgs.python3Packages.fonttools
                  pkgs.python3Packages.brotli
                ];
              }
              ''
                pyftsubset '${pkgs.atkinson-hyperlegible-next}/share/fonts/truetype/AtkinsonHyperlegibleNext[wght].ttf' \
                  --unicodes='U+0000-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122,U+2190-2193,U+2212' \
                  --layout-features='kern,liga,tnum,lnum' --flavor=woff2 --output-file=font.woff2
                {
                  echo "<style>@font-face{font-family:'Atkinson Hyperlegible Next';font-weight:200 800;font-display:swap;src:url(data:font/woff2;base64,$(base64 -w0 font.woff2)) format('woff2')}"
                  echo ":root{--accent-light:${cfg.accent.light};--accent-dark:${cfg.accent.dark}}</style>"
                  cat ${./copyparty-head.html}
                } > $out
              '';
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

            groups = mkOption {
              type = types.attrsOf (types.listOf types.str);
              default = { };
              example = {
                family = [
                  "alice"
                  "bob"
                ];
              };
              description = ''
                Groups of accounts, granted access as `"@<name>"`. `"@acct"`
                is copyparty's own group of all accounts.
              '';
            };

            homes = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "/data/homes";
              description = ''
                Gives each account a private folder at `/home/<account>`,
                kept in `<homes>/<account>`. Null: no home folders. Keep it
                outside the other volumes' paths, or their readers see the
                homes too.
              '';
            };

            usernames = lib.mkEnableOption "login with account name and password, instead of the password alone";

            accent = {
              light = mkOption {
                type = hexColour;
                default = "#9a4419";
                description = "Accent of the light theme: selected folder and rows, open panel, focus.";
              };
              dark = mkOption {
                type = hexColour;
                default = "#e0895a";
                description = "The same on the dark theme, lighter to read on the dark ground.";
              };
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

            assertions =
              lib.concatLists (
                lib.mapAttrsToList (
                  url: v:
                  lib.mapAttrsToList (perm: who: {
                    assertion = lib.all grantee (lib.toList who);
                    message = "copyparty: volume ${url} grants `${perm}` to an account missing from `copyparty.accounts` or a group missing from `copyparty.groups`";
                  }) v.access
                ) cfg.volumes
              )
              ++ lib.mapAttrsToList (g: members: {
                assertion = lib.all (a: lib.elem a cfg.accounts) members;
                message = "copyparty: group ${g} lists an account missing from `copyparty.accounts`";
              }) cfg.groups;

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
                # the look: flat light, restyled by copyparty-head.html; a
                # visitor's own theme pick (in their browser) still wins
                theme = 3;
                html-head = "@${head}";
                favico = "▤ ${lib.removePrefix "#" cfg.accent.light} none";
                spinner = "◌";
                # anyone, logged in or not, could write messages into the
                # journal (the 📟 box, ?smsg): read the form as a GET instead
                urlform = "get";
                smsg = "";
              }
              // lib.optionalAttrs cfg.usernames { usernames = true; };
              accounts = lib.genAttrs cfg.accounts (name: {
                passwordFile = config.age.secrets.${secretOf name}.path;
              });
              inherit (cfg) groups;
              volumes =
                lib.mapAttrs (_: v: { inherit (v) path access flags; }) cfg.volumes
                // lib.optionalAttrs (cfg.homes != null) {
                  # copyparty makes one per account, and the folder on first use
                  "/home/\${u}" = {
                    path = "${cfg.homes}/\${u}";
                    access.rwmd = "\${u}";
                  };
                };
            };

            # the module binds only volume paths without a ${u} into the
            # service's sandbox
            systemd.services.copyparty.serviceConfig.BindPaths = lib.optional (cfg.homes != null) cfg.homes;

            # the module only creates a missing volume path, it does not take
            # over one that exists (a mount point)
            systemd.tmpfiles.rules =
              lib.mapAttrsToList (_: v: "z ${v.path} - ${svc.user} ${svc.group}") cfg.volumes
              ++ lib.optional (cfg.homes != null) "d ${cfg.homes} 0750 ${svc.user} ${svc.group}";

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
