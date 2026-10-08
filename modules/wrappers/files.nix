# Feature: generated config files for every wrapper.
#
#   passthru.files    "rel/path" = content  (see `fileHelpers`/`toFile` in
#                     modules/lib/wrappers.nix for what content can be).
#                     `null` means no file: the names of the files must not
#                     depend on the finished wrapper (only values may, as with
#                     any `overrideAttrs`), so a file that depends on a
#                     setting is `"x" = _: if cond then content else null`.
#   passthru.path     packages added to the wrapped program's PATH
#   passthru.live     point the wrapper at a stable symlink under `liveRoot`
#                     instead of the store path, so the config can change under
#                     a running program (the symlink is maintained by the
#                     `activation` feature; `reload` implies `live`)
#   passthru.liveRoot where those symlinks live, default /run/wrapped
#
# Read-only, for use in other extensions:
#
#   passthru.config.dir     directory holding the files (live path if `live`)
#   passthru.config.file    "rel/path" -> "<dir>/rel/path"
#   passthru.config.store   the store path of the tree, whatever `live` is
#   passthru.config.tree    the tree derivation
#
# Example, with the format helpers `h = self.lib.wrappers.fileHelpers pkgs`:
#
#   (w.withFiles {
#     "config.jsonc" = h.json { layer = "top"; };
#     "style.css" = "* { font-family: monospace; }";
#   })
#   (final: {
#     passthru.wrapper.flags.__append = [
#       "--config" final.passthru.config.file."config.jsonc"
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
        live = _: false;
        liveRoot = _: "/run/wrapped";
      };
    }
    (
      final:
      let
        p = final.passthru;
        name = p.wrapperName;
        files = lib.filterAttrs (_: content: content != null) p.files;
        tree = w.tree pkgs name files;
        liveDir = "${p.liveRoot}/${name}";
        dir = if p.live then liveDir else "${tree}";

        # Keeps the tree in the wrapper's closure even when `live` makes
        # nothing else reference it.
        stampVar = "_WRAPPED_" + lib.toUpper (builtins.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name);
      in
      {
        passthru.config = _: {
          inherit name dir tree;
          store = "${tree}";
          file = lib.mapAttrs (n: _: "${dir}/${n}") files;
        };

        passthru.wrapper = {
          envDefault = lib.optionalAttrs (files != { }) {
            ${stampVar} = _: "${tree}";
          };
          prefix = lib.optionalAttrs (p.path != [ ]) {
            PATH = _: [ (lib.makeBinPath p.path) ];
          };
          # compiled wrappers cannot `--run`, so they go without the guard
          extraArgs.__append = lib.optionals (p.live && !p.wrapper.binary) [
            "--run"
            ''
              if [ ! -e ${liveDir} ]; then
                echo "${name}: ${liveDir} is missing -- the activation fragment for this wrapper is not installed" >&2
                exit 1
              fi
            ''
          ];
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
