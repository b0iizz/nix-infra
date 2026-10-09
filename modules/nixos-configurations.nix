{
  lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib)
    attrNames
    attrValues
    getAttrs
    subtractLists
    ;

  resolveRoles =
    host:
    let
      modules = config.flake.modules.nixos or { };
      available = attrNames modules;
      missing = subtractLists available host.roles;
    in
    lib.throwIf (missing != [ ])
      "host '${host.hostName}': unknown role(s) ${toString missing}; available are ${toString available}"
      (attrValues (getAttrs host.roles modules));

  contextModule = host: {
    options.host-context = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
    };

    config = {
      _module.args = lib.mapAttrs (_: f: f host) config.registry.extraHostArgs;
      host-context = host;
      networking.hostName = host.hostName;
      nixpkgs.hostPlatform = host.system;
      system.stateVersion = host.stateVersion;
      hardware.facter.reportPath = lib.mkIf (host.facter.reportPath != null) host.facter.reportPath;
      users.users.root.openssh.authorizedKeys.keys = config.registry.rootKeys;
      assertions = [
        {
          assertion = config.registry.rootKeys != [ ];
          message = "no key can log in as root: set `registry.adminKeys` or generate an admin's key (`agenix generate`)";
        }
      ];
    };
  };

  collectHostModules =
    host:
    [
      (contextModule host)
      (config.flake.modules.nixos.base or { })
    ]
    ++ (resolveRoles host)
    ++ host.modules;
in
{
  options.registry.extraHostArgs = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.coercedTo lib.types.raw lib.toFunction (lib.types.functionTo lib.types.raw)
    );
    default = { };
  };

  config.flake.nixosConfigurations = lib.mapAttrs (
    _name: host:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs self; };
      modules = collectHostModules host;
    }
  ) config.registry.hosts;
}
