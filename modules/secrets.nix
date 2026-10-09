{ withInputs, ... }:
withInputs
  {
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    {
      lib,
      config,
      inputs,
      self,
      ...
    }@top:
    let
      # One token per `<name>-identity.hmac` in secrets/master, with its public
      # key in `<name>.pub` (`fido2-identity.hmac` + `fido2.pub`): add a backup
      # token by dropping in a second pair, then `agenix rekey -a`.
      masterDir = config.registry.secretsDir + "/master";
      masterIdentities = lib.pipe (builtins.readDir masterDir) [
        builtins.attrNames
        (builtins.filter (lib.hasSuffix "-identity.hmac"))
        (map (f: {
          identity = masterDir + "/${f}";
          pubkey = lib.fileContents (masterDir + "/${lib.removeSuffix "-identity.hmac" f}.pub");
        }))
      ];
      identified = lib.filterAttrs (_: host: host.hostkey.publicKeyFile != null) config.registry.hosts;
    in
    {
      imports = [ inputs.agenix-rekey.flakeModule ];

      perSystem =
        { config, ... }:
        {
          agenix-rekey = {
            nixosConfigurations = lib.mapAttrs (name: _: self.nixosConfigurations.${name}) identified;
            collectHomeManagerConfigurations = false;
          };

          make-shells.default = { pkgs, ... }: {
            packages = [
              pkgs.age-plugin-fido2-hmac
              pkgs.rage
              config.agenix-rekey.package
            ];
          };
        };

      flake.modules.nixos.base.imports = [ self.modules.nixos.secrets ];
      flake.modules.nixos.secrets =
        {
          lib,
          config,
          pkgs,
          ...
        }:
        {
          imports = [
            inputs.agenix-rekey.nixosModules.default
            inputs.agenix.nixosModules.default
          ];

          config = lib.mkIf (config.host-context.hostkey.publicKey != null) {
            age.rekey = {
              inherit masterIdentities;

              agePlugins = [ pkgs.age-plugin-fido2-hmac ];

              hostPubkey = config.host-context.hostkey.publicKey;

              storageMode = "local";
              localStorageDir = top.config.registry.secretsDir + "/rekeyed/${config.host-context.hostName}";
              generatedSecretsDir = top.config.registry.secretsDir + "/generated";
            };

            services.openssh = {
              enable = lib.mkDefault true;
              settings = {
                PasswordAuthentication = lib.mkDefault false;
                KbdInteractiveAuthentication = lib.mkDefault false;
                PermitRootLogin = lib.mkDefault "prohibit-password";
              };
              hostKeys = lib.mkForce [
                {
                  path = "/etc/ssh/ssh_host_ed25519_key";
                  type = "ed25519";
                }
              ];
            };

            age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          };
        };

    }
  )
