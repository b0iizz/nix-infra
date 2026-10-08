# nixpkgs' lib has no integer power (`lib.pow` does not exist).
{ lib, ... }:
{
  flake.lib.pow = base: exp: lib.foldl' (acc: _: acc * base) 1 (lib.range 1 exp);
}
