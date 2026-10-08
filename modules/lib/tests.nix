# Unit tests for the parts of `self.lib` that silently break things when
# they change: the IP parser behind every address option, the slot hash that
# keeps WireGuard addresses stable, and the size parser for disks and swap.
#
#   nix build .#checks.x86_64-linux.lib
{ lib, self, ... }:
let
  inherit (self.lib) ip stableSlots parseSize;

  fails = x: !(builtins.tryEval (builtins.deepSeq x x)).success;
  fmt = s: ip.format (ip.parse s);

  slots =
    keys:
    stableSlots {
      salt = "net";
      capacity = 254;
      inherit keys;
    };

  tests = {
    # -- ip ----------------------------------------------------------------
    testIPv6Compress = {
      # Longest zero run wins, the leftmost on ties (RFC 5952).
      expr = map fmt [
        "2001:DB8:0:0:1:0:0:1"
        "2001:db8:0:0:0:1:0:0"
        "::"
        "1:0:0:0:0:0:0:0"
        "::ffff:1.2.3.4"
      ];
      expected = [
        "2001:db8::1:0:0:1"
        "2001:db8::1:0:0"
        "::"
        "1::"
        "::ffff:102:304"
      ];
    };
    testInvalidRejected = {
      expr = map (s: fails (ip.parse s)) [
        "256.1.1.1"
        "01.2.3.4"
        "1.2.3"
        "1::2::3"
        "1:2:3:4:5:6:7:8:9"
        "1.2.3.4::1"
        ":::"
        ""
      ];
      expected = lib.genList (_: true) 8;
    };
    testCidr = {
      expr = [
        (ip.formatCidr (ip.networkOf (ip.parseCidr "10.1.2.3/16")))
        (ip.formatCidr (ip.networkOf (ip.parseCidr "fd00:1:2:3::9/48")))
        (fails (ip.parseCidr "10.0.0.0/33"))
      ];
      expected = [
        "10.1.0.0/16"
        "fd00:1:2::/48"
        true
      ];
    };
    testHostAddress = {
      expr = [
        (ip.format (ip.hostAddress "10.0.0.0/24" 5))
        (ip.format (ip.hostAddress "10.0.0.0/23" 300))
        (ip.format (ip.hostAddress "fd00::/64" 65536))
        (fails (ip.hostAddress "10.0.0.0/24" 256))
      ];
      expected = [
        "10.0.0.5"
        "10.0.1.44"
        "fd00::1:0"
        true
      ];
    };
    testContains = {
      expr = [
        (ip.contains "fd00::/64" "fd00::1")
        (ip.contains "10.0.0.0/8" "11.0.0.1")
        (ip.contains "10.0.0.0/8" "fd00::1")
      ];
      expected = [
        true
        false
        false
      ];
    };
    testEndpoint = {
      expr = [
        (ip.formatEndpoint "::1" 51820)
        (ip.formatEndpoint "10.0.0.1" 51820)
        (ip.formatEndpoint "vpn.example.org" 51820)
      ];
      expected = [
        "[::1]:51820"
        "10.0.0.1:51820"
        "vpn.example.org:51820"
      ];
    };

    # -- stableSlots ---------------------------------------------------------
    # The point of the hash: other members keep their address.
    testSlotsStableOnAdd = {
      expr = removeAttrs (slots [
        "alpha"
        "beta"
        "gamma"
        "delta"
      ]) [ "delta" ];
      expected = slots [
        "alpha"
        "beta"
        "gamma"
      ];
    };
    testSlotsIndependentOfOrder = {
      expr = slots [
        "gamma"
        "alpha"
        "beta"
      ];
      expected = slots [
        "alpha"
        "beta"
        "gamma"
      ];
    };
    testSlotsPinned = {
      expr =
        (stableSlots {
          salt = "net";
          capacity = 254;
          keys = [
            "alpha"
            "beta"
          ];
          pinned.alpha = 7;
        }).alpha;
      expected = 7;
    };
    testSlotsFull = {
      # A full space still terminates and hands out every slot once.
      expr = lib.sort (a: b: a < b) (
        lib.attrValues (stableSlots {
          salt = "net";
          capacity = 5;
          keys = [
            "a"
            "b"
            "c"
            "d"
            "e"
          ];
        })
      );
      expected = [
        0
        1
        2
        3
        4
      ];
    };
    testSlotsOverfull = {
      expr = fails (stableSlots {
        salt = "net";
        capacity = 1;
        keys = [
          "a"
          "b"
        ];
      });
      expected = true;
    };

    # -- parseSize -----------------------------------------------------------
    testParseSize = {
      expr = map parseSize [
        42
        "512"
        "500G"
        "476GiB"
        "8 MiB"
        "1TB"
      ];
      expected = [
        42
        512
        500000000000
        (476 * 1024 * 1024 * 1024)
        (8 * 1024 * 1024)
        1000000000000
      ];
    };
    testParseSizeRejects = {
      expr = map (s: fails (parseSize s)) [
        "1.5T"
        "8g"
        "G"
      ];
      expected = [
        true
        true
        true
      ];
    };
  };
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.lib =
        let
          failed = lib.runTests tests;
        in
        pkgs.runCommand "check-lib" { } (
          if failed == [ ] then
            "touch $out"
          else
            ''
              echo ${lib.escapeShellArg (lib.generators.toPretty { } failed)} >&2
              exit 1
            ''
        );
    };
}
