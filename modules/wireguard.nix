{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib)
    all
    any
    attrNames
    attrValues
    concatMap
    filter
    filterAttrs
    flatten
    foldr
    genAttrs
    length
    mapAttrs
    mapAttrs'
    mkDefault
    mkIf
    mkOption
    nameValuePair
    optionalAttrs
    pathExists
    stringLength
    types
    unique
    ;

  rcfg = config.registry;
  cfg = config.wireguard;
  ip = self.lib.ip;

  pow2 = self.lib.pow 2;

  # Name of the agenix-rekey secret holding a host's private key for a
  # network. Generated secrets of all hosts share one directory, so the
  # name has to be unique across hosts.
  secretName = host: net: "wireguard-${host}-${net}";

  # The generator of the key (below) writes the public key next to the
  # generated secret as `<secret>.pub`.
  generatedPublicKey =
    host: net:
    let
      file = rcfg.secretsDir + "/generated/${secretName host net}.pub";
    in
    if pathExists file then lib.fileContents file else null;

  memberType =
    { netName, net }:
    types.submodule (
      { name, ... }:
      {
        options = {

          index = mkOption {
            type = types.nullOr types.ints.unsigned;
            default = null;
            description = ''
              Offset of this member's address inside the network prefix.
              Members without an index get one derived from a hash of the
              network and host name, so it does not depend on the other
              members. Only a hash collision with another member can move
              an address when members are added or removed; set `index`
              to rule even that out.
            '';
          };

          ipv4 = mkOption {
            type = types.nullOr ip.types.ipv4;
            default = null;
            description = "Explicit IPv4 address inside the network prefix, overriding `index`.";
          };

          ipv6 = mkOption {
            type = types.nullOr ip.types.ipv6;
            default = null;
            description = "Explicit IPv6 address inside the network prefix, overriding `index`.";
          };

          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "vpn.example.org";
            description = ''
              Host name or IP (without port) other members use to reach
              this one. Members without an endpoint can only initiate.
            '';
          };

          endpointPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Port peers connect to. Defaults to `listenPort`, then the network's `port`.";
          };

          listenPort = mkOption {
            type = types.nullOr types.port;
            default = if net.topology == "hub-and-spoke" && net.hub != name then null else net.port;
            description = ''
              UDP port to listen on. `null` picks a random port and does
              not open the firewall; that is the default for spokes.
            '';
          };

          persistentKeepalive = mkOption {
            type = types.nullOr types.ints.unsigned;
            default =
              if net.topology == "hub-and-spoke" && net.hub != name then net.persistentKeepalive else null;
            description = "Keepalive interval this member sends to its peers.";
          };

          peers = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            example = [ "gateway" ];
            description = ''
              The members this one has a peer for; `null` means all of them.
              WireGuard needs both ends, so a member left out cannot talk to
              this one, and what it sends is dropped. Meshes only; in a
              hub-and-spoke network spokes peer with the hub.
            '';
          };

          routes = mkOption {
            type = types.listOf ip.types.cidr;
            default = [ ];
            description = ''
              Extra prefixes reachable through this member, for example a
              LAN behind it. Peers route them through this member; in a
              hub-and-spoke network the hub relays them to the other spokes.
            '';
          };

          publicKey = mkOption {
            type = types.nullOr types.str;
            default = generatedPublicKey name netName;
            defaultText = "contents of secrets/generated/wireguard-<host>-<network>.pub if it exists";
            description = ''
              Public key of this member. The private key is generated and
              stored with agenix-rekey (`agenix generate`), which also
              writes the matching `.pub` file that is picked up here.
            '';
          };

        };
      }
    );

  networkType = types.submodule (
    { name, config, ... }:
    {
      options = {

        topology = mkOption {
          type = types.enum [
            "mesh"
            "hub-and-spoke"
          ];
          default = "mesh";
          description = ''
            `mesh`: every member peers with every other member.
            `hub-and-spoke`: spokes only peer with the hub, which relays
            traffic between them.
          '';
        };

        hub = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Name of the hub host. Required for, and only valid with, `hub-and-spoke`.";
        };

        interface = mkOption {
          type = types.str;
          default = "wg-${name}";
          description = "Interface name (at most 15 characters).";
        };

        port = mkOption {
          type = types.port;
          default = 51820;
        };

        ipv4 = mkOption {
          type = types.nullOr ip.types.ipv4Cidr;
          default = null;
          example = "10.100.0.0/24";
        };

        ipv6 = mkOption {
          type = types.nullOr ip.types.ipv6Cidr;
          default = null;
          example = "fd00:100::/64";
        };

        mtu = mkOption {
          type = types.nullOr types.ints.positive;
          default = null;
        };

        persistentKeepalive = mkOption {
          type = types.nullOr types.ints.unsigned;
          default = 25;
          description = "Default keepalive of spokes towards the hub.";
        };

        firstIndex = mkOption {
          type = types.nullOr types.ints.unsigned;
          default = null;
          description = ''
            Lowest index that can be assigned. Defaults to 1 (keeping the
            network address free), or 0 for point-to-point prefixes (/31, /127).
          '';
        };

        members = mkOption {
          type = types.attrsOf (memberType {
            netName = name;
            net = config;
          });
          default = { };
          description = "Hosts of this network, named as in `registry.hosts`.";
        };

      };
    }
  );

  linkType = types.submodule (
    { ... }:
    {
      options = {

        hosts = mkOption {
          type = types.listOf types.str;
          example = [
            "alpha"
            "beta"
          ];
          description = "The two hosts joined by this link.";
        };

        interface = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Interface name; defaults to `wg-<link name>`.";
        };

        port = mkOption {
          type = types.port;
          default = 51820;
        };

        ipv4 = mkOption {
          type = types.nullOr ip.types.ipv4Cidr;
          default = null;
          example = "10.200.0.0/31";
        };

        ipv6 = mkOption {
          type = types.nullOr ip.types.ipv6Cidr;
          default = null;
          example = "fd00:200::/127";
        };

        mtu = mkOption {
          type = types.nullOr types.ints.positive;
          default = null;
        };

        members = mkOption {
          type = types.attrsOf (types.attrsOf types.raw);
          default = { };
          example = {
            beta.endpoint = "beta.example.org";
          };
          description = "Per-host member settings, see `wireguard.networks.<name>.members`.";
        };

      };
    }
  );

  # -- resolution --------------------------------------------------------------

  resolveNetwork =
    netName: net:
    let
      memberNames = attrNames net.members;
      prefixes = map ip.parseCidr (
        lib.remove null [
          net.ipv4
          net.ipv6
        ]
      );

      firstIndex =
        if net.firstIndex != null then
          net.firstIndex
        else if all (c: ip.hostBits c <= 1) prefixes then
          0
        else
          1;

      # Usable indices are firstIndex .. 2^hostBits - 1, minus the IPv4
      # broadcast address. Host bits are capped to keep the arithmetic small.
      capacity = lib.foldl' lib.min (pow2 31) (
        map (
          c:
          let
            bits = lib.min 31 (ip.hostBits c);
            broadcast = if c.family == 4 && bits > 1 then 1 else 0;
          in
          pow2 bits - firstIndex - broadcast
        ) prefixes
      );

      pinned = filterAttrs (_: v: v != null) (mapAttrs (_: m: m.index) net.members);
      # Slot s is index firstIndex + s.
      slots = self.lib.stableSlots {
        salt = netName;
        inherit capacity;
        keys = memberNames;
        pinned = mapAttrs (_: i: i - firstIndex) pinned;
      };
      indexOf = mapAttrs (_: s: s + firstIndex) slots;

      checks = [
        {
          cond = prefixes != [ ];
          msg = "at least one of `ipv4` and `ipv6` must be set";
        }
        {
          cond = length memberNames >= 2;
          msg = "needs at least two members";
        }
        {
          cond = stringLength net.interface <= 15;
          msg = "interface name '${net.interface}' is longer than 15 characters";
        }
        {
          cond = all (n: rcfg.hosts ? ${n}) memberNames;
          msg = "unknown host(s) ${toString (filter (n: !(rcfg.hosts ? ${n})) memberNames)}";
        }
        {
          cond = length (unique (attrValues indexOf)) == length memberNames;
          msg = "member indices are not unique";
        }
        {
          cond =
            if net.topology == "hub-and-spoke" then
              net.hub != null && net.members ? ${net.hub}
            else
              net.hub == null;
          msg = "`hub` must name a member for hub-and-spoke networks and be unset for meshes";
        }
        {
          cond = net.topology != "hub-and-spoke" || net.members.${net.hub}.endpoint != null;
          msg = "the hub ${toString net.hub} needs an `endpoint`, or no spoke can reach it";
        }
        {
          # Explicit `ipv4`/`ipv6` addresses don't reserve their index.
          cond = length (unique addresses) == length addresses;
          msg = "two members have the same address: ${
            toString (unique (filter (a: lib.count (b: b == a) addresses > 1) addresses))
          }";
        }
      ];

      members = mapAttrs resolveMember net.members;
      addresses = concatMap (m: m.hostRoutes) (attrValues members);

      resolveMember =
        host: m:
        let
          pick =
            prefix: explicit:
            if prefix == null then
              (
                if explicit != null then
                  throw "wireguard network '${netName}': ${host} has an address of a family the network does not use"
                else
                  null
              )
            else if explicit != null then
              (
                if ip.contains prefix explicit then
                  ip.parse explicit
                else
                  throw "wireguard network '${netName}': ${explicit} of ${host} is outside ${prefix}"
              )
            else
              ip.hostAddress prefix indexOf.${host};
          addresses = lib.remove null [
            (pick net.ipv4 m.ipv4)
            (pick net.ipv6 m.ipv6)
          ];
          prefixLengthOf =
            a: (if a.family == 4 then ip.parseCidr net.ipv4 else ip.parseCidr net.ipv6).prefixLength;
        in
        {
          inherit host;
          inherit (m)
            publicKey
            listenPort
            persistentKeepalive
            peers
            ;
          ips = map (a: "${ip.format a}/${toString (prefixLengthOf a)}") addresses;
          addresses = map ip.format addresses;
          hostRoutes = map ip.hostCidr addresses;
          extraRoutes = m.routes;
          endpoint =
            if m.endpoint == null then
              null
            else
              ip.formatEndpoint m.endpoint (
                if m.endpointPort != null then
                  m.endpointPort
                else if m.listenPort != null then
                  m.listenPort
                else
                  net.port
              );
        };
    in
    foldr (c: acc: if c.cond then acc else throw "wireguard network '${netName}': ${c.msg}") {
      inherit (net)
        topology
        hub
        interface
        mtu
        ;
      name = netName;
      prefixes = map (c: ip.formatCidr (ip.networkOf c)) prefixes;
      hasIPv4 = net.ipv4 != null;
      hasIPv6 = net.ipv6 != null;
      inherit members;
    } checks;

  resolved = mapAttrs resolveNetwork cfg.networks;

  # Everything one host needs to know, keyed by network name.
  interfacesFor =
    host:
    let
      me = host.hostName;
      mine = filterAttrs (_: n: n.members ? ${me}) resolved;
    in
    mapAttrs (
      netName: n:
      let
        self' = n.members.${me};
        isSpoke = n.topology == "hub-and-spoke" && n.hub != me;
        others = filterAttrs (h: _: h != me && rcfg.hosts.${h}.enable) n.members;
        targets =
          if isSpoke then
            filterAttrs (h: _: h == n.hub) others
          else if self'.peers != null then
            filterAttrs (h: _: lib.elem h self'.peers) others
          else
            others;
        allowedIPs =
          other:
          if isSpoke then
            # The hub relays everything else.
            n.prefixes ++ concatMap (m: m.extraRoutes) (attrValues (removeAttrs n.members [ me ]))
          else
            other.hostRoutes ++ other.extraRoutes;
      in
      {
        inherit (n) mtu hasIPv4 hasIPv6;
        interface = n.interface;
        secretName = secretName me netName;
        addresses = self'.ips;
        inherit (self') listenPort publicKey;
        isHub = n.topology == "hub-and-spoke" && n.hub == me;
        peers = map (other: {
          name = other.host;
          inherit (other) publicKey endpoint;
          persistentKeepalive = self'.persistentKeepalive;
          allowedIPs = allowedIPs other;
        }) (attrValues targets);
      }
    ) mine;
in
{
  options.wireguard = {

    networks = mkOption {
      type = types.attrsOf networkType;
      default = { };
      description = "WireGuard networks spanning several hosts.";
      example = {
        corp = {
          topology = "hub-and-spoke";
          hub = "gateway";
          ipv4 = "10.100.0.0/24";
          ipv6 = "fd00:100::/64";
          members = {
            gateway.endpoint = "vpn.example.org";
            laptop = { };
            server = { };
          };
        };
      };
    };

    resolved = mkOption {
      type = types.raw;
      readOnly = true;
      default = resolved;
      description = ''
        Resolved networks, including the addresses of every member. For
        modules that need to know where another host is reachable.
      '';
    };

    links = mkOption {
      type = types.attrsOf linkType;
      default = { };
      description = ''
        Point-to-point links between two hosts. Sugar for a two member
        mesh in `networks` under the same name.
      '';
    };

  };

  config = {

    wireguard.networks = mapAttrs (
      name: l:
      {
        topology = "mesh";
        inherit (l)
          ipv4
          ipv6
          port
          mtu
          ;
        members = genAttrs l.hosts (h: l.members.${h} or { });
      }
      // optionalAttrs (l.interface != null) { inherit (l) interface; }
    ) cfg.links;

    registry.extraHostArgs.wireguard = host: { interfaces = interfacesFor host; };

    flake.modules.nixos.base.imports = [ self.modules.nixos.wireguard ];

    # Receiver. Relies on the agenix-rekey setup of the `secrets` module.
    flake.modules.nixos.wireguard =
      { config, wireguard, ... }:
      let
        ifaces = wireguard.interfaces;
        list = attrValues ifaces;
        ports = lib.remove null (map (i: i.listenPort) list);
        hubs = filter (i: i.isHub) list;
        unkeyed = flatten (
          map (i: map (p: "${i.interface}: ${p.name}") (filter (p: p.publicKey == null) i.peers)) list
        );
      in
      {
        config = mkIf (ifaces != { }) {

          assertions = [
            {
              assertion = length (unique (map (i: i.interface) list)) == length list;
              message = "wireguard: two networks use the same interface name on ${config.networking.hostName}";
            }
            {
              assertion = length (unique ports) == length ports;
              message = "wireguard: two networks listen on the same UDP port on ${config.networking.hostName}";
            }
            {
              assertion = unkeyed == [ ];
              message = ''
                wireguard: missing public key for ${toString unkeyed}.
                Run `agenix generate` and commit secrets/generated/wireguard-*.pub, or set `publicKey`.
              '';
            }
          ];

          # Private keys are generated by the script below (which also writes the
          # `.pub` file; agenix-rekey has no wireguard generator) and rekeyed per host.
          age.secrets = mapAttrs' (
            _: i:
            nameValuePair i.secretName {
              generator.script =
                {
                  lib,
                  pkgs,
                  file,
                  ...
                }:
                ''
                  key=$(${pkgs.wireguard-tools}/bin/wg genkey)
                  ${pkgs.wireguard-tools}/bin/wg pubkey <<<"$key" >${lib.escapeShellArg "${lib.removeSuffix ".age" file}.pub"}
                  echo "$key"
                '';
              mode = "0400";
            }
          ) ifaces;

          networking.wireguard.interfaces = mapAttrs' (
            _: i:
            nameValuePair i.interface {
              ips = i.addresses;
              inherit (i) listenPort mtu;
              privateKeyFile = config.age.secrets.${i.secretName}.path;
              peers = map (p: {
                inherit (p)
                  name
                  publicKey
                  endpoint
                  persistentKeepalive
                  allowedIPs
                  ;
              }) (filter (p: p.publicKey != null) i.peers);
            }
          ) ifaces;

          networking.firewall.allowedUDPPorts = ports;

          # With `filterForward` the hub would drop what it relays between
          # peers; only allow traffic that stays inside the same interface.
          # (filterForward itself requires the nftables firewall.)
          networking.firewall.extraForwardRules =
            mkIf (config.networking.firewall.filterForward && hubs != [ ])
              (
                lib.concatMapStringsSep "\n" (
                  i: ''iifname "${i.interface}" oifname "${i.interface}" accept comment "wireguard hub relay"''
                ) hubs
              );

          boot.kernel.sysctl = {
            "net.ipv4.ip_forward" = mkIf (any (i: i.hasIPv4) hubs) (mkDefault 1);
            "net.ipv6.conf.all.forwarding" = mkIf (any (i: i.hasIPv6) hubs) (mkDefault 1);
          };

        };
      };

  };
}
