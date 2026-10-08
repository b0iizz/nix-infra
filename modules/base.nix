{ self, lib, ... }:
{
  flake.modules.nixos.base = {
    nix.settings = {
      trusted-users = [ "@wheel" ];
      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://nix-community.cachix.org" ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    system.activationScripts.current-flake = lib.stringAfter [ "specialfs" ] ''
      ln -sfn ${self} /run/current-flake
    '';

    time.timeZone = lib.mkDefault "Europe/Berlin";
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
    console.keyMap = lib.mkDefault "de";
  };
}
