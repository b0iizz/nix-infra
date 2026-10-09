# A development machine: git, Claude Code, programs built for other distros
# (nix-ld). Editors and toolchains come from per-project shells; ~/Projects
# exists on every host (modules/users.nix). Claude Code is unfree, so the role allows unfree
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
        directories = [ ".claude" ];
        files = [ ".claude.json" ];
      };
    };
}
