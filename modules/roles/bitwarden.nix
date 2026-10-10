# Bitwarden desktop client, and its extension in the host's LibreWolf and
# Firefox (see `browser-extensions` in modules/wrappers/firefox/default.nix).
# The vault lives on the server; only the login and the local cache are kept
# across reboots.
#
#   roles = [ "workstation" "bitwarden" ];
{ self, ... }:
{
  flake.modules.nixos.bitwarden =
    { pkgs, ... }:
    {
      imports = with self.modules.nixos; [
        persist
        browser-extensions
      ];

      # in the browsers of the host (`librewolf`, `firefox` roles)
      browser.extensions."{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";

      environment.systemPackages = [ pkgs.bitwarden-desktop ];

      persist.home.directories = [ ".config/Bitwarden" ];
    };
}
