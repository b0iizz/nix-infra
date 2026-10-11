# Gateway VPS (IONOS, 1 vCPU, 1.8 GiB RAM, public IPv4 and IPv6): the one
# public address of the fleet.
#
# - Hub of the `edge` WireGuard network (hub and spoke): origins such as atlas
#   dial wg.greb.es and need no open port. Spokes see only the hub.
# - Terminates TLS (Let's Encrypt, DNS-01 through Cloudflare;
#   the records are DNS only, not proxied) and reverse
#   proxies what origins `publicProxy.expose`, e.g. nas.grebes.net for
#   copyparty on atlas.
# - Keeps the Cloudflare records of all this up to date.
#
# The publicProxy settings are for the whole flake; see
# modules/public-proxy/module.nix. Secrets (agenix edit, then agenix rekey -a):
#   secrets/public-proxy/cloudflare-dns-token.age   record sync
#   secrets/public-proxy/cloudflare-acme-token.age  DNS-01 challenge
# plus `agenix generate` for the WireGuard keys of phoebe and atlas.
#
# Disks: root on ext4 with swap, no LUKS (a VPS has to boot unattended).
{ ... }:
let
  address = {
    ipv4 = "87.106.233.164";
    ipv6 = "2a02:2479:db:ce00::1";
  };
in
{
  publicProxy = {
    zones."greb.es" = { };
    zones."grebes.net" = { };
    defaultZone = "greb.es";

    gateways.phoebe = address // {
      endpoint = "wg.greb.es";
    };
    origins = [ "atlas" ];

    tls.acme.challenge = "dns";
    dns.enable = true;
  };

  registry.hosts.phoebe = {
    path = ./.;
    stateVersion = "26.11";
    roles = [ "disko-root-ext4" ];
    deploy.targetHost = address.ipv4;
    provision.targetUser = "root";
    provision.targetHost = address.ipv4;

    modules = [
      {
        boot.loader.systemd-boot.enable = true;
        # a VPS has no persistent firmware variables to rely on
        boot.loader.efi.canTouchEfiVariables = false;

        # 1.8 GiB of RAM and nginx: some swap on disk, zram in front of it
        disko-layouts.swap.size = "2GiB";
        zramSwap.enable = true;

        # the provider hands out the IPv4 and IPv6 address by DHCP
        networking.useDHCP = true;
        networking.useNetworkd = true;
      }
    ];
  };
}
