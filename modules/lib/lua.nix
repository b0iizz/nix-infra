# Nix values as Lua source, for generated Lua configs (Hyprland).
#
#   toLua { a = [ 1 "x" ]; b.c = null; }   ->   { a = { 1, "x" }, b = { c = nil } }
#   toLua (raw "hl.dsp.window.close()")    ->   hl.dsp.window.close()
#
# Strings go through `builtins.toJSON`, which is a valid Lua string literal
# except for the `\uXXXX` it emits for control characters (Lua wants
# `\u{XXXX}`): ponytail: keep control characters out of generated strings.
{ lib, ... }:
let
  keywords = [
    "and"
    "break"
    "do"
    "else"
    "elseif"
    "end"
    "false"
    "for"
    "function"
    "goto"
    "if"
    "in"
    "local"
    "nil"
    "not"
    "or"
    "repeat"
    "return"
    "then"
    "true"
    "until"
    "while"
  ];

  key =
    k:
    if builtins.match "[A-Za-z_][A-Za-z0-9_]*" k != null && !(builtins.elem k keywords) then
      k
    else
      "[${builtins.toJSON k}]";

  toLua =
    v:
    if v == null then
      "nil"
    else if builtins.isAttrs v && v ? __raw then
      v.__raw
    else if builtins.isAttrs v then
      "{ ${lib.concatStringsSep ", " (lib.mapAttrsToList (k: x: "${key k} = ${toLua x}") v)} }"
    else if builtins.isList v then
      "{ ${lib.concatStringsSep ", " (map toLua v)} }"
    else
      builtins.toJSON v;
in
{
  flake.lib.lua = {
    inherit toLua;
    raw = expr: { __raw = expr; };
  };
}
