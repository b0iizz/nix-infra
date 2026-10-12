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
#   settings.lsp       server -> null (off) | {
#                        package   the server, appended to PATH, so a project
#                                  shell's own server wins (optional: without
#                                  it the server must come from PATH)
#                        ...       vim.lsp.Config fields (cmd, filetypes,
#                                  settings, ...), merged over nvim-lspconfig's
#                                  lsp/<server>.lua, so the name is lspconfig's
#                      }
#
# Every server is enabled; one whose command isn't on PATH stays off (noted in
# :LspLog). The servers this repo edits are configured in languages.nix.
# Completion is blink.cmp (`settings.plugins.blink-cmp`): servers, paths,
# buffer words and friendly-snippets' snippets, with its default keymap
# (CTRL-Y accepts). LSP keymaps and diagnostics are Neovim's defaults
# (:help lsp-defaults).
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
        plugins = _: {
          # the servers' default configs (lsp/*.lua)
          nvim-lspconfig.package = pkgs.vimPlugins.nvim-lspconfig;
          # eager: it gives every server its capabilities when it loads
          blink-cmp = {
            package = pkgs.vimPlugins.blink-cmp;
            config = ''
              require("blink.cmp").setup({
                keymap = { preset = "default" },
                completion = { documentation = { auto_show = true } },
                signature = { enabled = true },
              })
            '';
          };
          # found on the runtimepath by blink's snippet source
          friendly-snippets.package = pkgs.vimPlugins.friendly-snippets;
        };
        lsp = _: { };
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

        servers = lib.filterAttrs (_: v: v != null) s.lsp;
        serverPackages = lib.filter (p: p != null) (map (v: v.package or null) (lib.attrValues servers));
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

          -- after the plugins: a server's config is resolved from the
          -- runtimepath, where nvim-lspconfig must be by then
          for name, config in pairs(${
            toLua { } (lib.mapAttrs (_: v: removeAttrs v [ "package" ]) servers)
          }) do
            vim.lsp.config(name, config)
            vim.lsp.enable(name)
          end
        '';

        passthru.wrapper.flags.__append = [ "-u ${final.passthru.config.file."init.lua"}" ];
        passthru.wrapper.suffix = lib.optionalAttrs (runtimeDeps ++ serverPackages != [ ]) {
          PATH = _: [ (lib.makeBinPath (runtimeDeps ++ serverPackages)) ];
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
      # its dependencies, the theme colors reach the highlight groups, the
      # servers of languages.nix attach, and blink offers nix snippets.
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
            # the flake's options can't be evaluated in the sandbox
            passthru.settings.lsp.nixd.settings.nixd.options = _: { };
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
            local function step(f)
              local ok, err = pcall(f)
              if not ok then
                io.stderr:write(tostring(err) .. "\n")
                vim.cmd("cquit 1")
              end
              return ok
            end

            local ok = step(function()
              assert(vim.g.probe == nil, "lazy plugin loaded at startup")
              vim.cmd("Probe")
              assert(vim.g.probe and vim.g.probe_after, "lazy plugin or its config not loaded")
              assert(vim.g.keyprobe == nil, "key-triggered plugin loaded at startup")
              vim.api.nvim_feedkeys(vim.keycode("<leader>p"), "x", false)
              assert(vim.g.keyprobe and vim.g.keyprobe_rhs, "key-triggered plugin or its rhs not run")
              assert(vim.g.telescope_after, "eager plugin's config, with its dependency, didn't run")
              local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
              assert(normal.fg == 0x123456, "Normal fg is not base05")
              assert(normal.bg == nil, "Normal has a background")
              local function attaches(file, server)
                vim.cmd.edit(os.getenv("TMPDIR") .. "/" .. file)
                assert(vim.wait(20000, function()
                  return #vim.lsp.get_clients({ name = server, bufnr = 0 }) > 0
                end), server .. " did not attach")
              end
              attaches("test.md", "marksman")
              attaches("test.nix", "nixd")
              vim.o.showmode = false
            end)

            -- Type `let` and accept blink's snippet. Typed input is only read
            -- by the main loop, hence nvim_input and the deferred checks.
            if ok then
              local cmp = require("blink.cmp")
              vim.api.nvim_input("ilet")
              vim.defer_fn(function()
                step(function()
                  local index
                  for i, item in ipairs(cmp.get_items()) do
                    if item.source_id == "snippets" and item.label == "let" then
                      index = i
                    end
                  end
                  assert(index, "blink's menu has no `let` snippet")
                  cmp.accept({ index = index })
                  vim.defer_fn(function()
                    step(function()
                      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
                      assert(text:find("^let\n.*\nin"), "`let` expanded to " .. vim.inspect(text))
                      vim.cmd("qall!")
                    end)
                  end, 1000)
                end)
              end, 3000)
            end
          '';
        in
        pkgs.runCommand "check-neovim" { } ''
          export HOME=$TMPDIR
          timeout 120 ${lib.getExe nvim} --headless -c "luafile ${test}" 2> err || touch failed
          cat err
          [ ! -e failed ]
          # A startup error (a failed `config`) changes neither the exit code
          # nor :messages, and reaches stderr only if the event loop ran (the
          # nixd wait). Every `config` in the test therefore sets a flag the
          # test asserts.
          [ ! -s err ]
          touch $out
        '';
    };
}
