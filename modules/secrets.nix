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
              masterIdentities = [
                {
                  identity = top.config.registry.secretsDir + "/master/fido2.age-identity";
                  pubkey = lib.fileContents (top.config.registry.secretsDir + "/master/fido2.pub");
                }
              ];

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
