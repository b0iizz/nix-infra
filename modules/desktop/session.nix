# What every desktop session needs, whichever compositor and shell it has.
# Imported by the quickshell role. Everything is `mkDefault`, hosts override.
# How GTK and Qt programs look is modules/desktop/theme.nix.
{ self, lib, ... }:
{
  flake.modules.nixos.desktop-session =
    { pkgs, ... }:
    {
      # imported by the quickshell and the greeter role, so its lists once
      key = "modules/desktop/session.nix";

      imports = [ self.modules.nixos.persist ];

      # volumes and default devices, or they reset on every boot
      persist.home.directories = [ ".local/state/wireplumber" ];

      # the compositor's key binds call wpctl, brightnessctl and playerctl
      environment.systemPackages = with pkgs; [
        brightnessctl
        playerctl
        wireplumber
        # icons, and the cursors of `xdg.icons.fallbackCursorThemes` (the greeter's too)
        adwaita-icon-theme
      ];

      services.udev.packages = [ pkgs.brightnessctl ];
      xdg.icons.fallbackCursorThemes = lib.mkDefault [ "Adwaita" ];

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
