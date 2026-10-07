# Cloudflare integration of the public proxy (see module.nix), with one API
# token (`cloudflare.apiTokenFile`):
#
# - `dns.enable`: one gateway keeps the records of `publicProxy.records`
#   in Cloudflare up to date.
# - Cloudflare origin certificates (`tls.mode = "cloudflare-origin"`):
#   either committed per zone (`zones.<zone>.cloudflareOrigin`), or issued
#   through the API on every gateway that needs one.
# - The token is the default credential of the DNS-01 challenge.
# - The ranges Cloudflare's proxy connects from, trusted for the client
#   address of proxied services.
#
# Both API jobs run as oneshot services on deploy and daily. Let's Encrypt
# orders wait for the DNS sync, so HTTP-01 finds its records.
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib)
    attrNames
    concatMap
    concatStringsSep
    filter
    genAttrs
    head
    listToAttrs
    mapAttrs'
    mkDefault
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optional
    optionalAttrs
    subtractLists
    types
    unique
    ;

  rcfg = config.registry;
  cfg = config.publicProxy;
  ip = self.lib.ip;

  # Published Cloudflare ranges (https://www.cloudflare.com/ips/).
  cloudflareIPs = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];

  # Runs on gateways as oneshot services. Reads the API token from the
  # systemd credential `cloudflare-token` and a JSON config built below.
  #
  #   dns <config>     sync records: { zones, records, ttl, prune }
  #   origin <config>  issue/renew an origin certificate:
  #                    { zone, hostnames, directory, group, reload,
  #                      validityDays, renewDays }
  cloudflareTool =
    pkgs:
    pkgs.writers.writePython3Bin "public-proxy-cloudflare"
      {
        flakeIgnore = [
          "E501"
          "W503"
          "W504"
        ];
      }
      ''
        import ipaddress
        import json
        import os
        import shutil
        import subprocess
        import sys
        import tempfile
        import urllib.error
        import urllib.parse
        import urllib.request

        API = os.environ.get("CLOUDFLARE_API", "https://api.cloudflare.com/client/v4")
        MARKER = "managed by nix public-proxy"


        class ApiError(Exception):
            pass


        def read_token():
            path = os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "cloudflare-token")
            with open(path) as f:
                return f.read().strip()


        def call(method, path, body=None, params=None):
            url = API + path
            if params:
                url += "?" + urllib.parse.urlencode(params)
            data = None if body is None else json.dumps(body).encode()
            request = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": "Bearer " + read_token(),
                "Content-Type": "application/json",
            })
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    result = json.load(response)
            except urllib.error.HTTPError as e:
                try:
                    result = json.load(e)
                except ValueError:
                    raise ApiError(f"{method} {path}: HTTP {e.code}")
            except urllib.error.URLError as e:
                raise ApiError(f"{method} {path}: {e.reason}")
            if not result.get("success"):
                raise ApiError(f"{method} {path}: {result.get('errors')}")
            return result


        def paged(path):
            items, page = [], 1
            while True:
                result = call("GET", path, params={"page": page, "per_page": 100})
                items += result["result"]
                if page >= (result.get("result_info") or {}).get("total_pages", 1):
                    return items
                page += 1


        # -- dns ------------------------------------------------------------------

        def key_of(record):
            name = record["name"].lower()
            if record["type"] == "SRV":
                data = record.get("data", record)
                return ("SRV", name, data["priority"], data["weight"], data["port"], data["target"].lower())
            content = record["content"]
            if record["type"] in ("A", "AAAA"):
                content = str(ipaddress.ip_address(content))
            return (record["type"], name, content)


        def payload(record, ttl):
            body = {"type": record["type"], "name": record["name"], "comment": MARKER}
            if record["type"] == "SRV":
                body["data"] = {k: record[k] for k in ("priority", "weight", "port", "target")}
                body["ttl"] = ttl
            else:
                body["content"] = record["content"]
                body["proxied"] = record["proxied"]
                # Cloudflare forces automatic TTL on proxied records.
                body["ttl"] = 1 if record["proxied"] else ttl
            return body


        def outdated(current, body):
            return (
                current.get("comment") != MARKER
                or current.get("ttl") != body["ttl"]
                or ("proxied" in body and current.get("proxied") != body["proxied"])
            )


        def sync_zone(zone, records, ttl, prune):
            found = call("GET", "/zones", params={"name": zone})["result"]
            if not found:
                raise ApiError(f"zone {zone} not found, or the token can't read it")
            base = f"/zones/{found[0]['id']}/dns_records"
            existing = paged(base)
            managed = {key_of(e): e for e in existing if e.get("comment") == MARKER}
            unmanaged = {key_of(e): e for e in existing if e.get("comment") != MARKER}
            wanted = {key_of(r) for r in records}
            ok = True

            for e in existing:
                key = key_of(e) if e["type"] in ("A", "AAAA", "SRV") else None
                if e.get("comment") != MARKER and key not in wanted and any(
                    (r["type"], r["name"].lower()) == (e["type"], e["name"]) for r in records
                ):
                    print(f"{zone}: warning: unmanaged {e['type']} {e['name']} {e.get('content', ${"''"})} is served alongside", file=sys.stderr)

            def attempt(action, *args):
                nonlocal ok
                try:
                    call(*args)
                    print(f"{zone}: {action}")
                except ApiError as e:
                    print(f"{zone}: {action} failed: {e}", file=sys.stderr)
                    ok = False

            for record in records:
                key = key_of(record)
                body = payload(record, ttl)
                current = managed.pop(key, None) or unmanaged.get(key)
                label = " ".join(str(k) for k in key)
                if current is None:
                    attempt(f"create {label}", "POST", base, body)
                elif outdated(current, body):
                    attempt(f"update {label}", "PATCH", f"{base}/{current['id']}", body)

            if prune:
                for key, stale in managed.items():
                    label = " ".join(str(k) for k in key)
                    attempt(f"delete {label}", "DELETE", f"{base}/{stale['id']}")
            return ok


        def dns(config):
            ok = True
            for zone in config["zones"]:
                records = [r for r in config["records"] if r["zone"] == zone]
                try:
                    ok = sync_zone(zone, records, config["ttl"], config["prune"]) and ok
                except ApiError as e:
                    print(f"{zone}: {e}", file=sys.stderr)
                    ok = False
            return ok


        # -- origin certificates ----------------------------------------------------

        def openssl(*args):
            return subprocess.run(["openssl", *args], check=True, capture_output=True, text=True).stdout


        def install(path, group, mode):
            shutil.chown(path, group=group)
            os.chmod(path, mode)


        def origin(config):
            zone, directory, group = config["zone"], config["directory"], config["group"]
            cert = os.path.join(directory, "cert.pem")
            key = os.path.join(directory, "key.pem")
            names = os.path.join(directory, "hostnames.json")
            hostnames = sorted(set(config["hostnames"]))

            try:
                with open(names) as f:
                    issued_for = json.load(f)
            except (OSError, ValueError):
                issued_for = None
            valid = os.path.exists(cert) and subprocess.run(
                ["openssl", "x509", "-checkend", str(config["renewDays"] * 86400), "-noout", "-in", cert],
                capture_output=True,
            ).returncode == 0
            if issued_for == hostnames and valid:
                print(f"{zone}: origin certificate is current")
                return True

            if not os.path.exists(cert):
                # Stand-in so the proxy can start even if the API is unreachable.
                openssl("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                        "-nodes", "-keyout", key, "-out", cert, "-days", "1", "-subj", f"/CN={zone}")
                install(key, group, 0o640)
                install(cert, group, 0o644)

            with tempfile.TemporaryDirectory(dir=directory) as tmp:
                new_key = os.path.join(tmp, "key.pem")
                new_cert = os.path.join(tmp, "cert.pem")
                openssl("genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-out", new_key)
                csr = openssl("req", "-new", "-key", new_key, "-subj", f"/CN={zone}")
                try:
                    result = call("POST", "/certificates", {
                        "hostnames": hostnames,
                        "requested_validity": config["validityDays"],
                        "request_type": "origin-ecc",
                        "csr": csr,
                    })["result"]
                except ApiError as e:
                    print(f"{zone}: {e}", file=sys.stderr)
                    return False
                with open(new_cert, "w") as f:
                    f.write(result["certificate"])
                install(new_key, group, 0o640)
                install(new_cert, group, 0o644)
                os.replace(new_key, key)
                os.replace(new_cert, cert)

            with open(names, "w") as f:
                json.dump(hostnames, f)
            print(f"{zone}: issued origin certificate for {', '.join(hostnames)}")
            subprocess.run(["systemctl", "try-reload-or-restart", config["reload"]], check=False)
            return True


        def main():
            command, path = sys.argv[1:3]
            with open(path) as f:
                config = json.load(f)
            ok = {"dns": dns, "origin": origin}[command](config)
            sys.exit(0 if ok else 1)


        main()
      '';

  # Gateway side: certificates, secrets and the oneshot jobs.
  nixosModule =
    {
      config,
      pkgs,
      publicProxy,
      ...
    }:
    let
      pp = publicProxy;
      cf = pp.cloudflare;
      backend = pp.backend;

      tool = "${cloudflareTool pkgs}/bin/public-proxy-cloudflare";
      apiTokenSecret = "public-proxy-cloudflare-api-token";
      fileSecret = zone: "public-proxy-cloudflare-origin-${zone}";
      originDir = zone: "/var/lib/public-proxy/cloudflare-origin/${zone}";
      originUnit = zone: "public-proxy-cloudflare-origin-${zone}";

      # Zones whose origin certificate is used here (a route without a
      # zone is reported by module.nix), by where the certificate comes from.
      originRoutes = filter (
        r: r.protocol == "http" && r.cert.kind == "cloudflare-origin" && r.cert.zone != null
      ) pp.routes;
      originZones = unique (map (r: r.cert.zone) originRoutes);
      fileZones = filter (z: pp.zones.${z}.cloudflareOrigin.certificate != null) originZones;
      apiZones = subtractLists fileZones originZones;
      usesApi = cf.dns.sync || apiZones != [ ];

      # The zone apex, its wildcard and whatever deeper names are served.
      originHostnames =
        zone:
        unique (
          [
            zone
            "*.${zone}"
          ]
          ++ concatMap (r: r.cert.extraNames) (filter (r: r.cert.zone == zone) originRoutes)
        );

      # A oneshot that runs at boot and whenever its config changes, plus a
      # timer driven twin for the daily run (a timer can't restart a unit
      # that stays active).
      job =
        {
          name,
          description,
          command,
          settings,
          extraConfig ? { },
        }:
        let
          configFile = pkgs.writeText "${name}.json" (builtins.toJSON settings);
          unit = remain: {
            inherit description;
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            path = [
              pkgs.openssl
              config.systemd.package
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = remain;
              ExecStart = "${tool} ${command} ${configFile}";
              LoadCredential = "cloudflare-token:${config.age.secrets.${apiTokenSecret}.path}";
              UMask = "0077";
              # The API being unreachable at boot shouldn't wait a day.
              Restart = "on-failure";
              RestartSec = "10min";
            }
            // extraConfig;
          };
        in
        {
          ${name} = unit true // {
            wantedBy = [ "multi-user.target" ];
          };
          "${name}-refresh" = unit false // {
            startAt = "daily";
          };
        };
    in
    {
      config = mkIf pp.isGateway {

        publicProxy.internal.originCertificates =
          genAttrs fileZones (zone: {
            certificate = pp.zones.${zone}.cloudflareOrigin.certificate;
            key = config.age.secrets.${fileSecret zone}.path;
          })
          // genAttrs apiZones (zone: {
            certificate = "${originDir zone}/cert.pem";
            key = "${originDir zone}/key.pem";
          });

        age.secrets =
          listToAttrs (
            map (
              zone:
              nameValuePair (fileSecret zone) {
                rekeyFile = pp.zones.${zone}.cloudflareOrigin.keyFile;
                owner = backend.user;
                group = backend.group;
                mode = "0400";
              }
            ) fileZones
          )
          // optionalAttrs usesApi {
            ${apiTokenSecret}.rekeyFile = cf.apiTokenFile;
          };

        systemd.services = mkMerge (
          optional cf.dns.sync (job {
            name = "public-proxy-dns";
            description = "Sync public-proxy DNS records to Cloudflare";
            command = "dns";
            settings = {
              inherit (cf.dns)
                zones
                records
                ttl
                prune
                ;
            };
          })
          ++ map (
            zone:
            job {
              name = originUnit zone;
              description = "Cloudflare origin certificate for ${zone}";
              command = "origin";
              settings = {
                inherit zone;
                hostnames = originHostnames zone;
                directory = originDir zone;
                group = backend.group;
                reload = "${backend.unit}.service";
                validityDays = 5475;
                renewDays = 30;
              };
              extraConfig.StateDirectory = "public-proxy/cloudflare-origin/${zone}";
            }
          ) apiZones
          ++ [
            # The proxy needs the certificates (or their stand-ins) to start.
            {
              ${backend.unit} = {
                wants = map (z: "${originUnit z}.service") apiZones;
                after = map (z: "${originUnit z}.service") apiZones;
              };
            }
          ]
          # HTTP-01 needs the records in place before ordering.
          ++ optional cf.dns.sync (
            mapAttrs' (
              name: _:
              nameValuePair "acme-order-renew-${name}" {
                wants = [ "public-proxy-dns.service" ];
                after = [ "public-proxy-dns.service" ];
              }
            ) config.security.acme.certs
          )
        );

        warnings = optional (cf.dns.sync && cf.dns.unzoned != [ ]) ''
          public-proxy: not syncing DNS for ${concatStringsSep ", " cf.dns.unzoned}: not in any of `publicProxy.zones`
        '';

      };
    };
in
{
  options.publicProxy = {

    # Extends the zones of module.nix.
    zones = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.cloudflareOrigin = {

              certificate = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = ''
                  `null`: every gateway issues its own origin certificate
                  through the Cloudflare API (`cloudflare.apiTokenFile`) and
                  renews it before it expires.

                  Otherwise an origin certificate (PEM) of this zone from the
                  Cloudflare dashboard, with its key in `keyFile`. It's
                  public, commit it.
                '';
              };

              keyFile = mkOption {
                type = types.path;
                default = rcfg.secretsDir + "/public-proxy/cloudflare-origin-${name}.age";
                defaultText = "secrets/public-proxy/cloudflare-origin-<zone>.age";
                description = "age encrypted private key of `certificate`.";
              };

            };
          }
        )
      );
    };

    cloudflare = {

      apiTokenFile = mkOption {
        type = types.path;
        default = rcfg.secretsDir + "/public-proxy/cloudflare-api-token.age";
        defaultText = "secrets/public-proxy/cloudflare-api-token.age";
        description = ''
          age encrypted Cloudflare API token (create with `agenix edit
          <file>`), used for DNS records, origin certificates and the
          DNS-01 challenge. Permissions, for all zones in `zones`:
          Zone:Read, DNS:Edit and SSL and Certificates:Edit.
        '';
      };

      ipRanges = mkOption {
        type = types.listOf ip.types.cidr;
        default = cloudflareIPs;
        description = "Addresses Cloudflare's proxy connects from; trusted for the client address.";
      };

    };

    dns = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Keep the records of `records` in Cloudflare up to date. One
          gateway (`dns.gateway`) syncs them on every deploy that changes
          them and once a day. Records it creates are marked with a
          comment; only marked records are ever changed or deleted
          (an identical unmarked record is adopted).
        '';
      };

      gateway = mkOption {
        type = types.nullOr types.str;
        default = if cfg.gateways == { } then null else head (attrNames cfg.gateways);
        defaultText = "the first gateway";
        description = "Gateway that syncs the records.";
      };

      ttl = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "TTL of unproxied records in seconds; 1 means automatic.";
      };

      prune = mkOption {
        type = types.bool;
        default = true;
        description = "Delete marked records that are no longer needed.";
      };

    };

  };

  config = {

    publicProxy.tls.acme.credentials = mkIf (cfg.tls.acme.dnsProvider == "cloudflare") (mkDefault {
      CLOUDFLARE_DNS_API_TOKEN = cfg.cloudflare.apiTokenFile;
    });

    publicProxy.internal.problems = optional (
      cfg.dns.enable && !(cfg.dns.gateway != null && cfg.gateways ? ${cfg.dns.gateway})
    ) "`dns.gateway` ${toString cfg.dns.gateway} is not in `gateways`";

    publicProxy.internal.hostData.cloudflare = host: {
      inherit (cfg.cloudflare) apiTokenFile;
      dns = {
        sync = cfg.dns.enable && cfg.dns.gateway == host;
        inherit (cfg.dns) ttl prune;
        zones = attrNames cfg.zones;
        records = filter (r: r.zone != null) cfg.records;
        unzoned = unique (map (r: r.name) (filter (r: r.zone == null) cfg.records));
      };
    };

    flake.modules.nixos.public-proxy.imports = [ nixosModule ];

  };
}
