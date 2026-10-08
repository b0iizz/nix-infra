# nftables sets on the gateways of the public proxy (see module.nix) whose
# addresses are dropped. Meant as the target of fail2ban and similar
# tools; together with the per service logs of the backends
# (`backends.<name>.logFile`) that is all a jail needs.
#
# Services proxied by Cloudflare can't be banned here: their traffic comes
# from Cloudflare's edge. They need a backend level deny or the Cloudflare
# API.
{ lib, config, ... }:
{
  options.publicProxy.banList.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      nftables sets `inet public-proxy banned4`/`banned6` on gateways;
      traffic from addresses in them is dropped. Enables the nftables
      firewall. Nothing here fills the sets, and they are emptied whenever
      the firewall reloads (every deploy), so whatever fills them (e.g.
      fail2ban) has to re-apply its bans.
    '';
  };

  config = {

    publicProxy.internal.hostData.banList = _: { inherit (config.publicProxy.banList) enable; };

    flake.modules.nixos.public-proxy.imports = [
      (
        { lib, publicProxy, ... }:
        {
          config = lib.mkIf (publicProxy.isGateway && publicProxy.banList.enable) {
            networking.nftables = {
              enable = lib.mkDefault true;
              tables.public-proxy = {
                family = "inet";
                content = ''
                  set banned4 {
                    type ipv4_addr
                    flags interval, timeout
                  }
                  set banned6 {
                    type ipv6_addr
                    flags interval, timeout
                  }
                  chain input {
                    type filter hook input priority filter - 10; policy accept;
                    ip saddr @banned4 drop
                    ip6 saddr @banned6 drop
                  }
                '';
              };
            };
          };
        }
      )
    ];

  };
}
