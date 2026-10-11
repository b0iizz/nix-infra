{ ... }:
{
  registry.hosts.phoebe = {
    path = ./.;
    roles = [ ];
    provision.targetUser = "root";
    provision.targetHost = "87.106.233.164";
  };
}
