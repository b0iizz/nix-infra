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
}
