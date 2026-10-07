# Declare flake inputs and gate a module on their presence in the generated
# flake.nix, so a new module can be added in the same step as its input and
# `nix run .#write-flake` still evaluates.
#
# Provided to every module as the `withInputs` specialArg (see the flake
# `outputs` in modules/flake-root.nix), so no relative path is needed:
#
#   { withInputs, ... }:
#   withInputs { make-shell.url = "github:nicknovitski/make-shell"; } (
#     { inputs, ... }: {
#       imports = [ inputs.make-shell.flakeModules.default ];
#       ...
#     }
#   )
#
# This must stay out of `config` (e.g. `flake.lib`): `imports` may not depend
# on `config`, so anything reached through it recurses infinitely. Only
# `specialArgs` are safe there.
#
# The `flake-file.inputs` declaration is always emitted. The body (a module, a
# module function, or a path) is only imported once every declared input exists
# in `inputs`; until then a trace tells you to regenerate.
inputs: decls: body:
let
  missing = builtins.filter (name: !(inputs ? ${name})) (builtins.attrNames decls);
in
{
  flake-file.inputs = decls;
  imports =
    if missing == [ ] then
      [ body ]
    else
      builtins.trace
        "with-inputs: skipping module, inputs not in flake.nix yet: ${toString missing} (run `nix run .#write-flake`)"
        [ ];
}
