{
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.flake-file.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  flake-file = {
    description = "My NixOS configurations";

    inputs = {
      flake-parts.url = "github:hercules-ci/flake-parts";
      import-tree.url = "github:vic/import-tree";
      flake-file.url = "github:vic/flake-file";

      nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    outputs = ''
      inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (
        inputs.import-tree [ ./modules ]
      )
    '';
  };

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  registry = {
    defaultSystem = "x86_64-linux";
    adminKeys = [
      # "ssh-ed25519 AAAA... you@workstation"
    ];
  };

  registry.users.joni = {
    description = "Jonathan";
    uid = 1000;
    admin = true;
    # Keys in `registry.adminKeys` are added automatically for admins.
    sshKeys = [ ];
    # Groups for all users of a role are in `registry.userPolicy.roleGroups`.
    extraGroups = [ ];
  };

  # Root: key-only over SSH (see secrets module), generated password for the
  # console. Accounts are fully declarative, passwords can't be changed ad hoc.
  registry.rootUser = {
    password = "generated";
    sshKeys = [ ];
  };

  registry.userPolicy = {
    mutableUsers = false;
    sudoNeedsPassword = true;
    perHostPasswords = true;
    # Added to all users of hosts with that role.
    roleGroups.desktop = [
      "networkmanager"
      "audio"
      "video"
      "dialout"
    ];
  };
}
