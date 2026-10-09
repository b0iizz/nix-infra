# A development machine: git (wrapped), Claude Code, programs built for other distros
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

      # the wrapper (modules/wrappers/git): defaults, and ~/.config/git kept
      programs.git = {
        enable = true;
        package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.git;
      };
      programs.nix-ld.enable = true;
      environment.systemPackages = [ pkgs.claude-code ];

      # ~/.claude.json would be a bind-mounted file, which Claude Code can't
      # replace when it saves; inside its config directory it is kept as is
      environment.variables.CLAUDE_CONFIG_DIR = "$HOME/.claude";
      persist.home.directories = [ ".claude" ];
    };
}
