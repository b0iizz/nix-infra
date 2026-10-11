# Expose services of hosts without a public address (origins, e.g. a
# homelab behind CGNAT) through hosts that have one (gateways, e.g. a VPS).
#
# Origins dial out to every gateway over a WireGuard network this module
# defines. Gateways terminate TLS and reverse proxy HTTP to the origins, or
# forward plain TCP/UDP ports.
#
# Once, at flake level:
#
#   publicProxy = {
#     zones."example.com" = { };
#     zones."example.net" = { };
#     defaultZone = "example.com"; # automatic with a single zone
#     gateways.vps.ipv4 = "203.0.113.5";
#     origins = [ "homelab" ];
#   };
#
# Per service, in any NixOS module of an origin, next to the service itself:
#
#   publicProxy.expose.jellyfin = {
#     subdomain = "media"; # media.example.com
#     domains = [ "media.example.net" ];
#     port = 8096;
#   };
#
# Gateways read `publicProxy.expose` of every origin from its evaluated
# configuration, so adding a service only touches the origin. Reads only go
# from gateway to origin; origins never look at the aggregate.
#
# This file is the glue: it resolves services into backend-neutral routes,
# validates them, derives DNS records (plus `extraRecords`), sets up the tunnel and the parts of
# a gateway every backend shares (firewall, Let's Encrypt). The rest of
# this directory plugs into it:
#
# - Backends (nginx.nix) register in `publicProxy.backends.<name>`:
#
#     { user; group;            # the proxy runs as, may read certificates
#       unit;                   # its systemd service
#       logFile = id: path;     # per service access log, for fail2ban
#       config = { routes, tlsFor, acmeWebroot }: <NixOS config>; }
#
#   A route (`resolveService`) carries `id`, `protocol`, `domains`,
#   `publicPort`, `upstream.{host,port,address,url}`, `websockets`,
#   `maxBodySize`, `proxyProtocol`, `realIp` (null or `{ header; from; }`)
#   and the service's own settings in `service` (e.g. `service.nginx`).
#   `tlsFor route` is `{ acmeCert = <security.acme.certs name>; }` or
#   `{ certificate; key; }`. With HTTP-01 the backend serves
#   /.well-known/acme-challenge/ from `acmeWebroot` on port 80 and reloads
#   itself after renewals.
#
# - Features (cloudflare.nix, ban-list.nix) add fields to the `publicProxy`
#   module argument (`internal.hostData`), configuration errors
#   (`internal.problems`) and NixOS modules to `flake.modules.nixos.public-proxy`.
#   On gateways, Cloudflare origin certificates are taken from the NixOS
#   option `publicProxy.internal.originCertificates.<zone>`.
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib)
    all
    attrNames
    attrValues
    concatLists
    concatMap
    elem
    filter
    filterAttrs
    genAttrs
    hasSuffix
    head
    length
    listToAttrs
    mapAttrs
    mapAttrs'
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optional
    optionalAttrs
    optionals
    removeSuffix
    stringLength
    subtractLists
    tail
    types
    unique
    ;

  rcfg = config.registry;
  cfg = config.publicProxy;
  ip = self.lib.ip;

  tlsModes = [
    "acme"
    "cloudflare-origin"
  ];

  # -- types -------------------------------------------------------------------

  gatewayType = types.submodule (
    { config, ... }:
    {
      options = {

        ipv4 = mkOption {
          type = types.nullOr ip.types.ipv4;
          default = null;
          description = "Public IPv4 address, used for DNS records.";
        };

        ipv6 = mkOption {
          type = types.nullOr ip.types.ipv6;
          default = null;
          description = "Public IPv6 address, used for DNS records.";
        };

        endpoint = mkOption {
          type = types.nullOr types.str;
          default = if config.ipv4 != null then config.ipv4 else config.ipv6;
          defaultText = "`ipv4`, else `ipv6`";
          description = "Host name or address origins dial to reach this gateway's tunnel.";
        };

      };
    }
  );

  zoneType = types.submodule {
    options = {

      wildcard = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Request one certificate for the zone and `*.<zone>` per gateway
          instead of one per service. Needs the DNS challenge.
        '';
      };

    };
  };

  # Declared on every NixOS host as `publicProxy.expose.<name>`.
  serviceType = types.submodule (
    { config, ... }:
    {
      options = {

        enable = mkOption {
          type = types.bool;
          default = true;
        };

        protocol = mkOption {
          type = types.enum [
            "http"
            "tcp"
            "udp"
          ];
          default = "http";
          description = ''
            `http`: TLS terminated and reverse proxied by the gateway.
            `tcp`/`udp`: `publicPort` of the gateway forwarded as is.
          '';
        };

        subdomain = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "media";
          description = "Name below `zone`; `@` is the zone itself.";
        };

        zone = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "example.net";
          description = "Zone `subdomain` is relative to; `null` means `publicProxy.defaultZone`.";
        };

        domains = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Fully qualified names, in addition to `subdomain`. The first
            name (`subdomain` if set) is the primary one.
          '';
        };

        port = mkOption {
          type = types.port;
          description = "Port the service listens on, on the origin.";
        };

        publicPort = mkOption {
          type = types.port;
          default = config.port;
          defaultText = "`port`";
          description = "Port opened on the gateways (tcp/udp only; http is always 443).";
        };

        upstreamScheme = mkOption {
          type = types.enum [
            "http"
            "https"
          ];
          default = "http";
          description = "What the origin speaks on `port` (http only).";
        };

        gateways = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = "Gateways serving this service; `null` means all of them.";
        };

        websockets = mkOption {
          type = types.bool;
          default = true;
        };

        maxBodySize = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "10G";
          description = "Largest request body accepted; `null` keeps the backend default.";
        };

        proxyProtocol = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Send the PROXY protocol header to the origin (tcp/udp only), so
            the service learns the client address. It has to support it.
          '';
        };

        tls = mkOption {
          type = types.nullOr (types.enum tlsModes);
          default = null;
          description = "Certificate source; `null` uses `publicProxy.tls.mode`.";
        };

        dns = {

          manage = mkOption {
            type = types.bool;
            default = true;
            description = "Whether `publicProxy.records` contains records for this service.";
          };

          cloudflareProxied = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Whether the records go through Cloudflare's proxy (orange
              cloud). `null` means yes exactly for http services using a
              Cloudflare origin certificate, which only Cloudflare trusts.
              Proxied services get the real client address from Cloudflare.
            '';
          };

          srv = mkOption {
            type = types.nullOr (
              types.submodule {
                options = {
                  service = mkOption {
                    type = types.str;
                    example = "minecraft";
                  };
                  domain = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Name the SRV record is placed under; `null` means the primary domain, the name clients look it up for.";
                  };
                  priority = mkOption {
                    type = types.ints.unsigned;
                    default = 0;
                  };
                  weight = mkOption {
                    type = types.ints.unsigned;
                    default = 0;
                  };
                };
              }
            );
            default = null;
            description = ''
              SRV record `_<service>._<protocol>.<domain>` pointing at the
              primary domain and `publicPort` (tcp/udp only).
            '';
          };

        };

      };
    }
  );

  # -- resolution --------------------------------------------------------------

  net = config.wireguard.resolved.${cfg.tunnel.network} or null;
  tunnelUp = cfg.gateways != { } && cfg.origins != [ ];

  # All tunnel addresses of a member, IPv4 first.
  addressesOf =
    host: if net == null || !(net.members ? ${host}) then [ ] else net.members.${host}.addresses;

  exposedBy =
    origin:
    filterAttrs (_: s: s.enable) (
      config.flake.nixosConfigurations.${origin}.config.publicProxy.expose or { }
    );

  allGateways = attrNames cfg.gateways;

  # The most specific declared zone a name belongs to, or null.
  zoneOf =
    d:
    let
      matching = filter (z: d == z || hasSuffix ".${z}" d) (attrNames cfg.zones);
    in
    if matching == [ ] then null else lib.last (lib.sortOn stringLength matching);

  # A name the wildcard certificate of `zone` is valid for.
  wildcardCovers =
    zone: d: d == zone || (hasSuffix ".${zone}" d && !(lib.hasInfix "." (removeSuffix ".${zone}" d)));

  resolveService =
    origin: name: s:
    let
      id = "${origin}-${name}";
      tlsMode = if s.tls != null then s.tls else cfg.tls.mode;
      host = head (addressesOf origin ++ [ (throw "public-proxy: ${origin} has no tunnel address") ]);
      address = ip.formatEndpoint host s.port;
      subdomainZone = if s.zone != null then s.zone else cfg.defaultZone;
      fromSubdomain =
        if s.subdomain == null || subdomainZone == null then
          [ ]
        else if s.subdomain == "@" then
          [ subdomainZone ]
        else
          [ "${s.subdomain}.${subdomainZone}" ];
      domains = unique (fromSubdomain ++ s.domains);
      domainZones = unique (map zoneOf domains);
      # The zone all domains share, if they do.
      zone = if length domainZones == 1 then head domainZones else null;
      wildcard = zone != null && cfg.zones.${zone}.wildcard && all (wildcardCovers zone) domains;
      cloudflareProxied =
        if s.dns.cloudflareProxied != null then
          s.dns.cloudflareProxied
        else
          s.protocol == "http" && tlsMode == "cloudflare-origin";
    in
    {
      inherit
        id
        name
        origin
        tlsMode
        domains
        zone
        subdomainZone
        cloudflareProxied
        ;
      # Backend-neutral certificate choice, see `tlsFor` in the NixOS module.
      cert =
        if tlsMode == "cloudflare-origin" then
          {
            kind = "cloudflare-origin";
            inherit zone;
            # Names the zone's wildcard doesn't cover.
            extraNames = if zone == null then [ ] else filter (d: !(wildcardCovers zone d)) domains;
          }
        else
          {
            kind = "acme";
            inherit wildcard;
            name = if wildcard then zone else head domains;
          };
      inherit (s)
        protocol
        websockets
        maxBodySize
        proxyProtocol
        ;
      service = s;
      publicPort = if s.protocol == "http" then 443 else s.publicPort;
      gateways = if s.gateways == null then allGateways else s.gateways;
      upstream = {
        inherit host address;
        inherit (s) port;
        url = "${s.upstreamScheme}://${address}";
      };
      # Where the client address comes from, if not from the connection.
      realIp =
        if cloudflareProxied then
          {
            header = "CF-Connecting-IP";
            from = cfg.cloudflare.ipRanges;
          }
        else
          null;
    };

  services = concatMap (
    origin: mapAttrsToList (resolveService origin) (exposedBy origin)
  ) cfg.origins;

  routesOf = gw: filter (r: elem gw r.gateways) services;

  duplicates = xs: attrNames (filterAttrs (_: g: length g > 1) (lib.groupBy toString xs));

  problems =
    let
      check = cond: msg: optional (!cond) msg;
      perService =
        r:
        let
          uses = mode: r.protocol == "http" && r.tlsMode == mode;
        in
        concatLists [
          (check (
            subtractLists allGateways r.gateways == [ ]
          ) "${r.id}: unknown gateway(s) ${toString (subtractLists allGateways r.gateways)}")
          (check (r.gateways != [ ]) "${r.id}: is served by no gateway")
          (check (
            r.protocol != "http" || r.domains != [ ]
          ) "${r.id}: http services need `subdomain` or `domains`")
          (check (
            !r.cloudflareProxied || r.protocol == "http"
          ) "${r.id}: Cloudflare only proxies http services")
          (check (
            r.service.subdomain == null || r.subdomainZone != null
          ) "${r.id}: sets `subdomain` but no `zone`, and there is no `publicProxy.defaultZone`")
          (check (
            r.subdomainZone == null || cfg.zones ? ${r.subdomainZone}
          ) "${r.id}: zone ${toString r.subdomainZone} is not in `publicProxy.zones`")
          (check (!(uses "cloudflare-origin") || r.zone != null)
            "${r.id}: a Cloudflare origin certificate covers one zone, but its domains are not all in the same zone of `publicProxy.zones`"
          )
          (check (!(uses "acme" && cfg.tls.acme.challenge == "http" && length r.gateways > 1))
            "${r.id}: is served by several gateways, the HTTP-01 challenge would hit the wrong one; use `publicProxy.tls.acme.challenge = \"dns\"`"
          )
          (check (
            r.service.dns.srv == null || r.protocol != "http"
          ) "${r.id}: SRV records are for tcp/udp services")
          (check (
            r.service.dns.srv == null
            || (r.domains != [ ] && (r.service.dns.srv.domain != null || zoneOf (head r.domains) != null))
          ) "${r.id}: an SRV record needs a domain to point at and one to live under")
        ];
    in
    concatLists [
      (check (
        subtractLists (attrNames rcfg.hosts) (allGateways ++ cfg.origins) == [ ]
      ) "unknown host(s) ${toString (subtractLists (attrNames rcfg.hosts) (allGateways ++ cfg.origins))}")
      (check (
        lib.intersectLists allGateways cfg.origins == [ ]
      ) "a host can't be both gateway and origin")
      (map (g: "gateway ${g} has no `endpoint` (or `ipv4`/`ipv6`)") (
        attrNames (filterAttrs (_: g: g.endpoint == null) cfg.gateways)
      ))
      (map (d: "domain ${d} is used by several services") (
        duplicates (concatMap (r: r.domains) services)
      ))
      (map (z: "zone ${z}: `wildcard` needs `tls.acme.challenge = \"dns\"`") (
        optionals (cfg.tls.acme.challenge != "dns") (attrNames (filterAttrs (_: z: z.wildcard) cfg.zones))
      ))
      (check (
        cfg.defaultZone == null || cfg.zones ? ${cfg.defaultZone}
      ) "`defaultZone` ${toString cfg.defaultZone} is not in `zones`")
      (check (
        cfg.tls.acme.challenge != "dns" || cfg.tls.acme.credentials != { }
      ) "the DNS challenge needs `tls.acme.credentials`")
      (concatMap perService services)
      cfg.internal.problems
    ];

  portProblems =
    gw:
    let
      routes = routesOf gw;
      ports = proto: map (r: r.publicPort) (filter (r: r.protocol == proto) routes);
      tcp = ports "tcp";
      udp = ports "udp";
    in
    map (p: "${gw}: tcp port ${toString p} is used twice") (duplicates tcp)
    ++ map (p: "${gw}: tcp port ${toString p} is reserved for http") (
      lib.intersectLists tcp [
        80
        443
      ]
    )
    ++ map (p: "${gw}: udp port ${toString p} is used twice") (duplicates udp)
    ++ optional (elem cfg.tunnel.port udp) "${gw}: udp port ${toString cfg.tunnel.port} is the tunnel port";

  records =
    map (r: r // { zone = zoneOf r.name; }) cfg.extraRecords
    ++ concatMap (
      r:
      let
        addressRecords = concatMap (
          d:
          concatMap (
            gw:
            let
              g = cfg.gateways.${gw};
              record = type: content: {
                name = d;
                zone = zoneOf d;
                inherit type content;
                proxied = r.cloudflareProxied;
              };
            in
            optional (g.ipv4 != null) (record "A" g.ipv4) ++ optional (g.ipv6 != null) (record "AAAA" g.ipv6)
          ) r.gateways
        ) r.domains;
        srv = r.service.dns.srv;
        srvDomain = if srv.domain != null then srv.domain else head r.domains;
        srvRecord = {
          name = "_${srv.service}._${r.protocol}.${srvDomain}";
          zone = zoneOf srvDomain;
          type = "SRV";
          inherit (srv) priority weight;
          port = r.publicPort;
          target = head r.domains;
          proxied = false;
        };
      in
      optionals r.service.dns.manage (addressRecords ++ optional (srv != null) srvRecord)
    ) services;

  # Handed to every host as the `publicProxy` module argument, together
  # with the fields of `internal.hostData`. Origins must not touch `routes`
  # or `problems`: they are built from the configurations of all origins,
  # their own included.
  hostData =
    host:
    {
      inherit (cfg) zones tls;
      inherit tunnelUp;
      backendName = cfg.backend;
      backend = cfg.backends.${cfg.backend};
      network = cfg.tunnel.network;
      isGateway = cfg.gateways ? ${host};
      isOrigin = elem host cfg.origins;
      gateways = allGateways;
      tunnelAddresses = addressesOf host;
      trustedProxies = concatMap addressesOf allGateways;
      routes = routesOf host;
      problems = problems ++ portProblems host;
    }
    // mapAttrs (_: f: f host) cfg.internal.hostData;

  # -- NixOS -------------------------------------------------------------------

  nixosModule =
    {
      config,
      lib,
      publicProxy,
      wireguard,
      ...
    }:
    let
      pp = publicProxy;
      hostName = config.networking.hostName;
      exposed = filterAttrs (_: s: s.enable) config.publicProxy.expose;
      iface = wireguard.interfaces.${pp.network}.interface or null;

      backend = pp.backend;
      routes = pp.routes;
      acme = pp.tls.acme;
      originCertificates = config.publicProxy.internal.originCertificates;

      credentialSecret = var: "public-proxy-acme-${lib.toLower var}";

      httpRoutes = filter (r: r.protocol == "http") routes;
      acmeRoutes = filter (r: r.cert.kind == "acme") httpRoutes;
      originZones = unique (
        lib.remove null (map (r: r.cert.zone) (filter (r: r.cert.kind == "cloudflare-origin") httpRoutes))
      );

      tlsFor =
        r:
        let
          # An assertion reports this; keep evaluation going until then.
          missing = {
            certificate = "/dev/null";
            key = "/dev/null";
          };
        in
        if r.cert.kind != "cloudflare-origin" then
          { acmeCert = r.cert.name; }
        else if r.cert.zone == null then
          missing
        else
          originCertificates.${r.cert.zone} or missing;

      acmeWebroot = "/var/lib/acme/acme-challenge";

      challenge =
        if acme.challenge == "http" then
          { webroot = acmeWebroot; }
        else
          {
            inherit (acme) dnsProvider dnsResolver;
            credentialFiles = mapAttrs' (
              var: _: nameValuePair "${var}_FILE" config.age.secrets.${credentialSecret var}.path
            ) acme.credentials;
          };

      acmeCerts = listToAttrs (
        map (
          r:
          nameValuePair r.cert.name (
            if r.cert.wildcard then
              {
                domain = r.cert.name;
                extraDomainNames = [ "*.${r.cert.name}" ];
              }
            else
              {
                domain = head r.domains;
                extraDomainNames = tail r.domains;
              }
          )
        ) acmeRoutes
      );

      ports = proto: unique (map (r: r.publicPort) (filter (r: r.protocol == proto) routes));
      originPorts =
        udp: unique (map (s: s.port) (filter (s: (s.protocol == "udp") == udp) (attrValues exposed)));
    in
    {
      options.publicProxy = {

        expose = mkOption {
          type = types.attrsOf serviceType;
          default = { };
          description = "Services of this host published through the gateways.";
        };

        tunnelAddresses = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = pp.tunnelAddresses;
          description = "This host's tunnel addresses, to bind services to them only.";
        };

        trustedProxies = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = pp.trustedProxies;
          description = ''
            Tunnel addresses of the gateways. Services behind the proxy
            should trust X-Forwarded-For/X-Real-IP from these.
          '';
        };

        internal.originCertificates = mkOption {
          type = types.attrsOf (
            types.submodule {
              options = {
                certificate = mkOption { type = types.either types.path types.str; };
                key = mkOption { type = types.str; };
              };
            }
          );
          default = { };
          internal = true;
          description = "Cloudflare origin certificate and key per zone, for gateways.";
        };

      };

      config = mkMerge [

        (mkIf (exposed != { }) {
          assertions = [
            {
              assertion = pp.isOrigin;
              message = "public-proxy: ${hostName} exposes services but is not in `publicProxy.origins`";
            }
            {
              assertion = !pp.isOrigin || pp.tunnelUp;
              message = "public-proxy: ${hostName} exposes services but no gateway is defined";
            }
          ];

          # Only the gateways can reach exposed ports, and only through the
          # tunnel.
          networking.firewall.interfaces = mkIf (iface != null) {
            ${iface} = {
              allowedTCPPorts = originPorts false;
              allowedUDPPorts = originPorts true;
            };
          };
        })

        (mkIf pp.isGateway (mkMerge [

          # Every backend is listed, so the structure of this module does
          # not depend on its arguments (that would recurse infinitely).
          (mkMerge (
            mapAttrsToList (
              name: b: mkIf (pp.backendName == name) (b.config { inherit routes tlsFor acmeWebroot; })
            ) cfg.backends
          ))

          {
            assertions =
              map (msg: {
                assertion = false;
                message = "public-proxy: ${msg}";
              }) pp.problems
              ++ map (zone: {
                assertion = originCertificates ? ${zone};
                message = "public-proxy: no Cloudflare origin certificate for ${zone} on ${hostName}";
              }) originZones;

            networking.firewall.allowedTCPPorts = [
              80
              443
            ]
            ++ ports "tcp";
            networking.firewall.allowedUDPPorts = ports "udp";

            security.acme = mkIf (acmeCerts != { }) {
              acceptTerms = true;
              defaults = {
                email = mkIf (acme.email != null) acme.email;
                server = mkIf acme.staging "https://acme-staging-v02.api.letsencrypt.org/directory";
              };
              certs = mapAttrs (_: c: c // challenge // { group = backend.group; }) acmeCerts;
            };

            age.secrets = optionalAttrs (acmeCerts != { } && acme.challenge == "dns") (
              mapAttrs' (var: file: nameValuePair (credentialSecret var) { rekeyFile = file; }) acme.credentials
            );
          }

        ]))

      ];
    };
in
{
  options.publicProxy = {

    zones = mkOption {
      type = types.attrsOf zoneType;
      default = { };
      example = {
        "example.com".wildcard = true;
        "example.net" = { };
      };
      description = ''
        DNS zones services are published under, by zone name. Domains
        outside of them work too, but get no zone level features
        (`subdomain`, wildcard and origin certificates, `records.*.zone`).
      '';
    };

    defaultZone = mkOption {
      type = types.nullOr types.str;
      default = if length (attrNames cfg.zones) == 1 then head (attrNames cfg.zones) else null;
      defaultText = "the only zone in `zones`, if there is exactly one";
      description = "Zone `subdomain` is relative to when a service sets no `zone`.";
    };

    gateways = mkOption {
      type = types.attrsOf gatewayType;
      default = { };
      description = "Hosts with a public address that serve the exposed services, by host name.";
    };

    origins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Hosts whose `publicProxy.expose` services are published. They join
        the tunnel and dial out to every gateway, so they need no public
        address or open port.
      '';
    };

    backend = mkOption {
      type = types.enum (attrNames cfg.backends);
      default = "nginx";
      description = "Proxy software on the gateways, one of `backends`.";
    };

    backends = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      internal = true;
      description = "Proxy implementations, registered by their files; see the interface at the top.";
    };

    tunnel = {

      network = mkOption {
        type = types.str;
        default = "edge";
        description = "Name of the WireGuard network between gateways and origins.";
      };

      ipv4 = mkOption {
        type = types.nullOr ip.types.ipv4Cidr;
        default = "10.77.0.0/24";
      };

      ipv6 = mkOption {
        type = types.nullOr ip.types.ipv6Cidr;
        default = null;
      };

      port = mkOption {
        type = types.port;
        default = 51820;
        description = "UDP port the gateways listen on for the tunnel.";
      };

      persistentKeepalive = mkOption {
        type = types.ints.unsigned;
        default = 25;
        description = "Keeps the NAT mapping of origins open.";
      };

    };

    tls = {

      mode = mkOption {
        type = types.enum tlsModes;
        default = "acme";
        description = ''
          Default certificate source of http services.
          `acme`: Let's Encrypt, see `acme`.
          `cloudflare-origin`: the Cloudflare origin certificate of the
          service's zone (see cloudflare.nix). Only Cloudflare trusts it,
          so the services' records are proxied by Cloudflare.
        '';
      };

      acme = {

        email = mkOption {
          type = types.nullOr types.str;
          default = null;
        };

        staging = mkOption {
          type = types.bool;
          default = false;
          description = "Use the Let's Encrypt staging environment, for testing.";
        };

        challenge = mkOption {
          type = types.enum [
            "http"
            "dns"
          ];
          default = "http";
          description = ''
            `http`: HTTP-01, needs nothing but only works with a single
            gateway per domain.
            `dns`: DNS-01 through `dnsProvider`, works with any number of
            gateways and for wildcards.
          '';
        };

        dnsProvider = mkOption {
          type = types.str;
          default = "cloudflare";
          description = "lego DNS provider name.";
        };

        dnsResolver = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "1.1.1.1:53";
          description = ''
            Resolver lego asks whether the challenge record is visible. `null`
            is the system's, which may be a provider resolver that does not
            see new records for a long time.
          '';
        };

        credentials = mkOption {
          type = types.attrsOf types.path;
          default = { };
          description = ''
            lego environment variable -> age encrypted file holding its
            value (create with `agenix edit <file>`). For Cloudflare this
            defaults to the API token of cloudflare.nix.
          '';
        };

      };

    };

    extraRecords = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption { type = types.str; };
            type = mkOption {
              type = types.enum [
                "A"
                "AAAA"
              ];
            };
            content = mkOption { type = types.str; };
            proxied = mkOption {
              type = types.bool;
              default = false;
            };
          };
        }
      );
      default = [ ];
      description = ''
        Records kept in Cloudflare next to those of the services, for names
        that are no service, e.g. the endpoint of a WireGuard hub.
      '';
    };

    records = mkOption {
      type = types.raw;
      readOnly = true;
      default = records;
      description = "DNS records the exposed services need.";
    };

    internal = {

      hostData = mkOption {
        type = types.attrsOf (types.functionTo types.raw);
        default = { };
        internal = true;
        description = "Extra fields of the `publicProxy` module argument, computed from the host name.";
      };

      problems = mkOption {
        type = types.listOf types.str;
        default = [ ];
        internal = true;
        description = "Configuration errors, reported by every gateway.";
      };

    };

  };

  config = {

    wireguard.networks = mkIf tunnelUp {
      ${cfg.tunnel.network} = {
        topology = "mesh";
        inherit (cfg.tunnel) ipv4 ipv6 port;
        # Origins have no endpoint, so they never try to reach each other.
        members =
          mapAttrs (_: g: { inherit (g) endpoint; }) cfg.gateways
          // genAttrs cfg.origins (_: {
            listenPort = null;
            inherit (cfg.tunnel) persistentKeepalive;
            # only the gateways: a broken-into origin must not reach the others
            peers = allGateways;
          });
      };
    };

    registry.extraHostArgs.publicProxy = host: hostData host.hostName;

    flake.publicProxyData = {
      inherit records;
      services = map (r: {
        inherit (r)
          id
          origin
          protocol
          domains
          publicPort
          gateways
          tlsMode
          cloudflareProxied
          ;
        upstream = if r.protocol == "http" then r.upstream.url else "${r.protocol}://${r.upstream.address}";
      }) services;
    };

    flake.modules.nixos.base.imports = [ self.modules.nixos.public-proxy ];
    flake.modules.nixos.public-proxy.imports = [ nixosModule ];

  };
}
