{ inputs, ... }:
{
  imports = [ inputs.make-shell.flakeModules.default ];

  flake-file.inputs = {
    make-shell.url = "github:/nicknovitski/make-shell";
  };

  perSystem.make-shells.default = { pkgs, ... }: {
    packages = with pkgs; [
      git
      jq
      curl
      wget
    ];
  };
}
