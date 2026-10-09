# Installs a host into a QEMU VM with `provision commit --local`, boots it,
# reboots it, and checks that the root wipe of `disko-root-impermanence` keeps
# what it must. One test per host with that role, no hardware and no secrets
# needed:
#
#   nix build .#vm-test-prometheus
#
# The VM runs the host's own roles and modules with a few changes: a small
# virtual disk and swap, the test backdoor (so the test can run commands), no
# EFI variables, a throwaway host key and no password secret (that key cannot
# decrypt it). Everything else, the btrfs layout, LUKS where the host has it,
# the initrd rollback service and `preservation`, is the host's own.
#
# `provision` is the real tool; only what it reaches out to is stood in for:
# the flake (`nix` answers from the target's configuration), the disks
# (`disko` is the target's own script) and the network (a remote commit first,
# against nothing, records what nixos-anywhere would have been handed). A few
# minutes, mostly the install.
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
            luks = target.config.disko-layouts.luks;
            passphrase = "test";
            # lines of the test script for a host with LUKS (the type check
            # refuses an `if` on a constant)
            ifLuks = lib.optionalString luks.enable;
            resume = target.config.boot.resumeDevice;

            provision = self.packages.${system}.provision-cli.withRuntimeInputs [
              (pkgs.writeShellScriptBin "nix" ''
                case "$*" in
                  *'#provisionData')
                    echo ${
                      lib.escapeShellArg (
                        builtins.toJSON {
                          ${name} = {
                            age = "/host.age";
                            pub = "/host.pub";
                            facter = "/facter.json";
                            method = "local";
                          };
                        }
                      )
                    } ;;
                  *.disko.devices.disk*)
                    echo ${
                      lib.escapeShellArg (
                        builtins.toJSON (lib.mapAttrs (_: d: d.device) target.config.disko.devices.disk)
                      )
                    } ;;
                  *.luks.enable) echo ${lib.boolToString luks.enable} ;;
                  *.luks.passwordFile) echo ${luks.passwordFile} ;;
                  *.toplevel) echo ${tc.toplevel} ;;
                  *'#host-key-cli'*) mkdir -p "''${*: -1}/etc/ssh" && cp /tmp/key/* "''${*: -1}/etc/ssh/" ;;
                  *) echo "nix, standing in: unexpected $*" >&2; exit 1 ;;
                esac
              '')
              (pkgs.writeShellScriptBin "disko" "exec ${tc.diskoScript}")
              (pkgs.writeShellScriptBin "ssh" "true")
              (pkgs.writeShellScriptBin "ssh-keyscan" ''echo "''${*: -1} $(cat /tmp/key/ssh_host_ed25519_key.pub)"'')
              (pkgs.writeShellScriptBin "nixos-anywhere" ''
                while [ $# -gt 0 ]; do
                  case $1 in
                    --extra-files) (cd "$2" && find . | sort) >/tmp/sent-files; shift ;;
                    --disk-encryption-keys) cp "$3" /tmp/sent-luks-key; shift 2 ;;
                  esac
                  shift
                done
              '')
            ];
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
                  environment.systemPackages = [
                    pkgs.nixos-install-tools
                    provision
                  ];
                  nix.settings.substituters = lib.mkForce [ ];
                };
              target = {
                # LUKS' key derivation takes 1 GiB, and root and swap are opened at once
                virtualisation.memorySize = 4096;
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

              # a throwaway host key, and the files `provision` checks for in the repository
              installer.succeed(
                  "mkdir -p /tmp/key /tmp/flake",
                  '${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "" -f /tmp/key/ssh_host_ed25519_key',
                  "cp /tmp/key/ssh_host_ed25519_key.pub /tmp/flake/host.pub",
                  "touch /tmp/flake/host.age /tmp/flake/facter.json",
              )
              key = installer.succeed("cat /tmp/key/ssh_host_ed25519_key.pub")
              commit = "printf '%s\\n' ${passphrase} ${passphrase} | FLAKE_ROOT=/tmp/flake provision commit ${name} --yes"

              with subtest("a remote commit sends the host key and nothing else"):
                  installer.succeed(f"{commit} --target root@192.0.2.1 >&2")
                  sent = installer.succeed("cat /tmp/sent-files").split()
                  assert sent == [".", "./etc", "./etc/ssh", "./etc/ssh/ssh_host_ed25519_key", "./etc/ssh/ssh_host_ed25519_key.pub"], sent
                  ${ifLuks ''installer.succeed("test \"$(cat /tmp/sent-luks-key)\" = ${passphrase}")''}

              with subtest("a local commit formats, installs and keeps no passphrase"):
                  installer.succeed(f"{commit} --local >&2")
                  installer.succeed("findmnt /mnt${persistDir} && findmnt /mnt/etc/ssh && findmnt /mnt/boot")
                  installer.fail("test -e ${luks.passwordFile}")
                  assert installer.succeed("cat /mnt/etc/ssh/ssh_host_ed25519_key.pub") == key
                  installer.succeed("umount -R /mnt && sync")
                  installer.shutdown()

              def boot():
                  target.start()
                  # one passphrase for root and swap: a second prompt would time out below
                  ${ifLuks ''target.wait_for_console_text("Please enter passphrase")''}
                  ${ifLuks ''target.send_console("${passphrase}\n")''}
                  target.wait_for_unit("multi-user.target")

              # the same machine and disk, booted from the disk this time
              target.state_dir = installer.state_dir
              boot()

              with subtest("first boot has the layout, the host key and the kept state"):
                  target.succeed("findmnt ${persistDir} && findmnt /etc/ssh && findmnt /var/log")
                  assert target.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub") == key, "not the installed host key"
                  # swap, and so the hibernation image, is on the encrypted volume
                  ${ifLuks ''target.succeed('test "$(swapon --show=NAME --noheadings)" = "$(readlink -f /dev/mapper/${luks.name}-swap)"')''}
                  ${lib.optionalString (
                    resume != ""
                  ) ''target.succeed("grep -q 'resume=${resume}' /proc/cmdline")''}
                  target.succeed("test -s /etc/machine-id")
                  target.succeed("test -d /home/joni/Projects")
                  target.succeed("echo kept > /home/joni/Projects/kept; echo gone > /home/joni/gone; echo gone > /root/gone")
                  target.succeed("cat /etc/machine-id > /home/joni/Projects/machine-id")

              target.shutdown()
              boot()

              with subtest("a reboot wipes the root and keeps the declared state"):
                  target.succeed("test \"$(cat /home/joni/Projects/kept)\" = kept")
                  target.fail("test -e /home/joni/gone")
                  target.fail("test -e /root/gone")
                  target.succeed("test \"$(cat /etc/machine-id)\" = \"$(cat /home/joni/Projects/machine-id)\"")
                  target.succeed("mkdir /top && mount -o subvolid=5 ${
                    if luks.enable then "/dev/mapper/${luks.name}" else "/dev/disk/by-partlabel/disk-root-root"
                  } /top")
                  target.succeed("test \"$(cat /top/old_roots/*/home/joni/gone)\" = gone")
            '';
          }
        )
      ) (lib.filterAttrs (_: host: host.system == system) hosts);
    };
}
