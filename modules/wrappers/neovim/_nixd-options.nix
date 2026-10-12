# The options nixd completes in a flake, for its `options.<name>.expr`
# (languages.nix): `flake -> { nixos; flake-parts; perSystem; }`.
#
#   nixos        the NixOS options of every host, merged
#   flake-parts  top-level flake-parts options (theme, registry, flake.*)
#   perSystem    perSystem options (wrappers, packages, checks)
#
# The flake-parts sets exist only in a flake with `debug = true`. Not imported
# as a module (import-tree skips `_` files).
flake:
let
  isOption = v: builtins.isAttrs v && (v._type or null) == "option";
  # deep, but stops at options, so a host's own (atlas: services.copyparty)
  # survive next to the others'
  merge =
    a: b:
    a
    // builtins.mapAttrs (
      n: v:
      if
        builtins.hasAttr n a
        && builtins.isAttrs v
        && builtins.isAttrs a.${n}
        && !isOption v
        && !isOption a.${n}
      then
        merge a.${n} v
      else
        v
    ) b;
in
{
  nixos = builtins.foldl' merge { } (
    map (c: c.options) (builtins.attrValues (flake.nixosConfigurations or { }))
  );
  flake-parts = flake.debug.options or { };
  perSystem = flake.currentSystem.options or { };
}
