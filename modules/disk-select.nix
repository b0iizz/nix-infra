{ lib, self, ... }:
let
  facter = self.lib.facter;
in
{
  # Picks disks for a disko configuration from the host's nixos-facter report.
  #
  #   imports = [ self.modules.nixos.disk-select ];  # or: roles = [ "disk-select" ];
  #
  #   disk-select.want.root = { minSize = "100G"; prefer = "smallest"; };
  #   disk-select.want.data = { minSize = "1T"; kind = [ "hdd" "ssd" ]; };
  #
  #   disko.devices.disk.root.device = config.disk-select.result.root;
  #
  # Every want gets exactly one disk. Wants are served in `priority` order
  # (then by name), each one taking its best-ranked disk *that still leaves
  # every later want satisfiable*, so a greedy early want never starves a
  # later one that had no alternative.
  flake.modules.nixos.disk-select =
    { config, ... }:
    let
      inherit (lib) mkOption types;
      cfg = config.disk-select;

      # --- facter -> disks ----------------------------------------------------
      report = if cfg.reportPath == null then null else lib.importJSON cfg.reportPath;
      disks = facter.disks report;

      # --- wants -> ranked candidates ----------------------------------------
      inherit (self.lib) parseSize;

      speed = {
        nvme = 0;
        ssd = 1;
        virtual = 1;
        hdd = 2;
      };

      rankKey =
        prefer: d:
        (
          {
            fastest = [
              speed.${d.kind}
              (-d.size)
            ];
            largest = [
              (-d.size)
              speed.${d.kind}
            ];
            smallest = [
              d.size
              speed.${d.kind}
            ];
          }
          .${prefer}
        )
        ++ [ d.id ];

      eligible =
        want:
        lib.filter (
          d:
          (want.minSize == null || d.size >= parseSize want.minSize)
          && (want.maxSize == null || d.size <= parseSize want.maxSize)
          && lib.elem d.kind want.kind
          && (want.removable || !d.removable)
          && want.filter d
        ) disks;

      ranked = lib.mapAttrs (_: want: lib.sortOn (rankKey want.prefer) (eligible want)) cfg.want;

      candidates = lib.mapAttrs (_: map (d: d.id)) ranked;

      # Disks a `same` group must agree on. A field name or a `disk -> value`.
      sameKey =
        spec: d:
        if lib.isFunction spec then
          spec d
        else
          {
            size = d.size;
            model = d.model;
            kind = d.kind;
            # facter's vendor is often only a hex id; the model's first word
            # ("Samsung", "WDC", "ST4000DM004-...") is the best readable make.
            vendor = d.raw.vendor.name or (lib.head (lib.splitString " " d.model));
          }
          .${spec};

      # A want's interchangeable groups: eligible disks that agree on every
      # `same` key, best group first, each as a rank-ordered id list. Groups too
      # small for `count` are dropped. Without `same` there is a single group.
      groups = lib.mapAttrs (
        w: want:
        let
          byKey = lib.groupBy (d: builtins.toJSON (map (s: sameKey s d) want.same)) ranked.${w};
        in
        lib.pipe byKey [
          lib.attrValues
          (lib.filter (g: lib.length g >= want.count))
          (lib.sortOn (g: map (rankKey want.prefer) (lib.take want.count g)))
          (map (map (d: d.id)))
        ]
      ) cfg.want;

      order = map (w: w.name) (
        lib.sortOn (w: [
          w.value.priority
          w.name
        ]) (lib.attrsToList cfg.want)
      );

      # --- assignment ---------------------------------------------------------
      # Kuhn's augmenting-path bipartite matching, used only to answer "can
      # these wants still all be given distinct disks?".
      augment =
        cand: w: st:
        lib.foldl' (
          acc: d:
          if acc.ok || acc.seen ? ${d} then
            acc
          else
            let
              seen = acc.seen // {
                ${d} = true;
              };
            in
            if !(acc.owner ? ${d}) then
              {
                ok = true;
                inherit seen;
                owner = acc.owner // {
                  ${d} = w;
                };
              }
            else
              let
                r = augment cand acc.owner.${d} {
                  inherit (acc) owner;
                  inherit seen;
                };
              in
              if r.ok then
                {
                  ok = true;
                  inherit (r) seen;
                  owner = r.owner // {
                    ${d} = w;
                  };
                }
              else
                acc // { inherit (r) seen; }
        ) (st // { ok = false; }) cand.${w};

      # A want needs `count` slots, one per disk. `slots` maps slot name to the
      # disks it could take.
      slotsOf =
        w: n: cands:
        lib.genAttrs (map (i: "${w}/${toString i}") (lib.range 1 n)) (_: cands);

      # Slots for wants not yet placed: any eligible disk, ignoring `same`
      # (a relaxation, so it can only err towards "feasible").
      relaxed = lib.foldl' (acc: w: acc // slotsOf w cfg.want.${w}.count candidates.${w}) { };

      feasible =
        slots: taken:
        let
          cand = lib.mapAttrs (_: lib.filter (d: !(taken ? ${d}))) slots;
        in
        lib.foldl' (
          owner: s:
          if owner == null then
            null
          else
            let
              r = augment cand s {
                inherit owner;
                seen = { };
              };
            in
            if r.ok then r.owner else null
        ) { } (lib.attrNames cand) != null;

      # Depth-first over wants in priority order. A want tries its groups best
      # first; inside a group each disk is taken best first, but only if the
      # wants still to come stay satisfiable. If a later want turns out to have
      # no workable group, the search backs up and tries this want's next group.
      search =
        taken: wants:
        if wants == [ ] then
          { }
        else
          let
            w = lib.head wants;
            rest = lib.tail wants;
            n = cfg.want.${w}.count;

            tryGroup =
              group:
              let
                picked =
                  lib.foldl'
                    (
                      acc: d:
                      if lib.length acc.chosen == n || acc.taken ? ${d} then
                        acc
                      else
                        let
                          taken' = acc.taken // {
                            ${d} = true;
                          };
                          left = n - lib.length acc.chosen - 1;
                        in
                        if feasible (slotsOf w left group // relaxed rest) taken' then
                          {
                            chosen = acc.chosen ++ [ d ];
                            taken = taken';
                          }
                        else
                          acc
                    )
                    {
                      chosen = [ ];
                      inherit taken;
                    }
                    group;
                sub = if lib.length picked.chosen == n then search picked.taken rest else null;
              in
              if sub == null then
                null
              else
                sub
                // {
                  ${w} = picked.chosen;
                };
          in
          lib.foldl' (acc: g: if acc != null then acc else tryGroup g) null groups.${w};

      solution = search { } order;

      describe =
        d:
        "${d.id} (${d.kind}, ${toString (d.size / 1000000000)}GB${lib.optionalString d.removable ", removable"})";

      explain =
        w:
        if report == null then
          "disk-select: no facter report for this host (reportPath is null); cannot place '${w}'"
        else
          "disk-select: cannot place '${w}'.\n"
          + lib.concatMapStringsSep "\n" (
            n:
            "  ${n} needs ${toString cfg.want.${n}.count}, can use: ${toString candidates.${n}}"
            + lib.optionalString (cfg.want.${n}.same != [ ] && candidates.${n} != [ ]) (
              if groups.${n} == [ ] then
                " (but no ${toString cfg.want.${n}.count} of them agree on `same`)"
              else
                " (in ${toString (lib.length groups.${n})} matching group(s))"
            )
          ) order
          + "\n  disks in report: ${toString (map describe disks)}"
          + "\n  (a want may have candidates yet compete with the others for too few disks)";
    in
    {
      # A stable key lets other modules (disko-layouts) import this one without
      # a host that also lists it as a role declaring the options twice.
      key = "disk-select";

      options.disk-select = {
        reportPath = mkOption {
          type = types.nullOr types.path;
          default = config.host-context.facter.reportPath or null;
          defaultText = "the host's registry facter.reportPath";
          description = "nixos-facter report to read disks from.";
        };

        want = mkOption {
          default = { };
          description = "Disks to find, by name. Each gets one distinct disk in `result`.";
          type = types.attrsOf (
            types.submodule {
              options = {
                minSize = mkOption {
                  type = with types; nullOr (either ints.unsigned str);
                  default = null;
                  example = "500G";
                  description = "Bytes, or a string: `500G` (decimal, as disks are sold) or `476GiB` (binary).";
                };
                maxSize = mkOption {
                  type = with types; nullOr (either ints.unsigned str);
                  default = null;
                  description = "Upper size bound, same format as `minSize`.";
                };
                kind = mkOption {
                  type = with types; listOf (enum (lib.attrNames speed));
                  default = lib.attrNames speed;
                  description = ''
                    Accepted kinds. `ssd` vs `hdd` is a model-name heuristic (facter
                    has no rotational flag); `virtual` is a QEMU/virtio disk.
                  '';
                };
                prefer = mkOption {
                  type = types.enum [
                    "fastest"
                    "largest"
                    "smallest"
                  ];
                  default = "fastest";
                  description = ''
                    Ranking among eligible disks. `fastest` is nvme, then ssd, then
                    hdd, larger first. `smallest` suits a root disk: the smallest
                    one that still meets `minSize`.
                  '';
                };
                removable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Allow USB / hotplug disks. Off, so an install never erases the stick it booted from.";
                };
                filter = mkOption {
                  type = with types; functionTo bool;
                  default = _: true;
                  example = lib.literalExpression ''d: d.serial == "S69ENX0W111110A"'';
                  description = ''
                    Extra hard constraint on a disk `{ id, model, serial, size, kind, removable, raw }`
                    where `raw` is the facter entry. Pin to hardware with `serial`.
                  '';
                };
                count = mkOption {
                  type = types.ints.positive;
                  default = 1;
                  description = "How many disks to select, e.g. for a RAID array. With more than one, `result` is a list.";
                };
                same = mkOption {
                  type =
                    with types;
                    listOf (
                      either (enum [
                        "size"
                        "model"
                        "kind"
                        "vendor"
                      ]) (functionTo raw)
                    );
                  default = [ ];
                  example = [
                    "vendor"
                    "size"
                  ];
                  description = ''
                    Properties all selected disks must share, so `count` disks come
                    from one group of look-alikes. Use `[ "size" ]` for equal
                    capacity, `[ "model" ]` for identical drives, `[ "vendor" ]`
                    for the same make (first word of the model unless facter names
                    the vendor). A `disk -> value` function groups by anything,
                    e.g. `d: d.size / 100000000000` for sizes within a bucket.
                  '';
                };
                priority = mkOption {
                  type = types.int;
                  default = 0;
                  description = "Lower is served first when wants compete for the same disk; ties by name.";
                };
              };
            }
          );
        };

        result = mkOption {
          type = with types; lazyAttrsOf (either str (listOf str));
          readOnly = true;
          description = ''
            Want name to `/dev/disk/by-id/...` path, or a list of paths when
            `count` is above 1. Evaluating a want that can't be satisfied throws,
            listing what each want could use.
          '';
        };
      };

      config.disk-select.result = lib.genAttrs (lib.attrNames cfg.want) (
        w:
        let
          chosen = if solution == null then null else solution.${w} or null;
        in
        if chosen == null then
          throw (explain w)
        else if cfg.want.${w}.count == 1 then
          lib.head chosen
        else
          chosen
      );
    };
}
