# Documents, PDFs, printing and scanning. `office` brings the other two along;
# `printing` and `scanning` alone suit a machine that only needs the hardware.
# The drivers of a particular printer or scanner belong to the host:
#
#   services.printing.drivers = [ pkgs.epson-escpr2 ];
#   hardware.sane.extraBackends = [ pkgs.epkowa ];
{ self, ... }:
{
  flake.modules.nixos.office =
    { pkgs, ... }:
    {
      imports = with self.modules.nixos; [
        printing
        scanning
      ];

      environment.systemPackages = with pkgs; [
        libreoffice-stable
        evince
        ocrmypdf
      ];

      xdg.mime.defaultApplications."application/pdf" = "org.gnome.Evince.desktop";
    };

  flake.modules.nixos.printing = {
    imports = [ self.modules.nixos.persist ];

    services.printing.enable = true;
    # finds network printers
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    persist.directories = [ "/var/lib/cups" ];
  };

  flake.modules.nixos.scanning =
    { pkgs, ... }:
    {
      hardware.sane.enable = true;
      environment.systemPackages = [ pkgs.simple-scan ];
    };
}
