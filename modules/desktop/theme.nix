# GTK and Qt programs in the colors and fonts of `theme`
# (modules/wrappers/theme.nix), the palette of the wrapped programs and the
# shell. Imported by the quickshell role.
#
# GTK 3 programs use the adw-gtk3 theme, GTK 4 ones libadwaita's own
# stylesheet; both are drawn from named colors that ~/.config/gtk-3.0/gtk.css
# and gtk-4.0/gtk.css redefine. Qt programs take the palette from qt5ct and
# qt6ct, with the Fusion style. Light or dark reaches the programs through
# dconf and the portal; LibreWolf's toolbar follows it.
#
# The files in the home are links into the store that systemd-tmpfiles makes
# at every login (impermanence wipes the home at boot); they replace what was
# there, so changes made in the programs' settings don't last.
{ lib, ... }@flake:
let
  t = flake.config.theme;
  dark = t.polarity == "dark";
  hex = base: "#${t.colors.${base}}";

  # adw-gtk3 and libadwaita read the same names
  gtkCss = builtins.toFile "gtk.css" (
    lib.concatStrings (
      lib.mapAttrsToList (name: base: "@define-color ${name} ${hex base};\n") {
        accent_color = "base0D";
        accent_bg_color = "base0D";
        accent_fg_color = "base00";
        destructive_color = "base08";
        destructive_bg_color = "base08";
        destructive_fg_color = "base00";
        success_color = "base0B";
        success_bg_color = "base0B";
        success_fg_color = "base00";
        warning_color = "base0A";
        warning_bg_color = "base0A";
        warning_fg_color = "base00";
        error_color = "base08";
        error_bg_color = "base08";
        error_fg_color = "base00";
        window_bg_color = "base00";
        window_fg_color = "base05";
        view_bg_color = "base00";
        view_fg_color = "base05";
        headerbar_bg_color = "base01";
        headerbar_fg_color = "base05";
        headerbar_backdrop_color = "base01";
        sidebar_bg_color = "base01";
        sidebar_fg_color = "base05";
        sidebar_backdrop_color = "base01";
        secondary_sidebar_bg_color = "base01";
        secondary_sidebar_fg_color = "base05";
        secondary_sidebar_backdrop_color = "base01";
        card_bg_color = "base01";
        card_fg_color = "base05";
        dialog_bg_color = "base01";
        dialog_fg_color = "base05";
        popover_bg_color = "base01";
        popover_fg_color = "base05";
        thumbnail_bg_color = "base01";
        thumbnail_fg_color = "base05";
      }
    )
  );

  # a qt5ct/qt6ct color scheme: the QPalette roles in their order, WindowText
  # to PlaceholderText; disabled text is dimmed
  qtColors =
    let
      roles = [
        "base05" # WindowText
        "base01" # Button
        "base03" # Light
        "base02" # Midlight
        "base00" # Dark
        "base01" # Mid
        "base05" # Text
        "base07" # BrightText
        "base05" # ButtonText
        "base00" # Base
        "base00" # Window
        "base01" # Shadow
        "base0D" # Highlight
        "base00" # HighlightedText
        "base0D" # Link
        "base0E" # LinkVisited
        "base01" # AlternateBase
        "base00" # NoRole
        "base01" # ToolTipBase
        "base05" # ToolTipText
        "base04" # PlaceholderText
      ];
      text = [
        0
        6
        8
      ];
      line =
        disabled:
        lib.concatStringsSep ", " (
          lib.imap0 (
            i: base: "#ff${t.colors.${if disabled && lib.elem i text then "base04" else base}}"
          ) roles
        );
    in
    builtins.toFile "colors.conf" ''
      [ColorScheme]
      active_colors=${line false}
      inactive_colors=${line false}
      disabled_colors=${line true}
    '';

  qtConf = builtins.toFile "qtct.conf" ''
    [Appearance]
    color_scheme_path=${qtColors}
    custom_palette=true
    icon_theme=Adwaita
    standard_dialogs=xdgdesktopportal
    style=Fusion

    [Fonts]
    fixed="${t.fonts.monospace},${toString t.sizes.applications}"
    general="${t.fonts.sansSerif},${toString t.sizes.applications}"
  '';
in
{
  flake.modules.nixos.desktop-theme =
    { pkgs, ... }:
    {
      key = "modules/desktop/theme.nix";

      programs.dconf.enable = true;
      programs.dconf.profiles.user.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            color-scheme = if dark then "prefer-dark" else "prefer-light";
            gtk-theme = if dark then "adw-gtk3-dark" else "adw-gtk3";
            icon-theme = "Adwaita";
            cursor-theme = "Adwaita";
            font-name = "${t.fonts.sansSerif} ${toString t.sizes.applications}";
            monospace-font-name = "${t.fonts.monospace} ${toString t.sizes.applications}";
          };
        }
      ];

      # qt5ct also installs qt6ct
      qt.enable = true;
      qt.platformTheme = "qt5ct";

      # `-`: the greeter's user manager has no home to write to, and must not
      # fail for it. Per-user rules would go through `users.users` and recurse.
      systemd.user.tmpfiles.rules = [
        "L+- %h/.config/gtk-3.0/gtk.css - - - - ${gtkCss}"
        "L+- %h/.config/gtk-4.0/gtk.css - - - - ${gtkCss}"
        "L+- %h/.config/qt5ct/qt5ct.conf - - - - ${qtConf}"
        "L+- %h/.config/qt6ct/qt6ct.conf - - - - ${qtConf}"
      ];

      environment.systemPackages = [ pkgs.adw-gtk3 ];
    };
}
