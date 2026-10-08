# `perSystem.wrappers.<name>`: an ordered list of extensions (see
# modules/lib/wrappers.nix) applied to a base wrapper derivation, exposed as
# `packages.<name>`.
#
# Several modules may extend the same wrapper. Lists are concatenated, so use
# `self.lib.wrappers.program` (mkOrder 100) for a program's own definition and
# `lib.mkAfter` for overrides that must come last.
#
# `perSystem.wrapperExtensions` is one more list, applied to *every* wrapper
# before its own extensions. It carries the features that give wrappers their
# helper settings (`passthru.files`, `passthru.path`, see files.nix),
# each contributing at its own `mkOrder`; add your own the
# same way. Because they run first, a wrapper can override anything they set.
# Extensions can read `final.passthru.wrapperName`; derive from other settings
# with the `final:` form, which sees the finished wrapper wherever it sits.
{
  self,
  lib,
  flake-parts-lib,
  ...
}:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.wrappers = lib.mkOption {
      type = lib.types.lazyAttrsOf (lib.types.listOf lib.types.raw);
      default = { };
      description = "Wrapper name to ordered list of extensions.";
    };

    options.wrapperExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
      description = "Extensions applied to every wrapper before its own.";
    };
  };

  config.perSystem =
    { config, pkgs, ... }:
    {
      packages = lib.mapAttrs (
        name: exts:
        self.lib.wrappers.mkWrapper pkgs name [
          config.wrapperExtensions
          exts
        ]
      ) config.wrappers;
    };
}
