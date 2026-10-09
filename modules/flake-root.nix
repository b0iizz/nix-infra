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
    description = "Declarative NixOS fleet: hosts, disk layouts, secrets, provisioning and deployment";

    inputs = {
      flake-parts.url = "github:hercules-ci/flake-parts";
      import-tree.url = "github:vic/import-tree";
      flake-file.url = "github:vic/flake-file";

      nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    outputs = ''
      inputs: inputs.flake-parts.lib.mkFlake {
        inherit inputs;
        specialArgs.withInputs = import ./with-inputs.nix inputs;
      } (
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYJZQipCKx0rDKEYI6r+0MpUZKSVHZRafrOAF6dVP8J prometheus:joni-ssh-ed25519"
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
    roleGroups.workstation = [
      "networkmanager"
      "audio"
      "video"
      "dialout"
    ];
  };
}
