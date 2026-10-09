# Framework 13 laptop (13th gen Intel). Everything a desktop needs is in the
# roles; what is left here belongs to this machine or this person.
#
# Installed as a console system first. Once it runs, set `graphical = true`
# and `deploy prometheus` to add the graphical interface.
{ lib, withInputs, ... }:
withInputs
  {
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    { inputs, self, ... }:
    let
      graphical = false;
    in
    {
      registry.hosts.prometheus = {
        path = ./.;
        stateVersion = "26.11";

        # installed from itself, booted from the installer stick
        provision.method = "local";

        roles = [
          "disko-root-impermanence"
          "workstation"
          "laptop"
          "programming"
        ]
        ++ lib.optionals graphical [
          "quickshell"
          "removable-media"
          "greeter"
          "niri"
          "hyprland"
          "sway"
          "librewolf"
          "alacritty"
          "office"
          "gaming"
        ];

        modules = [
          (
            { pkgs, ... }:
            {
              imports = [ inputs.nixos-hardware.nixosModules.framework-13th-gen-intel ];

              # hibernation image as big as the RAM, plus 32 GiB of ordinary swap
              disko-layouts.swap.hibernation = true;
              disko-layouts.swap.size = "32GiB";
              # a laptop gets lost: the disk is encrypted, swap and the
              # hibernation image with it
              disko-layouts.luks.enable = true;
              # opened with the FIDO2 token (enrolled by `provision commit
              # --local`); the recovery keys it prints are the way in without it
              disko-layouts.luks.fido2 = true;

              hardware.fw-fanctrl.enable = true;
              services.hardware.bolt.enable = true;
              # the authorised Thunderbolt devices
              persist.directories = [ "/var/lib/boltd" ];

              programs.git.config.user = {
                name = "Jonathan Grebe";
                email = "joni.grebe@gmail.com";
              };

              environment.systemPackages = [ pkgs.wget ];
            }
          )
        ]
        ++ lib.optional graphical (
          { pkgs, ... }:
          {
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
            ]);
          }
        );
      };

      # the key to the other hosts lives on the machine it is used from
      registry.users.joni.keyHosts = [ "prometheus" ];
    }
  )
