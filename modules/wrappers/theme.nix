# Feature: one theme for every wrapper.
#
# `theme` (flake-level option) is the single source: a base16 palette, fonts
# and opacities. Every wrapper starts with a copy as `passthru.theme`, and its
# program module turns that into whatever format the program reads. To restyle
# one wrapper, infuse over its copy like any other setting:
#
#   passthru.theme.opacity.terminal = _: 1.0;
#
#   passthru.theme.colors     base16 "base00".."base0F", 6 hex digits, no `#`
#   passthru.theme.polarity   "dark" | "light"
#   passthru.theme.fonts      { monospace sansSerif serif emoji } -> family name
#   passthru.theme.sizes      { applications desktop popups terminal } -> pt
#   passthru.theme.opacity    { applications desktop popups terminal } -> 0..1
#
# Opacity is for programs that draw their own background; terminal programs
# leave it to their terminal.
#
# `self.lib.theme.hash colors` prefixes every color with `#`.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  options =
    type: defaults:
    lib.mapAttrs (
      _: default:
      mkOption {
        inherit type default;
      }
    ) defaults;
in
{
  options.theme = {
    polarity = mkOption {
      type = types.enum [
        "dark"
        "light"
      ];
      default = "dark";
    };

    # catppuccin-mocha
    colors = options (types.strMatching "[0-9a-fA-F]{6}") {
      base00 = "1e1e2e";
      base01 = "181825";
      base02 = "313244";
      base03 = "45475a";
      base04 = "585b70";
      base05 = "cdd6f4";
      base06 = "f5e0dc";
      base07 = "b4befe";
      base08 = "f38ba8";
      base09 = "fab387";
      base0A = "f9e2af";
      base0B = "a6e3a1";
      base0C = "94e2d5";
      base0D = "89b4fa";
      base0E = "cba6f7";
      base0F = "f2cdcd";
    };

    fonts = options types.str {
      monospace = "DejaVuSansM Nerd Font Mono";
      sansSerif = "DejaVuSansM Nerd Font Mono";
      serif = "DejaVuSansM Nerd Font Mono";
      emoji = "Noto Color Emoji";
    };

    sizes = options types.ints.positive {
      applications = 12;
      desktop = 10;
      popups = 10;
      terminal = 12;
    };

    opacity = options (types.numbers.between 0.0 1.0) {
      applications = 0.9;
      desktop = 0.9;
      popups = 0.9;
      terminal = 0.85;
    };
  };

  config.flake.lib.theme.hash = lib.mapAttrs (_: c: "#${c}");

  config.perSystem.wrapperExtensions = lib.mkOrder 90 [ { passthru.theme = _: config.theme; } ];
}
