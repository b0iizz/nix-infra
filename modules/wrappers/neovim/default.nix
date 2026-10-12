# Neovim, wrapped: `nvim -u <init.lua>`, with every plugin from the Nix store
# and loaded, at startup or lazily, by lz.n (github:nvim-neorocks/lz.n).
# ~/.config/nvim is not read.
#
#   settings.init      Lua run first, before any plugin: options, leader keys
#   settings.plugins   name -> null (no plugin) | {
#                        package   a vimPlugins derivation
#                        config    Lua run once the plugin is loaded (optional)
#                        ...       any other lz.n spec field, as Nix data:
#                                  event, cmd, ft, keys, colorscheme, lazy,
#                                  priority, before, ... A trigger makes the
#                                  plugin lazy; without one it loads at startup.
#                                  `keys` is a list of lhs strings or of
#                                  { lhs; rhs; mode; desc; ... }.
#                                  Lua functions: lib.generators.mkLuaInline.
#                      }
#
#   passthru.settings.plugins.telescope = _: {
#     package = pkgs.vimPlugins.telescope-nvim;
#     cmd = "Telescope";
#     keys = [ { lhs = "<leader>ff"; rhs = "<cmd>Telescope find_files<cr>"; } ];
#     config = ''require("telescope").setup({})'';
#   };
#
# The colors come from `passthru.theme` (theme.nix) through base16-nvim, as
# `settings.plugins.base16-nvim`. Groups drawn in base00 get no background, so
# the terminal's (and its opacity) shows through.
#
# ponytail: lz.n has no `dependencies`. A plugin's own dependencies (vim
# plugins, Lua modules like telescope's plenary) are always there from startup,
# so don't give them a lazy spec too.
{ self, lib, ... }:
let
  w = self.lib.wrappers;
  inherit (lib.generators) toLua mkLuaInline;

  program = pkgs: [
    (w.withPackage pkgs.neovim-unwrapped)
    {
      passthru.settings = {
        init = _: "";
        plugins = _: { };
      };
      passthru.persist.directories = old: old ++ [ ".local/state/nvim" ];
      passthru.wrapper.exes = _: [ "nvim" ];
    }
    (
      final:
      let
        t = final.passthru.theme;
        c = self.lib.theme.hash t.colors;
      in
      {
        passthru.settings.plugins.base16-nvim = _: {
          package = pkgs.vimPlugins.base16-nvim;
          lazy = false;
          priority = 1000;
          config = ''
            require("base16-colorscheme").setup(${toLua { } c})
            vim.o.background = ${toLua { } t.polarity}
            for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
              if hl.bg == ${toString (lib.fromHexString t.colors.base00)} then
                hl.bg = nil
                hl.ctermbg = nil
                vim.api.nvim_set_hl(0, name, hl)
              end
            end
          '';
        };
      }
    )
    (
      final:
      let
        s = final.passthru.settings;
        plugins = lib.filterAttrs (_: p: p != null) s.plugins;

        # a plugin's directory in the pack, which lz.n `packadd`s
        dirName = p: lib.getName p.package;
        packages = [ pkgs.vimPlugins.lz-n ] ++ map (p: p.package) (lib.attrValues plugins);
        pack = pkgs.vimUtils.packDir { wrapper.opt = packages; };
        # what nixpkgs' own wrapper adds for plugins built as Lua rocks
        # (telescope's plenary) and for programs plugins run
        lua = pkgs.neovim-unwrapped.lua;
        luaEnv = lua.withPackages (_: lib.concatMap (p: p.requiredLuaModules or [ ]) packages);
        runtimeDeps = lib.concatMap (p: p.runtimeDeps or [ ]) packages;
        specs = lib.mapAttrs' (
          _: p:
          lib.nameValuePair (dirName p) (
            removeAttrs p [
              "package"
              "config"
            ]
            // lib.optionalAttrs ((p.config or "") != "") {
              after = mkLuaInline "function()\n${p.config}\nend";
            }
          )
        ) plugins;
      in
      {
        passthru.files."init.lua" = _: ''
          package.path = ${toLua { } (lua.pkgs.getLuaPath luaEnv)} .. ";" .. package.path
          package.cpath = ${toLua { } (lua.pkgs.getLuaCPath luaEnv)} .. ";" .. package.cpath
          vim.opt.packpath:prepend(${toLua { } "${pack}"})
          vim.cmd.packadd("lz.n")

          ${s.init}

          -- lz.n reads the plugin name, and a key's lhs and rhs, by position,
          -- which Nix data can't express
          local specs = ${toLua { } specs}
          for name, spec in pairs(specs) do
            spec[1] = name
            for _, key in ipairs(spec.keys or {}) do
              if type(key) == "table" then
                key[1], key[2], key.lhs, key.rhs = key.lhs, key.rhs, nil, nil
              end
            end
          end
          require("lz.n").load(vim.tbl_values(specs))
        '';

        passthru.wrapper.flags.__append = [ "-u ${final.passthru.config.file."init.lua"}" ];
        passthru.wrapper.suffix = lib.optionalAttrs (runtimeDeps != [ ]) {
          PATH = _: [ (lib.makeBinPath runtimeDeps) ];
        };
      }
    )
  ];
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      wrappers.neovim = w.program (program pkgs);

      # A lazy plugin loads on its trigger, an eager one's config can require
      # its dependencies, and the theme colors reach the highlight groups.
      checks.neovim =
        let
          # sets vim.g.<name> when loaded, and has a command `Probe`
          probe =
            name:
            pkgs.writeTextFile {
              inherit name;
              destination = "/plugin/${name}.lua";
              text = ''
                vim.g.${name} = true
                vim.api.nvim_create_user_command("Probe", function() end, { force = true })
              '';
            };
          nvim = config.packages.neovim.extend {
            passthru.theme.colors.base05 = _: "123456";
            passthru.settings.plugins = {
              probe = _: {
                package = probe "probe";
                cmd = "Probe";
                config = "vim.g.probe_after = true";
              };
              keyprobe = _: {
                package = probe "keyprobe";
                keys = [
                  {
                    lhs = "<leader>p";
                    rhs = mkLuaInline "function() vim.g.keyprobe_rhs = true end";
                    desc = "probe";
                  }
                ];
              };
              telescope = _: {
                package = pkgs.vimPlugins.telescope-nvim;
                config = ''
                  require("plenary.path")
                  require("telescope").setup({})
                  vim.g.telescope_after = true
                '';
              };
            };
          };
          test = pkgs.writeText "test.lua" ''
            local ok, err = pcall(function()
              assert(vim.g.probe == nil, "lazy plugin loaded at startup")
              vim.cmd("Probe")
              assert(vim.g.probe and vim.g.probe_after, "lazy plugin or its config not loaded")
              assert(vim.g.keyprobe == nil, "key-triggered plugin loaded at startup")
              vim.api.nvim_feedkeys(vim.keycode("<leader>p"), "x", false)
              assert(vim.g.keyprobe and vim.g.keyprobe_rhs, "key-triggered plugin or its rhs not run")
              assert(vim.g.telescope_after, "eager plugin's config, with its dependency, didn't run")
              -- startup errors (lz.n reports failed hooks) go here, not to stderr
              local messages = vim.api.nvim_exec2("messages", { output = true }).output
              assert(not messages:find("Error") and not messages:find("Failed"), messages)
              local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
              assert(normal.fg == 0x123456, "Normal fg is not base05")
              assert(normal.bg == nil, "Normal has a background")
            end)
            if not ok then
              io.stderr:write(tostring(err) .. "\n")
              vim.cmd("cquit 1")
            end
            vim.cmd("qall!")
          '';
        in
        pkgs.runCommand "check-neovim" { } ''
          export HOME=$TMPDIR
          ${lib.getExe nvim} --headless -c "luafile ${test}" 2> err
          cat err
          # an error in init.lua doesn't change nvim's exit code, only stderr
          [ ! -s err ]
          touch $out
        '';
    };
}
