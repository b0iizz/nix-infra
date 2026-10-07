{ withInputs, ... }:
withInputs
  {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  }
  (
    {
      lib,
      config,
      self,
      inputs,
      ...
    }:
    let
      inherit (lib)
        mkDefault
        mkOption
        types
        ;

      nixosModules = config.flake.modules.nixos;
      facter = self.lib.facter;

      # Disko layouts, each a NixOS module. Pick the ones a host needs as roles:
      #
      #   roles = [ "disko-root-impermanence" "disko-raid" ];
      #
      #   disko-layouts.swap.hibernation = true;   # root layouts: swap = RAM
      #   disko-layouts.swap.size = "8G";          # ...plus 8G on top
      #   disko-layouts.raid.level = 5;
      #
      # Disks come from `disk-select` and the host's facter report; tune a choice
      # with `disk-select.want.<root|raid|data>`, e.g. `.minSize` or `.filter`.
      #
      #   disko-root-ext4          root: ESP + swap + ext4
      #   disko-root-btrfs         root: ESP + swap + btrfs subvolumes
      #   disko-root-impermanence  root: as above, but `/` is wiped every boot
      #   disko-raid               N disks as one mdadm array, mounted at /data
      #   disko-data               one extra disk, mounted at /data
      #
      # Layouts compose unless they claim the same mountpoint: the root layouts
      # all claim `/`, raid and data both claim `/data` by default. Importing
      # two that clash fails evaluation naming them. (Change `raid.mountpoint`
      # or `data.mountpoint` to use both.)

      # --- sizes ------------------------------------------------------------------
      MiB = 1024 * 1024;
      pow = base: n: lib.foldl' (acc: _: acc * base) 1 (lib.genList (x: x) n);

      # Binary like disko and sgdisk read sizes: `8G` is 8 GiB. Ints are bytes.
      parseBytes =
        s:
        if lib.isInt s then
          s
        else
          let
            m = builtins.match "([0-9]+)[[:space:]]*([KMGT]?)i?B?" s;
            exp = {
              "" = 0;
              K = 1;
              M = 2;
              G = 3;
              T = 4;
            };
          in
          if m == null then
            throw "disko-layouts: cannot parse size '${s}'; expected e.g. 8G, 512M or bytes"
          else
            lib.toInt (lib.elemAt m 0) * pow 1024 exp.${lib.elemAt m 1};

      # Disko wants a size string; whole MiB, rounded up so swap is never short.
      toDiskoSize = bytes: "${toString ((bytes + MiB - 1) / MiB)}M";

      # Room the system itself needs on a root disk on top of swap. Only used to
      # rule out disks that are too small; see `disk-select.want.root.minSize`.
      rootHeadroom = 32 * pow 1024 3;

      # A layout's `config`: its claim on a mountpoint always, the rest only while
      # no other layout shares that claim. Two layouts defining the same disk would
      # otherwise die in a type-merge error that hides the assertion explaining it.
      layout =
        config: name: mountpoint: body:
        lib.mkMerge [
          {
            disko-layouts.claims = [
              {
                inherit mountpoint;
                layout = name;
              }
            ];
          }
          (lib.mkIf (!config.disko-layouts.clashing) body)
        ];

      # --- shared by the root layouts -------------------------------------------
      # The `root` disk-select want, as defaults so hosts can override any of it.
      rootWant = cfg: {
        minSize = mkDefault (cfg.swap.bytes + rootHeadroom);
        prefer = mkDefault "smallest";
        priority = mkDefault 0;
      };

      # The root disk: ESP, optional swap, and `rootContent` in the rest. Swap
      # is a partition on purpose: hibernation resumes from a plain block device,
      # with no filesystem or swapfile offset to get right.
      rootDisk =
        config: rootContent:
        let
          cfg = config.disko-layouts;
        in
        {
          device = config.disk-select.result.root;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = cfg.espSize;
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
            }
            // lib.optionalAttrs (cfg.swap.bytes > 0) {
              swap = {
                size = toDiskoSize cfg.swap.bytes;
                content = {
                  type = "swap";
                  discardPolicy = "both";
                  resumeDevice = cfg.swap.hibernation;
                };
              };
            }
            // {
              root = {
                size = "100%";
                content = rootContent;
              };
            };
          };
        };

      btrfsOpts = [
        "compress=zstd"
        "noatime"
      ];

      subvol = config: mountpoint: {
        inherit mountpoint;
        mountOptions = config.disko-layouts.mountOptions;
      };

      # --- shared by the data layouts -------------------------------------------
      filesystemOption = mkOption {
        type = types.enum [
          "ext4"
          "xfs"
          "btrfs"
        ];
        default = "ext4";
        description = "Filesystem on the data volume.";
      };

      mountpointOption = mkOption {
        type = types.path;
        default = "/data";
        description = "Where the data volume is mounted.";
      };
    in
    {
      # Every layout imports this one. It carries the keys that make that safe
      # (`key` deduplicates it, so importing five layouts declares the options
      # once) and everything the layouts share: swap sizing, the facter RAM
      # lookup and the clash check.
      flake.modules.nixos.disko-layouts =
        { config, ... }:
        let
          cfg = config.disko-layouts;
          ram = cfg.ramBytes;
          byMountpoint = lib.groupBy (c: c.mountpoint) cfg.claims;
        in
        {
          key = "disko-layouts";

          imports = [
            inputs.disko.nixosModules.disko
            nixosModules.disk-select
          ];

          options.disko-layouts = {
            ramBytes = mkOption {
              type = with types; nullOr ints.unsigned;
              default = facter.ramBytes (config.host-context.facter.report or null);
              defaultText = "installed RAM from the host's facter report";
              description = ''
                RAM of this machine in bytes, which sizes hibernation swap. Read
                from the facter report; set it by hand for hosts without one.
              '';
            };

            swap = {
              size = mkOption {
                type = with types; nullOr (either ints.unsigned str);
                default = null;
                example = "8G";
                description = ''
                  Swap on the root disk, in addition to hibernation space. Bytes,
                  or a string such as `8G` (binary, as disko reads sizes).
                  Root layouts only.
                '';
              };

              hibernation = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Make the root disk's swap able to hold a hibernation image: RAM
                  worth of space, which is also set as the resume device. Added
                  to `swap.size`. Root layouts only.
                '';
              };

              bytes = mkOption {
                type = types.ints.unsigned;
                readOnly = true;
                description = "Total swap partition size the root layouts create.";
              };
            };

            mountOptions = mkOption {
              type = types.listOf types.str;
              default = [ "defaults" ];
              description = ''
                Mount options of the root filesystem (of every btrfs subvolume,
                for the btrfs layouts, which default to zstd compression and
                noatime).
              '';
            };

            espSize = mkOption {
              type = types.str;
              default = "1G";
              description = "Size of the EFI system partition on the root disk.";
            };

            claims = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    mountpoint = mkOption { type = types.str; };
                    layout = mkOption { type = types.str; };
                  };
                }
              );
              default = [ ];
              internal = true;
              description = ''
                Mountpoints the imported layouts use. Layouts add themselves; two
                for one mountpoint is a contradiction and fails the build.
              '';
            };

            clashing = mkOption {
              type = types.bool;
              readOnly = true;
              internal = true;
              description = "Whether two imported layouts claim the same mountpoint.";
            };
          };

          config = {
            disko-layouts.clashing = lib.any (claims: lib.length claims > 1) (lib.attrValues byMountpoint);

            disko-layouts.swap.bytes =
              let
                hibernation =
                  if !cfg.swap.hibernation then
                    0
                  else if ram == null then
                    throw ''
                      disko-layouts: swap.hibernation needs the machine's RAM size, but the facter
                      report has none (or the host has no report). Set `disko-layouts.ramBytes`.
                    ''
                  else
                    ram;
              in
              hibernation + (if cfg.swap.size == null then 0 else parseBytes cfg.swap.size);

            assertions =
              lib.mapAttrsToList (mountpoint: claims: {
                assertion = lib.length claims <= 1;
                message = "disko-layouts: ${mountpoint} is claimed by ${
                  lib.concatMapStringsSep ", " (c: c.layout) claims
                }, which contradict; import only one of them (raid and data can instead be moved apart with their `mountpoint` option).";
              }) byMountpoint
              ++ [
                {
                  assertion = cfg.swap.bytes == 0 || lib.any (c: c.mountpoint == "/") cfg.claims;
                  message = "disko-layouts: swap.size/swap.hibernation are set but no root layout (disko-root-*) is imported to apply them.";
                }
              ];
          };
        };

      # --- root layouts -----------------------------------------------------------

      flake.modules.nixos.disko-root-ext4 =
        { config, ... }:
        {
          imports = [ nixosModules.disko-layouts ];

          config = layout config "disko-root-ext4" "/" {
            disk-select.want.root = rootWant config.disko-layouts;

            disko.devices.disk.root = rootDisk config {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = config.disko-layouts.mountOptions;
            };
          };
        };

      flake.modules.nixos.disko-root-btrfs =
        { config, ... }:
        {
          imports = [ nixosModules.disko-layouts ];

          config = layout config "disko-root-btrfs" "/" {
            disk-select.want.root = rootWant config.disko-layouts;
            disko-layouts.mountOptions = mkDefault btrfsOpts;

            disko.devices.disk.root = rootDisk config {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = subvol config "/";
                "/home" = subvol config "/home";
                "/nix" = subvol config "/nix";
                "/log" = subvol config "/var/log";
              };
            };

            fileSystems."/var/log".neededForBoot = true;
          };
        };

      # Btrfs for impermanence: `/` is a subvolume that is moved aside and
      # recreated empty in the initrd on every boot, so anything not under
      # /persist, /nix or /var/log is gone after a reboot (but kept in
      # /old_roots for a while, see `keepOldRootsDays`). What to keep is declared
      # elsewhere (e.g. the impermanence module); this layout only provides the
      # places to keep it.
      flake.modules.nixos.disko-root-impermanence =
        {
          config,
          pkgs,
          utils,
          ...
        }:
        let
          cfg = config.disko-layouts.impermanence;
          rootPartition = config.disko.devices.disk.root.content.partitions.root.device;
          device = "${utils.escapeSystemdPath rootPartition}.device";
          keep = toString cfg.keepOldRootsDays;
        in
        {
          imports = [ nixosModules.disko-layouts ];

          options.disko-layouts.impermanence = {
            persistDir = mkOption {
              type = types.str;
              default = "/persist";
              description = "Where the subvolume that survives reboots is mounted.";
            };

            keepOldRootsDays = mkOption {
              type = types.ints.unsigned;
              default = 30;
              description = ''
                Each boot moves the previous root to `/old_roots/<time>` on the
                btrfs top level (mount it with `-o subvolid=5`) instead of
                destroying it, so something forgotten in `/persist` can still be
                fetched. Roots older than this many days are deleted. 0 deletes
                the previous root immediately.
              '';
            };
          };

          config = layout config "disko-root-impermanence" "/" {
            disk-select.want.root = rootWant config.disko-layouts;
            disko-layouts.mountOptions = mkDefault btrfsOpts;

            disko.devices.disk.root = rootDisk config {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = subvol config "/";
                "/nix" = subvol config "/nix";
                "/persist" = subvol config cfg.persistDir;
                "/log" = subvol config "/var/log";
              };
            };

            fileSystems.${cfg.persistDir}.neededForBoot = true;
            fileSystems."/var/log".neededForBoot = true;

            # Needs systemd in the initrd: the wipe must be ordered after a
            # hibernation resume (the resume restores the hibernated system, whose
            # root must still be intact) and before `/` is mounted.
            boot.initrd.systemd.enable = mkDefault true;
            assertions = [
              {
                assertion = config.boot.initrd.systemd.enable;
                message = "disko-root-impermanence wipes / from the systemd initrd; enable boot.initrd.systemd.";
              }
            ];

            boot.initrd.systemd.services.rollback-root = {
              description = "Move the btrfs root subvolume aside and recreate it empty";
              wantedBy = [ "initrd.target" ];
              requires = [ device ];
              after = [
                device
                "systemd-hibernate-resume.service"
              ];
              before = [ "sysroot.mount" ];
              unitConfig.DefaultDependencies = "no";
              serviceConfig.Type = "oneshot";
              script = ''
                mkdir -p /btrfs-top
                mount -t btrfs -o subvolid=5 ${rootPartition} /btrfs-top

                if [ -e /btrfs-top/root ]; then
                  ${
                    if cfg.keepOldRootsDays == 0 then
                      "btrfs subvolume delete --recursive /btrfs-top/root"
                    else
                      ''
                        # Named after when it was last written, i.e. when that boot ended.
                        mkdir -p /btrfs-top/old_roots
                        stamp=$(date --date="@$(stat -c %Y /btrfs-top/root)" "+%Y-%m-%d_%H:%M:%S")
                        mv /btrfs-top/root "/btrfs-top/old_roots/$stamp"
                      ''
                  }
                fi

                if [ -d /btrfs-top/old_roots ]; then
                  find /btrfs-top/old_roots -mindepth 1 -maxdepth 1 -mtime +${keep} |
                    while read -r old; do
                      btrfs subvolume delete --recursive "$old"
                    done
                fi

                btrfs subvolume create /btrfs-top/root
                umount /btrfs-top
              '';
            };

            # The script's tools; the initrd only has what is listed.
            boot.initrd.systemd.initrdBin = [
              pkgs.btrfs-progs
              pkgs.coreutils
              pkgs.findutils
              pkgs.util-linux
            ];
          };
        };

      # --- data layouts -----------------------------------------------------------

      flake.modules.nixos.disko-raid =
        { config, ... }:
        let
          cfg = config.disko-layouts.raid;
          minDisks = {
            "0" = 2;
            "1" = 2;
            "5" = 3;
            "6" = 4;
            "10" = 4;
          };
          disks = lib.toList config.disk-select.result.raid;
        in
        {
          imports = [ nixosModules.disko-layouts ];

          options.disko-layouts.raid = {
            level = mkOption {
              type = types.enum [
                0
                1
                5
                6
                10
              ];
              default = 1;
              description = "mdadm RAID level.";
            };
            count = mkOption {
              type = types.ints.positive;
              default = 2;
              description = "Number of disks in the array.";
            };
            name = mkOption {
              type = types.str;
              default = "data";
              description = "Array name, used for the md device and the disk partition labels.";
            };
            filesystem = filesystemOption;
            mountpoint = mountpointOption;
          };

          config = layout config "disko-raid" cfg.mountpoint {
            assertions = [
              {
                assertion = cfg.count >= minDisks.${toString cfg.level};
                message = "disko-raid: RAID${toString cfg.level} needs at least ${
                  toString minDisks.${toString cfg.level}
                } disks, but raid.count is ${toString cfg.count}.";
              }
            ];

            # Largest disks that are alike in size (within ~100GB: "4TB" drives
            # differ by a few GB between makers; mdadm uses the smallest member).
            # The root layouts take priority 0, so the array gets what is left.
            disk-select.want.raid = {
              inherit (cfg) count;
              same = mkDefault [ (d: d.size / 100000000000) ];
              prefer = mkDefault "largest";
              priority = mkDefault 10;
            };

            disko.devices.disk = lib.listToAttrs (
              lib.imap1 (
                i: device:
                lib.nameValuePair "${cfg.name}-${toString i}" {
                  inherit device;
                  type = "disk";
                  content = {
                    type = "gpt";
                    partitions.mdadm = {
                      size = "100%";
                      content = {
                        type = "mdraid";
                        inherit (cfg) name;
                      };
                    };
                  };
                }
              ) disks
            );

            disko.devices.mdadm.${cfg.name} = {
              type = "mdadm";
              level = cfg.level;
              content = {
                type = "filesystem";
                format = cfg.filesystem;
                mountpoint = cfg.mountpoint;
              };
            };

            boot.swraid = {
              enable = true;
              mdadmConf = mkDefault "MAILADDR root";
            };
          };
        };

      flake.modules.nixos.disko-data =
        { config, ... }:
        let
          cfg = config.disko-layouts.data;
        in
        {
          imports = [ nixosModules.disko-layouts ];

          options.disko-layouts.data = {
            filesystem = filesystemOption;
            mountpoint = mountpointOption;
          };

          config = layout config "disko-data" cfg.mountpoint {
            # The largest disk the root layout did not take.
            disk-select.want.data = {
              prefer = mkDefault "largest";
              priority = mkDefault 10;
            };

            disko.devices.disk.data = {
              device = config.disk-select.result.data;
              type = "disk";
              content = {
                type = "gpt";
                partitions.data = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = cfg.filesystem;
                    mountpoint = cfg.mountpoint;
                  };
                };
              };
            };
          };
        };
    }
  )
