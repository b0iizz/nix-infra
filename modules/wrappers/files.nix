# Feature: generated config files for every wrapper.
#
#   passthru.files    "rel/path" = content  (see `fileHelpers`/`toFile` in
#                     modules/lib/wrappers.nix for what content can be).
#                     `null` means no file: the names of the files must not
#                     depend on the finished wrapper (only values may, as with
#                     any `overrideAttrs`), so a file that depends on a
#                     setting is `"x" = _: if cond then content else null`.
#   passthru.path     packages added to the wrapped program's PATH
#
# Read-only, for use in other extensions:
#
#   passthru.config.dir     directory holding the files
#   passthru.config.file    "rel/path" -> "<dir>/rel/path"
#   passthru.config.tree    the tree derivation
#
# Example, with the format helpers `h = self.lib.wrappers.fileHelpers pkgs`:
#
#   {
#     passthru.files = {
#       "config.toml" = _: h.toml { layer = "top"; };
#       "style.css" = _: "* { font-family: monospace; }";
#     };
#   }
#   (final: {
#     passthru.wrapper.flags.__append = [
#       "--config" final.passthru.config.file."config.toml"
#     ];
#   })
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  feature = pkgs: [
    {
      passthru = {
        files = _: { };
        path = _: [ ];
      };
    }
    (
      final:
      let
        p = final.passthru;
        files = lib.filterAttrs (_: content: content != null) p.files;
        tree = w.tree pkgs p.wrapperName files;
        dir = "${tree}";
      in
      {
        passthru.config = _: {
          inherit dir tree;
          file = lib.mapAttrs (n: _: "${dir}/${n}") files;
        };

        passthru.wrapper.prefix = lib.optionalAttrs (p.path != [ ]) {
          PATH = _: [ (lib.makeBinPath p.path) ];
        };
      }
    )
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrapperExtensions = lib.mkOrder 100 (feature pkgs);
    };
}
