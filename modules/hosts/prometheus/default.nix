# Framework 13 laptop (13th gen Intel). Everything a desktop needs is in the
# roles; what is left here belongs to this machine or this person.
#
# Prometheus stole fire from the gods and gave it to people; this laptop was
# the first machine to give its owner NixOS.
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
          "bitwarden"
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
          (
            { pkgs, ... }:
            {
              # niri until the Hyprland setup is finished
              desktop.sessions.niri.order = 5;
              # 188/120, a logical 1440x960: Hyprland refuses scales that leave
              # 2256x1504 fractional (1.5 would) and warns at every start.
              # Unset, Hyprland and sway guess larger.
              desktop.outputs.eDP-1.scale = 1.566667;

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
          )
          (
            { config, ... }:
            {
              # joni's key for copyparty's SFTP on atlas, which cannot check
              # FIDO2 keys: sftp -P 3922 -i ~/.ssh/id_ed25519_nas joni@10.10.0.55:/video
              # Made by `agenix generate`, which writes the public half next to
              # the secret; modules/hosts/atlas authorizes it.
              age.secrets.copyparty-sftp-joni = {
                path = "${config.users.users.joni.home}/.ssh/id_ed25519_nas";
                owner = "joni";
                mode = "0400";
                generator.script =
                  {
                    lib,
                    pkgs,
                    file,
                    name,
                    ...
                  }:
                  ''
                    dir=$(mktemp -d)
                    trap 'rm -rf "$dir"' EXIT
                    ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C ${lib.escapeShellArg name} -f "$dir/key"
                    cp "$dir/key.pub" ${lib.escapeShellArg "${lib.removeSuffix ".age" file}.pub"}
                    cat "$dir/key"
                  '';
              };
            }
          )
        ];
      };

      # the key to the other hosts lives on the machine it is used from
      registry.users.joni.keyHosts = [ "prometheus" ];
    }
  )
