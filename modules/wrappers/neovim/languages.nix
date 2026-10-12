# Language servers for what this repo is written in, configured in full here
# (the wrapper's nvim-lspconfig defaults are for servers from project shells):
#
#   nixd       Nix: nixpkgs attributes, nixfmt formatting (the one `nix fmt`
#              uses), and the options of the flake the file is in
#              (_nixd-options.nix): every host's NixOS options and the
#              flake-parts ones. It runs in the project root, which makes
#              `./.` in its expressions that flake. (Its `cmd` is a function,
#              so Neovim doesn't check that nixd is on PATH: keep `package`.)
#   marksman   Markdown: completion and go-to for links and headings,
#              references, rename, broken-link diagnostics
#
# Extends `wrappers.neovim` (default.nix) after its own definition.
{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;

  fromFlake = set: "(import ${./_nixd-options.nix} (builtins.getFlake (toString ./.))).${set}";
in
{
  # flake-parts' `debug`, `allSystems` and `currentSystem` outputs: its option
  # declarations, for nixd
  debug = true;

  perSystem =
    { pkgs, ... }:
    {
      wrappers.neovim = lib.mkAfter [
        {
          passthru.settings.lsp = {
            nixd = _: {
              package = pkgs.nixd;
              cmd = mkLuaInline ''
                function(dispatchers, config)
                  return vim.lsp.rpc.start({ "nixd" }, dispatchers, { cwd = config.root_dir })
                end
              '';
              filetypes = [ "nix" ];
              root_markers = [
                "flake.nix"
                ".git"
              ];
              settings.nixd = {
                nixpkgs.expr = "import ${pkgs.path} { }";
                formatting.command = [ (lib.getExe pkgs.nixfmt) ];
                options = {
                  nixos.expr = fromFlake "nixos";
                  flake-parts.expr = fromFlake "flake-parts";
                  perSystem.expr = fromFlake "perSystem";
                };
              };
            };

            marksman = _: {
              package = pkgs.marksman;
              cmd = [
                "marksman"
                "server"
              ];
              filetypes = [ "markdown" ];
              root_markers = [
                ".marksman.toml"
                ".git"
              ];
            };
          };
        }
      ];
    };
}
