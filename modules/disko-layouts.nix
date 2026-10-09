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
      #   disko-layouts.swap.size = "8GiB";        # ...plus 8 GiB on top
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
      inherit (self.lib) parseSize;

      # Disko wants a size string, which it reads as binary (`8M` is 8 MiB);
      # whole MiB, rounded up so swap is never short.
      toDiskoSize = bytes: "${toString ((bytes + MiB - 1) / MiB)}M";

      # Room the system itself needs on a root disk on top of swap. Only used to
      # rule out disks that are too small; see `disk-select.want.root.minSize`.
      rootHeadroom = 32 * 1024 * MiB;

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

      # LVM volume group inside the LUKS volume: swap and root are logical
      # volumes, /dev/mapper/system-swap and /dev/mapper/system-root.
      lvmVg = "system";

      # The root disk: ESP, optional swap, and `rootContent` in the rest. Swap
      # is a plain block device on purpose: hibernation resumes from it, with
      # no filesystem or swapfile offset to get right. Without LUKS it is a
      # partition; with LUKS it is a logical volume next to the root, so one
      # unlock (one passphrase, or one PIN and touch) opens both.
      rootDisk =
        config: rootContent:
        let
          cfg = config.disko-layouts;
          swapContent = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = cfg.swap.hibernation;
          };
          hasSwap = cfg.swap.bytes > 0;
          rootPartitionContent =
            if cfg.luks.enable then
              {
                type = "luks";
                name = cfg.luks.name;
                settings.allowDiscards = true;
                content = {
                  type = "lvm_pv";
                  vg = lvmVg;
                };
              }
              // (if cfg.luks.fido2 then { enrollFido2 = true; } else { passwordFile = cfg.luks.passwordFile; })
            else
              rootContent;
        in
        {
          disk.root = {
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
              // lib.optionalAttrs (hasSwap && !cfg.luks.enable) {
                swap = {
                  size = toDiskoSize cfg.swap.bytes;
                  content = swapContent;
                };
              }
              // {
                root = {
                  size = "100%";
                  content = rootPartitionContent;
                };
              };
            };
          };
        }
        // lib.optionalAttrs cfg.luks.enable {
          lvm_vg.${lvmVg} = {
            type = "lvm_vg";
            lvs =
              lib.optionalAttrs hasSwap {
                swap = {
                  size = toDiskoSize cfg.swap.bytes;
                  content = swapContent;
                };
              }
              // {
                root = {
                  size = "100%FREE";
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
                example = "8GiB";
                description = ''
                  Swap on the root disk, in addition to hibernation space. Bytes,
                  or a string: `8GiB` (binary) or `8G` (decimal).
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

            luks = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Encrypt the root filesystem and the swap, and so the hibernation
                  image, with LUKS2 (root layouts only). One LUKS volume holds an
                  LVM group with swap and root as logical volumes, so the
                  passphrase is asked for once at boot. `provision commit` asks for it and
                  hands it to disko, nothing keeps it. See `fido2` for a token.
                '';
              };

              fido2 = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Unlock with a FIDO2 token instead of a passphrase. disko enrolls
                  the token while `provision commit --local` formats (it waits for
                  the token, then asks for its PIN and a touch) and prints a
                  recovery key: that key is the only way in without the token,
                  so store it. One PIN and touch per boot. Needs `luks.enable`. A remote commit
                  refuses it: the token would have to sit in the target.
                '';
              };

              name = mkOption {
                type = types.str;
                default = "cryptroot";
                description = "Name of the opened LUKS volume under /dev/mapper; the logical volumes in it are `system-root` and `system-swap`.";
              };

              passwordFile = mkOption {
                type = types.str;
                default = "/tmp/luks-root.key";
                description = "Where the installer puts the passphrase while formatting. Only used then.";
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
            # the systemd initrd needs this to activate the volume group
            boot.initrd.services.lvm.enable = lib.mkIf cfg.luks.enable true;

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
              hibernation + (if cfg.swap.size == null then 0 else parseSize cfg.swap.size);

            assertions =
              lib.mapAttrsToList (mountpoint: claims: {
                assertion = lib.length claims <= 1;
                message = "disko-layouts: ${mountpoint} is claimed by ${
                  lib.concatMapStringsSep ", " (c: c.layout) claims
                }, which contradict; import only one of them (raid and data can instead be moved apart with their `mountpoint` option).";
              }) byMountpoint
              ++ [
                {
                  assertion = !cfg.luks.fido2 || cfg.luks.enable;
                  message = "disko-layouts: luks.fido2 is set but luks.enable is not.";
                }
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

            disko.devices = rootDisk config {
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

            disko.devices = rootDisk config {
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
      # /persist, /nix, /var/log, /etc/ssh (the host key, which secrets need)
      # or /var/lib/nixos (uid maps) is gone after a reboot (but kept in
      # /old_roots for a while, see `keepOldRootsDays`). What to keep is declared
      # by the impermanence module (modules/impermanence.nix, imported here); this
      # layout only provides the places to keep it.
      flake.modules.nixos.disko-root-impermanence =
        {
          config,
          pkgs,
          utils,
          ...
        }:
        let
          cfg = config.disko-layouts.impermanence;
          # what holds the btrfs: the partition, or the root logical volume in the LUKS volume
          rootPartition =
            if config.disko-layouts.luks.enable then
              "/dev/mapper/${lvmVg}-root"
            else
              config.disko.devices.disk.root.content.partitions.root.device;
          device = "${utils.escapeSystemdPath rootPartition}.device";
        in
        {
          imports = [
            nixosModules.disko-layouts
            nixosModules.impermanence
          ];

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
                fetched. Roots retired more than this many days ago are deleted. 0 deletes
                the previous root immediately.
              '';
            };
          };

          config = layout config "disko-root-impermanence" "/" {
            disk-select.want.root = rootWant config.disko-layouts;
            disko-layouts.mountOptions = mkDefault btrfsOpts;

            disko.devices = rootDisk config {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = subvol config "/";
                "/nix" = subvol config "/nix";
                "/persist" = subvol config cfg.persistDir;
                "/log" = subvol config "/var/log";
                # what the system itself needs to survive a boot: the host key
                # (secrets are decrypted with it) and the uid/gid allocations
                "/ssh" = subvol config "/etc/ssh";
                "/nixos-state" = subvol config "/var/lib/nixos";
              };
            };

            fileSystems.${cfg.persistDir}.neededForBoot = true;
            fileSystems."/var/log".neededForBoot = true;
            fileSystems."/etc/ssh".neededForBoot = true;
            fileSystems."/var/lib/nixos".neededForBoot = true;

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
              script = self.lib.impermanence.rollbackScript {
                partition = rootPartition;
                keepDays = cfg.keepOldRootsDays;
              };
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
