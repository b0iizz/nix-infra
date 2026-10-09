# The root wipe of `disko-root-impermanence` (modules/disko-layouts.nix), and a
# VM test that it keeps what it must.
#
#   nix build .#checks.x86_64-linux.impermanence-rollback
{ ... }:
let
  # Runs in the initrd on every boot. `partition` holds the btrfs, `keepDays`
  # is how long retired roots stay in /old_roots.
  rollbackScript =
    { partition, keepDays }:
    ''
      mkdir -p /btrfs-top
      mount -t btrfs -o subvolid=5 ${partition} /btrfs-top

      if [ -e /btrfs-top/root ]; then
        ${
          if keepDays == 0 then
            "btrfs subvolume delete --recursive /btrfs-top/root"
          else
            ''
              # Named and dated after when it was retired (now). The
              # root's own mtime is roughly when it was created, so a
              # root older than the limit would be deleted at once.
              mkdir -p /btrfs-top/old_roots
              stamp=$(date "+%Y-%m-%d_%H:%M:%S")
              mv /btrfs-top/root "/btrfs-top/old_roots/$stamp"
              touch "/btrfs-top/old_roots/$stamp"
            ''
        }
      fi

      if [ -d /btrfs-top/old_roots ]; then
        find /btrfs-top/old_roots -mindepth 1 -maxdepth 1 -mtime +${toString keepDays} |
          while read -r old; do
            btrfs subvolume delete --recursive "$old"
          done
      fi

      btrfs subvolume create /btrfs-top/root
      umount /btrfs-top
    '';
in
{
  flake.lib.impermanence = { inherit rollbackScript; };

  perSystem =
    { pkgs, ... }:
    {
      # The script itself, on a loop-mounted btrfs image: a file in /persist
      # (a sibling subvolume) survives, one in the old root is gone from the
      # new one but kept in /old_roots, a root retired long ago is deleted, and
      # with keepDays = 0 nothing is kept.
      checks.impermanence-rollback = pkgs.testers.runNixOSTest {
        name = "impermanence-rollback";
        nodes.machine =
          { pkgs, ... }:
          {
            environment.systemPackages = with pkgs; [
              btrfs-progs
              findutils
            ];
            environment.etc."rollback-keep".source = pkgs.writeShellScript "rollback-keep" (rollbackScript {
              partition = "/dev/loop7";
              keepDays = 30;
            });
            environment.etc."rollback-drop".source = pkgs.writeShellScript "rollback-drop" (rollbackScript {
              partition = "/dev/loop7";
              keepDays = 0;
            });
          };
        testScript = ''
          machine.succeed(
              "truncate -s 512M /img",
              "mkfs.btrfs -q /img",
              "losetup /dev/loop7 /img",
              "mkdir /top && mount /dev/loop7 /top",
              "btrfs subvolume create /top/root",
              "btrfs subvolume create /top/persist",
              "echo kept > /top/persist/keep",
              "echo gone > /top/root/scratch",
              "mkdir /top/old_roots && btrfs subvolume create /top/old_roots/ancient",
              "touch -d '60 days ago' /top/old_roots/ancient",
              "umount /top",
          )

          machine.succeed("sh /etc/rollback-keep")
          machine.succeed("mount /dev/loop7 -o subvolid=5 /top")
          machine.succeed("test ! -e /top/root/scratch")             # new root is empty
          machine.succeed("test \"$(cat /top/persist/keep)\" = kept") # persist untouched
          machine.succeed("ls /top/old_roots | grep -v ancient")      # old root retired
          machine.succeed("test \"$(cat /top/old_roots/*/scratch)\" = gone")
          machine.succeed("test ! -e /top/old_roots/ancient")        # expired root deleted

          # a second boot with nothing in between leaves the persist alone
          machine.succeed("umount /top && sh /etc/rollback-keep && mount /dev/loop7 -o subvolid=5 /top")
          machine.succeed("test \"$(cat /top/persist/keep)\" = kept")

          # keepDays = 0 keeps no old root
          machine.succeed("echo x > /top/root/scratch2")
          machine.succeed("umount /top && sh /etc/rollback-drop && mount /dev/loop7 -o subvolid=5 /top")
          machine.succeed("test ! -e /top/root/scratch2")
          machine.succeed("test \"$(cat /top/persist/keep)\" = kept")
        '';
      };
    };
}
