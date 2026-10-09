# What a role or host wants to keep across reboots, without knowing whether the
# machine wipes its root. Every host has the options (imported by `base`); only
# a layout that wipes `/` reads them (`disko-root-impermanence`, see
# modules/impermanence.nix), anywhere else they do nothing.
#
#   persist.directories        absolute paths, e.g. "/var/lib/cups"
#   persist.files              likewise
#   persist.home.directories   relative to $HOME, kept for every normal user
#   persist.home.files         likewise
#
# A path may also be an attrset of the underlying preservation module
# (`{ directory = ...; mode = ...; }`).
#
# Wrapped programs declare their own home paths with `passthru.persist`
# (modules/wrappers/persist.nix), the rest is declared by the role that
# installs the program or by the host.
{ self, lib, ... }:
let
  inherit (lib) mkOption types;

  paths =
    description:
    mkOption {
      type = types.listOf (types.either types.str (types.attrsOf types.anything));
      default = [ ];
      inherit description;
    };
in
{
  flake.modules.nixos.base.imports = [ self.modules.nixos.persist ];

  flake.modules.nixos.persist = {
    # roles import this, too: the options must be declared once
    key = "modules/persist.nix";

    options.persist = {
      directories = paths "Directories to keep, absolute.";
      files = paths "Files to keep, absolute.";
      home = {
        directories = paths "Directories to keep for every normal user, relative to $HOME.";
        files = paths "Files to keep for every normal user, relative to $HOME.";
      };
    };
  };
}
