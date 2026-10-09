# git, wrapped: defaults that apply to every user, and the state git keeps in
# the home directory.
#
#   settings.config   git config options (nested attrs, as in a gitconfig),
#                     deep-merged over the defaults below
#
# The defaults are the *system* config, so `programs.git.config` (which NixOS
# writes to /etc/gitconfig) is included after them and wins over them, and a
# user's own config wins over both.
#
# `git config --global` always writes to ~/.config/git/config, a directory that
# is kept across reboots on hosts with `disko-root-impermanence`. (~/.gitconfig
# would have to be a bind-mounted file, which git can't replace when it saves.)
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  program = pkgs: [
    (w.withPackage pkgs.git)
    {
      passthru.settings.config = _: {
        init.defaultBranch = "main";
        pull.ff = "only";
      };
      passthru.persist.directories = old: old ++ [ ".config/git" ];
      # only `git` itself; its helpers are found through the package
      passthru.wrapper.exes = _: [ "git" ];
    }
    (final: {
      passthru.files."gitconfig" =
        _:
        (w.fileHelpers pkgs).text ''
          ${lib.generators.toGitINI final.passthru.settings.config}
          [include]
          	path = /etc/gitconfig
        '';

      passthru.wrapper.env.GIT_CONFIG_SYSTEM.__assign = final.passthru.config.file."gitconfig";
      passthru.wrapper.extraArgs.__append = [
        "--run"
        ''export GIT_CONFIG_GLOBAL="''${XDG_CONFIG_HOME:-$HOME/.config}/git/config"''
      ];
    })
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrappers.git = w.program (program pkgs);
    };
}
