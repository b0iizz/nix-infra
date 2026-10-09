# What every desktop session needs, whichever compositor and shell it has.
# Imported by the quickshell role. Everything is `mkDefault`, hosts override.
#
# GTK programs (LibreWolf, Evince, LibreOffice) take light or dark from the
# portal, which reads it from dconf; Adwaita has both, and its cursors are the
# compositor's and the programs' `default`.
{ self, lib, ... }@flake:
let
  dark = flake.config.theme.polarity == "dark";
in
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
        # icons and the cursors of `xdg.icons.fallbackCursorThemes`
        adwaita-icon-theme
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

      programs.dconf.enable = true;
      programs.dconf.profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            color-scheme = if dark then "prefer-dark" else "prefer-light";
            gtk-theme = if dark then "Adwaita-dark" else "Adwaita";
            cursor-theme = "Adwaita";
          };
        }
      ];
      xdg.icons.fallbackCursorThemes = lib.mkDefault [ "Adwaita" ];
    };
}
