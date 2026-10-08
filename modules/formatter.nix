{ withInputs, ... }:
withInputs
  {
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    {
      inputs,
      ...
    }:
    {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { pkgs, ... }:
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              prettier.enable = true;
              shfmt.enable = true;
              taplo.enable = true;
              nixfmt = {
                enable = pkgs.lib.meta.availableOn pkgs.stdenv.buildPlatform pkgs.nixfmt.compiler;
                package = pkgs.nixfmt;
              };
            };
            settings = {
              formatter.qmlformat = {
                command = "${pkgs.kdePackages.qtdeclarative}/bin/qmlformat";
                options = [ "-i" ];
                includes = [ "*.qml" ];
              };
              on-unmatched = "fatal";
              global.excludes = [
                "*.jpg"
                "*.png"
                "LICENSE"
                "*.pub"
                "*.age"
                "**/.gitkeep"
                "*.age-identity"
              ];
            };
          };
        };
    }
  )
