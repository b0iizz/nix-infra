{ withInputs, ... }:
withInputs
  {
    nixos-images = {
      url = "github:nix-community/nixos-images";
      inputs.nixos-unstable.follows = "nixpkgs";
    };
    nixos-facter = {
      url = "github:nix-community/nixos-facter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
  }
  (
    {
      lib,
      config,
      inputs,
      ...
    }:
    let
      # Both images log in as root with the registry's admin keys, carry
      # nixos-facter, and mark themselves with /etc/provision-installer so the
      # provision CLI can tell "already in an installer" from "a real system".
      installerBase =
        kind: facter:
        { lib, ... }:
        {
          services.openssh.enable = lib.mkDefault true;
          users.users.root.openssh.authorizedKeys.keys = config.registry.adminKeys;
          environment.systemPackages = [ facter ];
          environment.etc."provision-installer".text = kind;
          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
          ];
        };

      # Filesystem types a disko `devices` tree formats, found by walking it
      # (disks -> partitions -> luks/lvm/mdadm -> content). Keys starting with
      # `_` are disko internals that point back up the tree.
      filesystemsOf =
        node:
        if lib.isList node then
          lib.concatMap filesystemsOf node
        else if !lib.isAttrs node then
          [ ]
        else
          lib.optional ((node.type or null) == "filesystem" && node ? format) node.format
          ++ lib.optional (lib.elem (node.type or null) [
            "btrfs"
            "zfs"
            "bcachefs"
          ]) node.type
          ++ lib.concatMap filesystemsOf (lib.attrValues (lib.filterAttrs (n: _: !lib.hasPrefix "_" n) node));

      # What the ISO must be able to format: ext4 and btrfs always, plus whatever
      # the registry's hosts actually use, so adding a filesystem to disko-layouts.nix (or choosing one
      # for a host) needs no change here. A host that does not evaluate yet, e.g.
      # one still waiting for its facter report, contributes nothing.
      fleetFilesystems = lib.unique (
        # Always: the ESP, and the two filesystems the stock layouts are made of.
        [
          "vfat"
          "ext4"
          "btrfs"
        ]
        ++ lib.concatMap (
          host:
          let
            found = filesystemsOf (host.config.disko.devices or { });
            tried = builtins.tryEval (builtins.deepSeq found found);
          in
          if tried.success then tried.value else [ ]
        ) (lib.attrValues config.flake.nixosConfigurations)
      );
    in
    {
      perSystem =
        {
          config,
          system,
          pkgs,
          inputs',
          ...
        }:
        let
          facter = inputs'.nixos-facter.packages.default;
          disko = pkgs.disko; # the input's closure carries a copy of nixpkgs
          images = inputs.nixos-images.nixosModules;

          installer =
            modules:
            inputs.nixpkgs.lib.nixosSystem {
              modules = [ { nixpkgs.hostPlatform = system; } ] ++ modules;
            };

          # Booted from RAM by `provision` on a running machine, which then
          # talks to it over ssh. Stripped down because it all lives in memory:
          # disko and the install itself are driven by nixos-anywhere from outside.
          kexec = installer [
            images.kexec-installer
            images.noninteractive
            (installerBase "kexec" facter)
            { system.kexec-installer.name = "nixos-kexec-installer"; }
          ];

          # Written to a stick for machines that cannot be kexec'd, and for
          # installing the machine you are sitting at (`provision commit --local`).
          # Has the whole toolbox, including provision itself.
          #
          # Minimal on purpose: nixpkgs' minimal installation CD, trimmed further
          # by the same noninteractive profile as the kexec image. Left out
          # compared to the nixos-images installer: tor, network-status, the
          # latest kernel with zfs/bcachefs, generated root password, docs.
          # Wifi is the one convenience kept (iwd; `iwctl`), since a laptop has
          # to get online to fetch the flake.
          iso = installer [
            (inputs.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            images.noninteractive
            (installerBase "iso" facter)
            {
              environment.systemPackages = [
                disko
                config.packages.provision-cli
                inputs'.nixos-anywhere.packages.default
                pkgs.nixos-install-tools
              ];

              networking.hostName = "nixos-installer";
              # NetworkManager (from the installation-device profile) is far
              # bigger than networkd + iwd; sshd is the only service to reach.
              networking.networkmanager.enable = lib.mkForce false;
              networking.wireless.enable = lib.mkForce false;
              networking.wireless.iwd.enable = true;
              networking.useNetworkd = true;
              networking.firewall.enable = false;

              services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

              # The installation-device profile forces these on at image priority.
              documentation.enable = lib.mkForce false;
              documentation.nixos.enable = lib.mkForce false;
              documentation.doc.enable = lib.mkForce false;
              documentation.man.enable = lib.mkForce false;
              system.installer.channel.enable = false; # a 200 MB copy of nixpkgs
              system.tools.nixos-rebuild.enable = false; # drags in python
              programs.git.package = pkgs.gitMinimal;
              # Only what the fleet's disko configs format (see fleetFilesystems).
              # The noninteractive profile's extras, xfs especially, pull in python.
              boot.supportedFilesystems = lib.mkForce fleetFilesystems;

              # No one got time for xz.
              isoImage.squashfsCompression = "zstd";
              image.baseName = lib.mkForce "nixos-installer-${system}";
            }
          ];
        in
        {
          # nix build .#kexec-installer   -> a directory holding the .tar.gz
          packages.kexec-installer = kexec.config.system.build.kexecInstallerTarball;
          # nix build .#iso-installer     -> a directory holding iso/*.iso
          packages.iso-installer = iso.config.system.build.isoImage;
        };
    }
  )
