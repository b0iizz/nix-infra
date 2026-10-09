# A development machine: git, programs built for other distros (nix-ld) and the
# place the code lives. Editors and toolchains come from per-project shells.
{ self, ... }:
{
  flake.modules.nixos.programming = {
    imports = [ self.modules.nixos.persist ];

    programs.git.enable = true;
    programs.nix-ld.enable = true;

    persist.home.directories = [ "Projects" ];
  };
}
