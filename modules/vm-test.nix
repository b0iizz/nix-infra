# Installs a host into a QEMU VM the way `provision` does (disko formats the
# disk, nixos-install puts the system on it), boots it, reboots it, and checks
# that the root wipe of `disko-root-impermanence` keeps what it must. One test
# per host with that role, no hardware and no secrets needed:
#
#   nix build .#vm-test-prometheus
#
# The VM runs the host's own roles and modules with a few changes: a small
# virtual disk and swap, the test backdoor (so the test can run commands), no
# EFI variables, and no password secret (the VM has no host key to decrypt it).
# Everything else, the btrfs layout, the initrd rollback service and
# `preservation`, is the host's own. A few minutes, mostly the install.
{
  lib,
  config,
  self,
  ...
}:
let
  hosts = lib.filterAttrs (
    _: host: host.enable && lib.elem "disko-root-impermanence" host.roles
  ) config.registry.hosts;
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages = lib.mapAttrs' (
        name: _host:
        lib.nameValuePair "vm-test-${name}" (
          let
            target = self.nixosConfigurations.${name}.extendModules {
              modules = [
                (
                  { modulesPath, ... }:
                  {
                    imports = [ "${modulesPath}/testing/test-instrumentation.nix" ];

                    disko.devices.disk.root.device = lib.mkForce "/dev/vda";
                    disko-layouts.ramBytes = lib.mkForce (512 * 1024 * 1024);
                    disko-layouts.swap.size = lib.mkForce (256 * 1024 * 1024);

                    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
                    boot.initrd.availableKernelModules = [
                      "virtio_blk"
                      "virtio_pci"
                    ];
                    # the host key the secrets are encrypted to is not in the VM
                    users.users = lib.genAttrs ([ "root" ] ++ lib.attrNames config.registry.users) (_: {
                      hashedPasswordFile = lib.mkForce null;
                      initialPassword = "test";
                    });
                    documentation.enable = lib.mkForce false;
                  }
                )
              ];
            };
            tc = target.config.system.build;
            persistDir = target.config.disko-layouts.impermanence.persistDir;
          in
          pkgs.testers.runNixOSTest {
            name = "vm-test-${name}";
            nodes = {
              installer =
                { pkgs, ... }:
                {
                  virtualisation.memorySize = 4096;
                  virtualisation.diskSize = 20 * 1024;
                  virtualisation.cores = 4;
                  # the installed system lives on /dev/vda; the installer boots from vdb
                  virtualisation.emptyDiskImages = [ 8192 ];
                  virtualisation.rootDevice = "/dev/vdb";
                  virtualisation.fileSystems."/".autoFormat = true;
                  virtualisation.diskImage = "./target.qcow2";
                  virtualisation.additionalPaths = [
                    tc.toplevel
                    tc.diskoScript
                  ];
                  environment.systemPackages = [ pkgs.nixos-install-tools ];
                  nix.settings.substituters = lib.mkForce [ ];
                };
              target = {
                virtualisation.memorySize = 2048;
                virtualisation.diskImage = "./target.qcow2";
                virtualisation.useBootLoader = true;
                virtualisation.useEFIBoot = true;
                virtualisation.useDefaultFilesystems = false;
                virtualisation.efi.keepVariables = false;
                virtualisation.fileSystems."/" = {
                  device = "/dev/disk/by-label/this-is-not-real-and-will-never-be-used";
                  fsType = "ext4";
                };
              };
            };

            testScript = ''
              installer.start()
              installer.wait_for_unit("multi-user.target")
              installer.succeed("udevadm settle")

              with subtest("disko formats and mounts the disk"):
                  installer.succeed("${tc.diskoScript} >&2")
                  installer.succeed("findmnt /mnt/persist && findmnt /mnt/etc/ssh && findmnt /mnt/boot")

              with subtest("nixos-install puts the host on it"):
                  installer.succeed("mkdir -p /mnt/etc && nixos-install --no-root-passwd --system ${tc.toplevel} < /dev/null >&2")
                  installer.succeed("umount -R /mnt && sync")
                  installer.shutdown()

              # the same machine and disk, booted from the disk this time
              target.state_dir = installer.state_dir
              target.start()
              target.wait_for_unit("multi-user.target")

              with subtest("first boot has the layout and the kept state"):
                  target.succeed("findmnt ${persistDir} && findmnt /etc/ssh && findmnt /var/log")
                  target.succeed("test -s /etc/machine-id")
                  target.succeed("test -d /home/joni/Projects")
                  target.succeed("echo kept > /home/joni/Projects/kept; echo gone > /home/joni/gone; echo gone > /root/gone")
                  target.succeed("cat /etc/machine-id > /home/joni/Projects/machine-id")

              target.shutdown()
              target.start()
              target.wait_for_unit("multi-user.target")

              with subtest("a reboot wipes the root and keeps the declared state"):
                  target.succeed("test \"$(cat /home/joni/Projects/kept)\" = kept")
                  target.fail("test -e /home/joni/gone")
                  target.fail("test -e /root/gone")
                  target.succeed("test \"$(cat /etc/machine-id)\" = \"$(cat /home/joni/Projects/machine-id)\"")
                  target.succeed("mkdir /top && mount -o subvolid=5 /dev/disk/by-partlabel/disk-root-root /top")
                  target.succeed("test \"$(cat /top/old_roots/*/home/joni/gone)\" = gone")
            '';
          }
        )
      ) (lib.filterAttrs (_: host: host.system == system) hosts);
    };
}
