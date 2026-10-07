{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    importJSON
    fileContents
    ;
  rcfg = config.registry;

  hostSubmodule = types.submodule (
    { name, config, ... }:
    {
      options = {

        enable = mkEnableOption "this host" // {
          default = true;
        };

        path = mkOption {
          type = types.path;
          description = ''
            Directory holding this hosts out-of-band state: The facter
            report, the public host key, host-local definitions. Should
            always be `./.` from wherever this option is defined.
          '';
        };

        hostName = mkOption {
          type = types.str;
          default = name;
        };

        system = mkOption {
          type = types.raw;
          default = rcfg.defaultSystem;
        };

        stateVersion = mkOption {
          type = types.str;
          default = lib.trivial.release;
        };

        roles = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "server" ];
          description = ''
            Names resolved against `flake.modules.nixos.<name>`
          '';
        };

        modules = mkOption {
          type = types.listOf types.deferredModule;
          default = [ ];
          description = "Host specific NixOS modules";
        };

        facter = {

          reportPath = mkOption {
            type = types.nullOr types.path;
            default =
              if builtins.pathExists (config.path + "/facter.json") then config.path + "/facter.json" else null;
          };

          report = mkOption {
            type = types.nullOr types.raw;
            default = if config.facter.reportPath != null then (importJSON config.facter.reportPath) else null;
          };

          detected = mkOption {
            type = types.bool;
            readOnly = true;
            default = config.facter.report != null;
          };

        };

        hostkey = {

          publicKeyFile = mkOption {
            type = types.nullOr types.path;
            default =
              if builtins.pathExists (config.path + "/host.pub") then config.path + "/host.pub" else null;
          };

          publicKey = mkOption {
            type = types.nullOr types.str;
            default =
              if config.hostkey.publicKeyFile != null then fileContents config.hostkey.publicKeyFile else null;
          };

          privateKeyFile = mkOption {
            type = types.path;
            default = rcfg.hostKeysDir + "/${name}.age";
          };

        };

        deploy = {

          groups = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };

          targetHost = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Hostname or address reachable over SSH from the operator.

              `null` means this host is only ever deployed from itself:
              In that case `deploy` runs `nixos-rebuild` locally with no
              `--target-host`.
            '';
          };

          targetUser = mkOption {
            type = types.str;
            default = "root";
            description = ''
              SSH user. Anything other than `root` makes `deploy` pass
              `nixos-rebuild` it's remote sudo flag.
            '';
          };

          sshOpts = mkOption {
            type = types.listOf types.str;
            default = rcfg.defaultSshOpts;
          };

          buildOnTarget = mkOption {
            type = types.bool;
            default = false;
          };

        };

        provision = {

          method = mkOption {
            type = types.enum [
              "remote"
              "local"
            ];
            default = "remote";
          };

          kexec = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Try to boot every machine into an installer that isn't
              already in one using kexec.
            '';
          };

          targetHost = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Hostname or address reachable over SSH from the operator
              during installation.
            '';
          };

          targetUser = mkOption {
            type = types.str;
            default = "root";
          };

        };

      };
    }
  );
in
{

  options.registry = {

    defaultSystem = mkOption {
      type = types.raw;
      default = "x86_64-linux";
    };

    defaultSshOpts = mkOption {
      type = types.listOf types.str;
      default = [
        "-o"
        "ControlMaster=auto"
        "-o"
        "ControlPersist=60"
      ];
    };

    adminKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        SSH public keys which grant access to almost any host.
        They are also baked into the kexec installer.
      '';
    };

    secretsDir = mkOption {
      type = types.path;
      default = self + "/secrets";
      description = "Directory containing all commited cyphertext.";
    };

    hostKeysDir = mkOption {
      type = types.path;
      default = rcfg.secretsDir + "/host-keys";
    };

    hosts = mkOption {
      type = types.attrsOf hostSubmodule;
      default = { };
    };

  };

}
