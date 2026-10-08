{ lib, ... }:
let
  # Small readers for facts in a nixos-facter report (the parsed JSON, i.e.
  # `config.host-context.facter.report`). Each takes the report and returns
  # `null` when the report is missing or lacks the fact, so callers decide
  # whether that is fatal.
  #
  #   self.lib.facter.ramBytes config.host-context.facter.report
  #
  # Add new readers here rather than digging through `report.hardware` in
  # individual modules; the report's shape is then only known in one place.

  # Installed RAM in bytes. Facter lists "Main Memory" as one entry with a
  # `phys_mem` resource whose `range` is the size in bytes; summing every
  # such resource also covers reports that split memory over several entries.
  # This is what the kernel can use, slightly under the DIMM total.
  ramBytes =
    report:
    let
      memory = if report == null then [ ] else report.hardware.memory or [ ];
      # A list of entries in current reports; older ones have a single entry.
      resources = lib.concatMap (m: m.resources or [ ]) (
        if lib.isList memory then memory else [ memory ]
      );
      sizes = map (r: r.range) (lib.filter (r: (r.type or "") == "phys_mem" && r ? range) resources);
    in
    if sizes == [ ] then null else lib.sum sizes;

  # --- disks ------------------------------------------------------------------
  byId = "/dev/disk/by-id/";
  byPath = "/dev/disk/by-path/";

  # Readable model+serial aliases first, opaque ones (wwn-, nvme-eui.) last,
  # partition aliases never preferred. Shorter wins within a form, which
  # drops the duplicate `..._1` alias nvme drives get.
  alias =
    names:
    let
      pick = prefix: lib.filter (lib.hasPrefix prefix) names;
      ids = pick byId;
      pool = if ids != [ ] then ids else pick byPath;
      key =
        n:
        let
          base = lib.removePrefix (if ids != [ ] then byId else byPath) n;
          form = lib.lists.findFirstIndex (p: lib.hasPrefix p base) 99 [
            "nvme-"
            "ata-"
            "virtio-"
            "mmc-"
            "usb-"
            "scsi-"
          ];
        in
        [
          (
            if lib.hasInfix "-part" base || lib.hasPrefix "wwn-" base || lib.hasPrefix "nvme-eui." base then
              1
            else
              0
          )
          form
          (lib.stringLength base)
          base
        ];
    in
    if pool == [ ] then null else lib.head (lib.sortOn key pool);

  normaliseDisk =
    raw:
    let
      model = raw.model or "";
      classes = raw.class_list or [ ];
      drivers = raw.drivers or [ ];
      has = x: lib.elem x classes || lib.elem x drivers;
      sizes = map (r: r.value_1 * r.value_2) (
        lib.filter (r: (r.type or "") == "size" && (r.unit or "") == "sectors") (raw.resources or [ ])
      );
      virtual =
        has "virtio_blk"
        || has "virtio_scsi"
        || lib.any (s: lib.hasInfix s model) [
          "QEMU"
          "VBOX"
          "VMware"
          "Virtual"
        ];
    in
    {
      id = alias (raw.unix_device_names or [ ]);
      inherit model raw;
      serial = raw.serial or null;
      size = if sizes == [ ] then 0 else lib.head sizes;
      removable =
        has "usb" || has "uas" || (raw.bus_type.name or "") == "USB" || (raw.hotplug or "") == "usb";
      # Facter reports no rotational flag, so this is a heuristic: SATA SSDs
      # that omit "SSD" from their model read as hdd. Callers can pin by serial.
      # One of nvme, ssd, hdd, virtual.
      kind =
        if has "nvme" then
          "nvme"
        else if virtual then
          "virtual"
        else if lib.hasInfix "SSD" model || lib.hasInfix "Solid State" model then
          "ssd"
        else
          "hdd";
    };

  # Whole disks in the report as `{ id, model, serial, size, kind, removable,
  # raw }`: `id` is a stable /dev/disk/ path, `size` is in bytes and `raw` is
  # the facter entry. Disks without a usable path or size are dropped; an
  # absent report has no disks.
  disks =
    report:
    lib.pipe (if report == null then [ ] else report.hardware.disk or [ ]) [
      (lib.filter (
        d:
        lib.elem "disk" (d.class_list or [ ])
        && lib.elem "block_device" (d.class_list or [ ])
        && d ? resources
      ))
      (map normaliseDisk)
      (lib.filter (d: d.id != null && d.size > 0))
    ];
in
{
  flake.lib.facter = {
    inherit ramBytes disks;
  };
}
