# What every desktop session needs, whichever compositor and shell it has.
# Imported by the quickshell role. Everything is `mkDefault`, hosts override.
{ lib, ... }:
{
  flake.modules.nixos.desktop-session =
    { pkgs, ... }:
    {
      # the compositor's key binds call wpctl, brightnessctl and playerctl
      environment.systemPackages = with pkgs; [
        brightnessctl
        playerctl
        wireplumber
      ];

      services.udev.packages = [ pkgs.brightnessctl ];

      security.polkit.enable = lib.mkDefault true;
      security.rtkit.enable = lib.mkDefault true;
      services.pipewire = {
        enable = lib.mkDefault true;
        alsa.enable = lib.mkDefault true;
        pulse.enable = lib.mkDefault true;
      };

      # the families of the default theme (modules/wrappers/theme.nix)
      fonts.packages = with pkgs; [
        nerd-fonts.dejavu-sans-mono
        noto-fonts-color-emoji
      ];
    };
}
