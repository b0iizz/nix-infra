# nginx backend of the public proxy (see the backend interface in
# module.nix): http routes become TLS vhosts, tcp/udp routes stream
# servers. Services can add raw directives under `expose.<name>.nginx`.
{ lib, ... }:
let
  inherit (lib)
    concatMapStrings
    concatMapStringsSep
    filter
    head
    listToAttrs
    mkDefault
    mkOption
    nameValuePair
    optionalString
    tail
    types
    ;

  logFile = id: "/var/log/nginx/public-proxy-${id}.log";

  config =
    { routes, tlsFor, ... }:
    let
      http = filter (r: r.protocol == "http") routes;
      streams = filter (r: r.protocol != "http") routes;

      realIp = r: ''
        ${concatMapStrings (c: "set_real_ip_from ${c};\n") r.realIp.from}real_ip_header ${r.realIp.header};
      '';

      # Proxied services answer Cloudflare only: the connection (not the
      # client address real_ip substitutes) has to come from its ranges, or
      # a request straight to the gateway would skip Cloudflare altogether.
      proxied = filter (r: r.realIp != null) http;
      proxiedRanges = lib.unique (lib.concatMap (r: r.realIp.from) proxied);

      vhost =
        r:
        let
          tls = tlsFor r;
        in
        nameValuePair (head r.domains) (
          {
            serverAliases = tail r.domains;
            forceSSL = true;
            extraConfig = ''
              access_log ${logFile r.id};
              ${optionalString (r.maxBodySize != null) "client_max_body_size ${r.maxBodySize};"}
              ${optionalString (r.realIp != null) (realIp r)}
              ${optionalString (r.realIp != null) ''if ($public_proxy_from_cloudflare = 0) { return 444; }''}
              ${r.service.nginx.serverConfig}
            '';
            locations."/" = {
              proxyPass = r.upstream.url;
              proxyWebsockets = r.websockets;
              extraConfig = r.service.nginx.locationConfig;
            };
          }
          // (
            if tls ? acmeCert then
              { useACMEHost = tls.acmeCert; }
            else
              {
                sslCertificate = tls.certificate;
                sslCertificateKey = tls.key;
              }
          )
        );

      stream =
        r:
        let
          suffix = optionalString (r.protocol == "udp") " udp";
        in
        ''
          server {
            listen ${toString r.publicPort}${suffix};
            listen [::]:${toString r.publicPort}${suffix};
            proxy_pass ${r.upstream.address};
            ${optionalString r.proxyProtocol "proxy_protocol on;"}
            ${r.service.nginx.serverConfig}
          }
        '';
    in
    {
      services.nginx = {
        enable = true;
        recommendedProxySettings = mkDefault true;
        recommendedTlsSettings = mkDefault true;
        recommendedOptimisation = mkDefault true;
        recommendedGzipSettings = mkDefault true;

        virtualHosts = listToAttrs (map vhost http) // {
          # Unknown host names get nothing, not the first vhost.
          "_" = {
            default = true;
            rejectSSL = true;
            locations."/".return = "444";
          };
        };

        streamConfig = concatMapStrings stream streams;

        appendHttpConfig = optionalString (proxied != [ ]) ''
          geo $realip_remote_addr $public_proxy_from_cloudflare {
            default 0;
            ${concatMapStringsSep "\n  " (c: "${c} 1;") proxiedRanges}
          }
        '';
      };
    };
in
{
  publicProxy.backends.nginx = {
    user = "nginx";
    group = "nginx";
    # The NixOS nginx module already reloads nginx after ACME renewals.
    unit = "nginx";
    inherit logFile config;
  };

  # Per service escape hatches.
  flake.modules.nixos.public-proxy.imports = [
    {
      options.publicProxy.expose = mkOption {
        type = types.attrsOf (
          types.submodule {
            options.nginx = {
              serverConfig = mkOption {
                type = types.lines;
                default = "";
                description = "Extra directives for the `server` block (vhost or stream).";
              };
              locationConfig = mkOption {
                type = types.lines;
                default = "";
                description = "Extra directives for `location /` (http only).";
              };
            };
          }
        );
      };
    }
  ];
}
