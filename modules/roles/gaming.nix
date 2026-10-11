# Steam, with the firewall ports its features need, and Prism Launcher for
# Minecraft (modules/wrappers/prismlauncher). Steam is unfree, so the role
# allows unfree packages (a host can still turn that off).
{ self, lib, ... }:
{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      imports = [ self.modules.nixos.persist ];

      nixpkgs.config.allowUnfree = lib.mkDefault true;

      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        package = pkgs.steam.override (prev: {
          extraArgs = (prev.extraArgs or "") + " -system-composer";
        });
      };

      environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.prismlauncher ];

      persist.home.directories = [
        ".steam"
        ".local/share/Steam"
      ];
    };
}
