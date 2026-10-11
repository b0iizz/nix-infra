# Gateway VPS (IONOS, 1 vCPU, 1.8 GiB RAM, public IPv4 and IPv6): the one
# public address of the fleet.
#
# - Hub of the `hub` WireGuard network (hub and spoke) at wg.greb.es: atlas
#   and prometheus dial it and reach each other through it.
# - Gateway of the proxy's own `edge` tunnel: terminates TLS (Let's Encrypt,
#   DNS-01 through Cloudflare, records not proxied) and reverse proxies what
#   origins `publicProxy.expose`, e.g. nas.grebes.net for copyparty on atlas.
# - Keeps the Cloudflare records of all this up to date.
#
# The publicProxy and wireguard settings are for the whole flake; see
# modules/public-proxy/module.nix and modules/wireguard.nix. Secrets (agenix
# edit, then agenix rekey -a):
#   secrets/public-proxy/cloudflare-dns-token.age   record sync
#   secrets/public-proxy/cloudflare-acme-token.age  DNS-01 challenge
# plus `agenix generate` for the WireGuard keys (edge and hub networks).
#
# Disks: root on ext4 with swap, no LUKS (a VPS has to boot unattended).
{ ... }:
let
  hubEndpoint = "wg.greb.es";
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

    gateways.phoebe = address;
    origins = [ "atlas" ];

    tls.acme.challenge = "dns";
    dns.enable = true;

    extraRecords = [
      {
        name = hubEndpoint;
        type = "A";
        content = address.ipv4;
      }
      {
        name = hubEndpoint;
        type = "AAAA";
        content = address.ipv6;
      }
    ];
  };

  # Every machine of the fleet, reachable from every other through phoebe.
  # Separate from the proxy's `edge` tunnel (10.77.0.0/24, UDP 51820), which
  # only carries what the gateway publishes.
  wireguard.networks.hub = {
    topology = "hub-and-spoke";
    hub = "phoebe";
    ipv4 = "10.78.0.0/24";
    port = 51821;
    members = {
      phoebe.endpoint = hubEndpoint;
      atlas = { };
      prometheus = { };
    };
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
