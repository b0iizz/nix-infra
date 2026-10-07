{ inputs, ... }:
{
  imports = [ inputs.make-shell.flakeModules.default ];

  flake-file.inputs = {
    make-shell.url = "github:/nicknovitski/make-shell";
  };

  perSystem.make-shells.default = { pkgs, ... }: {
    packages = with pkgs; [
      git
      jq
      curl
      wget
    ];

    # A function, not a script: `exec` must replace the enclosing shell itself.
    shellHook = ''
      reload-shell() {
        local shell="''${1:-default}" root system
        root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || return 1
        system="$(nix eval --impure --raw --expr builtins.currentSystem)" || return 1

        echo "reload-shell: building devShells.$system.$shell ..."
        if ! nix build --no-link "$root#devShells.$system.$shell"; then
          echo "reload-shell: build failed, keeping current shell" >&2
          return 1
        fi

        echo "reload-shell: build succeeded, replacing shell"
        exec nix develop "$root#$shell" --command "''${SHELL:-bash}"
      }
    '';
  };
}
