# Bitwarden desktop client, and its extension in the host's LibreWolf and
# Firefox (see `browser-extensions` in modules/wrappers/firefox/default.nix).
# The vault lives on the server; only the login and the local cache are kept
# across reboots.
#
# Bitwarden only uses a Secret Service, it cannot be one, so the role brings
# gnome-keyring as the system keyring. The greeter unlocks it with the login
# password (modules/wrappers/quickshell/greeter.nix); its keyrings are kept.
# With the keepassxc role on the same host, KeePassXC is the keyring instead.
#
#   roles = [ "workstation" "bitwarden" ];
{ self, ... }:
{
  flake.modules.nixos.bitwarden =
    { lib, pkgs, ... }:
    {
      imports = with self.modules.nixos; [
        persist
        browser-extensions
      ];

      # in the browsers of the host (`librewolf`, `firefox` roles)
      browser.extensions."{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";

      environment.systemPackages = [ pkgs.bitwarden-desktop ];

      # mkDefault: the keepassxc role turns it off
      services.gnome.gnome-keyring.enable = lib.mkDefault true;

      persist.home.directories = [
        ".config/Bitwarden"
        {
          directory = ".local/share/keyrings";
          mode = "0700";
        }
      ];
    };
}
