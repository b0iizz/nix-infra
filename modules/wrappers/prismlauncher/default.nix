# Prism Launcher (Minecraft), wrapped. nixpkgs' package brings the Java
# versions Minecraft needs. Prism writes its settings itself, so the wrapper
# renders none; it only keeps the launcher's folder (accounts, instances,
# worlds) across reboots.
#
# Installed by the `gaming` role (modules/roles/gaming.nix).
{ self, ... }:
let
  w = self.lib.wrappers;
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrappers.prismlauncher = w.program [
        (w.withPackage pkgs.prismlauncher)
        { passthru.persist.directories = old: old ++ [ ".local/share/PrismLauncher" ]; }
      ];
    };
}
