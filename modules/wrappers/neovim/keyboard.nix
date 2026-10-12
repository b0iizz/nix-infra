# Neovim on a German (QWERTZ) keyboard: `[ ] { } \` are AltGr chords there,
# and CTRL-] rarely reaches the terminal. The umlauts take their place in
# Normal, Visual and Operator-pending mode (Insert mode still types them):
#
#   ö ä   [ ]      every [x / ]x: öd/äd previous/next diagnostic, öD/äD first/last
#   Ö Ä   { }      previous/next paragraph
#   ü     CTRL-]   go to definition (through the LSP's 'tagfunc'), CTRL-O back
#   ,     <Leader>
#
# ö and ä remap, so they reach the [x/]x mappings Neovim and plugins define.
# Extends `wrappers.neovim` (default.nix) after its own definition.
{ lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      wrappers.neovim = lib.mkAfter [
        {
          passthru.settings.init = old: ''
            ${old}
            vim.g.mapleader = ","
            vim.g.maplocalleader = ","
            for from, to in pairs({ ["ö"] = "[", ["ä"] = "]", ["Ö"] = "{", ["Ä"] = "}", ["ü"] = "<C-]>" }) do
              vim.keymap.set({ "n", "x", "o" }, from, to, { remap = true })
            end
          '';
        }
      ];

      # äd/öd reach Neovim's own ]d/[d, and Ä/Ö move by paragraph.
      checks.neovim-keyboard =
        let
          test = pkgs.writeText "test.lua" ''
            local ok, err = pcall(function()
              vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "", "b", "c", "", "d" })
              local ns = vim.api.nvim_create_namespace("test")
              vim.diagnostic.set(ns, 0, {
                { lnum = 2, col = 0, message = "x" },
                { lnum = 5, col = 0, message = "y" },
              })
              local function line(keys)
                vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
                return vim.api.nvim_win_get_cursor(0)[1]
              end
              assert(line("gg") == 1)
              assert(line("äd") == 3, "äd is not ]d")
              assert(line("äd") == 6, "äd is not ]d")
              assert(line("öd") == 3, "öd is not [d")
              assert(line("Ä") == 5, "Ä is not }")
              assert(line("Ö") == 2, "Ö is not {")
              assert(vim.g.mapleader == ",")
            end)
            if not ok then
              io.stderr:write(tostring(err) .. "\n")
              vim.cmd("cquit 1")
            end
            vim.cmd("qall!")
          '';
        in
        pkgs.runCommand "check-neovim-keyboard" { } ''
          export HOME=$TMPDIR
          timeout 60 ${lib.getExe config.packages.neovim} --headless -c "luafile ${test}"
          touch $out
        '';
    };
}
