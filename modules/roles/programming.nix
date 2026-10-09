# A development machine: git, Claude Code, programs built for other distros
# (nix-ld) and the place the code lives. Editors and toolchains come from
# per-project shells. Claude Code is unfree, so the role allows unfree
# packages (a host can still turn that off).
{ self, lib, ... }:
{
  flake.modules.nixos.programming =
    { pkgs, ... }:
    {
      imports = [ self.modules.nixos.persist ];

      nixpkgs.config.allowUnfree = lib.mkDefault true;

      programs.git.enable = true;
      programs.nix-ld.enable = true;
      environment.systemPackages = [ pkgs.claude-code ];

      persist.home = {
        directories = [
          "Projects"
          ".claude"
        ];
        files = [ ".claude.json" ];
      };
    };
}
