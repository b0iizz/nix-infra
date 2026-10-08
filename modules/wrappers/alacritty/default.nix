# Alacritty (the sixel fork, which spotify-player's cover art needs), wrapped:
# alacritty.toml is rendered from `passthru.theme` (see theme.nix) with
# `passthru.settings` merged on top, and handed over with `--config-file`.
#
#   settings   alacritty.toml options, deep-merged over the themed defaults
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  program = pkgs: [
    (w.withPackage pkgs.alacritty-graphics)
    { passthru.settings = _: { }; }
    (
      final:
      let
        t = final.passthru.theme;
        c = self.lib.theme.hash t.colors;

        themed = {
          colors = {
            primary = {
              foreground = c.base05;
              background = c.base00;
              bright_foreground = c.base07;
            };
            selection = {
              text = c.base05;
              background = c.base02;
            };
            cursor = {
              text = c.base00;
              cursor = c.base05;
            };
            normal = {
              black = c.base00;
              red = c.base08;
              green = c.base0B;
              yellow = c.base0A;
              blue = c.base0D;
              magenta = c.base0E;
              cyan = c.base0C;
              white = c.base05;
            };
            bright = {
              black = c.base03;
              red = c.base08;
              green = c.base0B;
              yellow = c.base0A;
              blue = c.base0D;
              magenta = c.base0E;
              cyan = c.base0C;
              white = c.base07;
            };
          };
          font = {
            normal = {
              family = t.fonts.monospace;
              style = "Regular";
            };
            size = t.sizes.terminal;
          };
          window.opacity = t.opacity.terminal;
        };
      in
      {
        passthru.files."alacritty.toml" =
          _: (w.fileHelpers pkgs).toml (lib.recursiveUpdate themed final.passthru.settings);

        passthru.wrapper.flags.__append = [
          "--config-file ${final.passthru.config.file."alacritty.toml"}"
        ];
      }
    )
  ];
in
{
  perSystem =
    { config, pkgs, ... }:
    {
      wrappers.alacritty = w.program (program pkgs);

      desktop.launcher.entries.alacritty = {
        name = "Terminal";
        exec = [ (lib.getExe config.packages.alacritty) ];
      };
    };

  # Opt-in per host (`roles = [ "alacritty" ]`), not part of `base`.
  flake.modules.nixos.alacritty =
    { pkgs, ... }:
    w.collect [ self.packages.${pkgs.stdenv.hostPlatform.system}.alacritty ];
}
