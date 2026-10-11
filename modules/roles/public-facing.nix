# A host that answers the internet: bans, rate limit, HSTS and a filtered
# forward chain.
#
#   roles = [ "disko-root-ext4" "public-facing" ];
#
# - fail2ban: NixOS's `sshd` jail, plus `nginx-abuse` on the per service logs
#   of the public proxy (modules/public-proxy/nginx.nix): 20 answers of
#   400/401/403/404 within a minute ban the address for 10 minutes, doubling
#   with every repeat. Bans use nftables sets of fail2ban's own; they survive
#   a deploy because fail2ban restarts and re-applies them.
# - nginx: 30 requests/s per client address (burst 100, then 429) and
#   `Strict-Transport-Security` for a year. Only if nginx is enabled.
# - nftables with `filterForward`: a WireGuard hub (modules/wireguard.nix)
#   relays inside its own interface only; nothing from the outside is routed
#   into a tunnel.
#
# Services behind Cloudflare (`dns.cloudflareProxied`) are banned by the
# address Cloudflare reports (CF-Connecting-IP), which the proxy puts into the
# log, so the ban lands on the client and not on Cloudflare's edge.
#
# Checked by `nix build .#checks.x86_64-linux.public-facing` for every host
# that lists the role. Not covered: patching (run `deploy switch` regularly)
# and the scope of the Cloudflare tokens.
{
  config,
  lib,
  self,
  ...
}:
{
  flake.modules.nixos.public-facing =
    { config, lib, ... }:
    {
      services.fail2ban = {
        enable = true;
        bantime = "10m";
        bantime-increment.enable = true;
        jails.nginx-abuse = lib.mkIf config.services.nginx.enable {
          # one failure per log line; <HOST> is the first field of `combined`.
          # fail2ban cuts the timestamp out first, so skip to the request
          filter.Definition.failregex = ''^<HOST> [^"]*"[^"]*" (400|401|403|404) '';
          settings = {
            # NixOS defaults to the journal, which ignores `logpath`
            backend = "auto";
            logpath = "/var/log/nginx/public-proxy-*.log";
            port = "http,https";
            maxretry = 20;
            findtime = "1m";
          };
        };
      };

      networking.nftables.enable = true;
      networking.firewall.filterForward = true;

      services.nginx.appendHttpConfig = lib.mkIf config.services.nginx.enable ''
        limit_req_zone $binary_remote_addr zone=public_facing:10m rate=30r/s;
        limit_req zone=public_facing burst=100 nodelay;
        limit_req_status 429;
        add_header Strict-Transport-Security "max-age=31536000" always;
      '';
    };

  perSystem =
    { pkgs, ... }:
    let
      hosts = lib.filterAttrs (_: h: lib.elem "public-facing" h.roles) config.registry.hosts;
      problems = lib.concatLists (
        lib.mapAttrsToList (
          name: _:
          let
            c = self.nixosConfigurations.${name}.config;
          in
          lib.optional (!c.services.fail2ban.enable) "${name}: fail2ban is off"
          ++ lib.optional (!c.networking.firewall.filterForward) "${name}: forwarding is not filtered"
          ++ lib.optional (
            c.services.nginx.enable && !(c.services.fail2ban.jails ? nginx-abuse)
          ) "${name}: no nginx jail"
        ) hosts
      );
    in
    {
      checks.public-facing = pkgs.runCommand "check-public-facing" { } (
        if problems == [ ] then
          "touch $out"
        else
          ''
            printf '%s\n' ${lib.escapeShellArgs problems} >&2
            exit 1
          ''
      );
    };
}
