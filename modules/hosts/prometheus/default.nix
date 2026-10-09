# Framework 13 laptop (13th gen Intel). Everything a desktop needs is in the
# roles; what is left here belongs to this machine or this person.
{ self, withInputs, ... }:
withInputs
  {
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    { inputs, ... }:
    {
      registry.hosts.prometheus = {
        path = ./.;
        stateVersion = "26.05";

        # installed from itself, booted from the installer stick
        provision.method = "local";

        roles = [
          "disko-root-impermanence"
          "workstation"
          "laptop"
          "quickshell"
          "greeter"
          "niri"
          "hyprland"
          "librewolf"
          "firefox"
          "alacritty"
          "programming"
          "office"
          "gaming"
        ];

        modules = [
          (
            { lib, pkgs, ... }:
            {
              imports = [ inputs.nixos-hardware.nixosModules.framework-13th-gen-intel ];

              # hibernation image, as big as the RAM
              disko-layouts.swap.hibernation = true;

              hardware.fw-fanctrl.enable = true;
              services.hardware.bolt.enable = true;

              # niri until the Hyprland setup is finished
              desktop.sessions.niri.order = 5;

              # the printer and the scanner at home (epkowa is unfree)
              services.printing.drivers = with pkgs; [
                epson-escpr2
                epson-escpr
              ];
              hardware.sane.extraBackends = [ pkgs.epkowa ];
              nixpkgs.config.allowUnfree = true;

              environment.systemPackages = [
                self.packages.${pkgs.stdenv.hostPlatform.system}.spotify-player
              ]
              ++ (with pkgs; [
                eduvpn-client
                gnome-network-displays
                wget
              ]);
            }
          )
        ];
      };

      # the key to the other hosts lives on the machine it is used from
      registry.users.joni.keyHosts = [ "prometheus" ];
    }
  )
