# Feature: state a wrapped program keeps in the home directory.
#
#   passthru.persist.directories   paths relative to $HOME, e.g. ".mozilla"
#   passthru.persist.files         likewise
#
# Only read on hosts with `disko-root-impermanence` (modules/impermanence.nix),
# which keeps them for every user that has the wrapper installed.
{ lib, ... }:
{
  perSystem.wrapperExtensions = lib.mkOrder 110 [
    {
      passthru.persist = {
        directories = _: [ ];
        files = _: [ ];
      };
    }
  ];
}
