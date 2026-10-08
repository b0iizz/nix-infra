{ lib, self, ... }:
let
  # Bytes from an int (as is) or a string: `500G` is decimal, as disks are
  # sold (500 * 1000^3), `476GiB` binary (476 * 1024^3). `B` is optional.
  parseSize =
    s:
    if lib.isInt s then
      s
    else
      let
        m = builtins.match "([0-9]+)[[:space:]]*([KMGT]?)(i?)B?" s;
        exp = {
          "" = 0;
          K = 1;
          M = 2;
          G = 3;
          T = 4;
        };
        base = if lib.elemAt m 2 == "i" then 1024 else 1000;
      in
      if m == null then
        throw "cannot parse size '${s}'; expected e.g. 500G (decimal), 476GiB (binary) or bytes"
      else
        lib.toInt (lib.elemAt m 0) * self.lib.pow base exp.${lib.elemAt m 1};
in
{
  flake.lib.parseSize = parseSize;
}
