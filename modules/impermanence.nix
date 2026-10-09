# What survives a reboot on a host with `disko-root-impermanence`, using
# github:nix-community/preservation. That layout imports this module; hosts
# on other layouts never see it.
#
# Besides /etc/machine-id (journald's logs in /var/log are keyed by it), it
# keeps what roles and the host declare in `persist.*` (modules/persist.nix)
# and the home-relative paths wrappers ask for, for every normal user: each
# package in `environment.systemPackages` or the user's `packages` may carry
# `passthru.persist.{directories,files}` (see modules/wrappers/persist.nix).
#
#   persist.directories = [ "/var/lib/foo" ];
#   persist.home.directories = [ "Documents" ];
{ withInputs, ... }:
withInputs { preservation.url = "github:nix-community/preservation"; } (
  { inputs, ... }:
  {
    flake.modules.nixos.impermanence =
      { config, lib, ... }:
      let
        asked = key: pkgs: lib.unique (lib.concatMap (p: p.passthru.persist.${key} or [ ]) pkgs);
      in
      {
        imports = [ inputs.preservation.nixosModules.default ];

        preservation = {
          enable = true;
          preserveAt.${config.disko-layouts.impermanence.persistDir} = {
            directories = config.persist.directories;
            files = [
              {
                file = "/etc/machine-id";
                inInitrd = true;
              }
            ]
            ++ config.persist.files;
            users = lib.mapAttrs (
              _: u:
              let
                pkgs = config.environment.systemPackages ++ u.packages;
              in
              {
                directories = lib.unique (asked "directories" pkgs ++ config.persist.home.directories);
                files = lib.unique (asked "files" pkgs ++ config.persist.home.files);
              }
            ) (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);
          };
        };

        # nothing to commit: the id lives on /persist
        systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
      };
  }
)
