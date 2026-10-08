# Wrapper library: a wrapper is a derivation with no package set, customised by
# an ordered list of infusions (github:amjoseph/infuse.nix).
#
#   wrappers.mkWrapper pkgs "yazi" [
#     (wrappers.withPackage pkgs.yazi)
#     { passthru.settings.manager.ratio = _: [ 1 3 4 ]; }
#     (final: { passthru.wrapper.env.YAZI_CONFIG_HOME.__assign = "${cfg final}"; })
#   ]
#
# An extension is an infusion on the *attributes* of the wrapper derivation
# (i.e. infuse's `__output`/`.overrideAttrs`), in one of three forms:
#
#   attrset        deep-infused into the previous attributes
#   final: infusion   same, but may read the fixpoint (`final.passthru.settings`)
#   list           applied in order; may be nested
#
# Plain values are not allowed as leaves: write `x = _: v` or `x.__assign = v`.
# An attrset infusion computes its values from the previous layer and so does
# not follow later changes; derive from other settings with the `final:` form.
#
# The base derivation exposes three override levels, from structured to raw:
#
#   passthru.settings   free-form data for the program
#   passthru.wrapper    env, envDefault, prefix, suffix, flags, exes, extraArgs,
#                       binary (compiled wrappers, no `--run`),
#                       fixDesktopEntries (default true)
#   wrapperArgs, buildCommand, meta, ... (plain derivation attributes)
#
# Programs that read their config from a file render it into
# `passthru.wrapper` from `final.passthru.settings`; programs with their own
# builder replace `buildCommand`. Both are just extensions.
#
# Every wrapper built through `perSystem.wrappers` also gets the global features
# in modules/wrappers/ (`wrapperExtensions`): `passthru.files`/`path`/`live`
# (files.nix) and `passthru.reload`/`activation` (activation.nix). The helpers
# they use (`fileHelpers`, `toFile`, `tree`, `withFiles`, `withPath`,
# `withReload`, `collect`) are at the end of this file.
{ withInputs, lib, ... }:
withInputs
  {
    infuse = {
      url = "git+https://codeberg.org/amjoseph/infuse.nix?ref=trunk";
      flake = false;
    };
  }
  (
    { inputs, ... }:
    let
      infuse = (import inputs.infuse { inherit lib; }).v1.infuse;

      # Turn extensions into one infusion for the wrapper derivation.
      toInfusion =
        ext:
        if builtins.isList ext then
          map toInfusion ext
        else if builtins.isFunction ext then
          { __output = final: prev: infuse prev (ext final); }
        else
          { __output = ext; };

      extendWith = drv: exts: infuse drv (toInfusion exts);

      mkBase =
        pkgs: wrapperName:
        pkgs.stdenvNoCC.mkDerivation (
          final:
          let
            pkg = final.passthru.package;
            w = final.passthru.wrapper;
            pairs = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
            joined = k: v: [
              k
              ":"
              (lib.concatStringsSep ":" v)
            ];
            makeWrapperCmd = if w.binary then "makeBinaryWrapper" else "makeWrapper";
            wrapsExe =
              if w.exes == null then
                "true"
              else
                ''[[ " ${lib.concatStringsSep " " w.exes} " == *" $exeName "* ]]'';
          in
          {
            # `meta` must not depend on the package: stdenv forces the
            # unextended meta too, which would throw for an unset package.
            # `withPackage` sets it.
            name = pkg.name;
            meta = { };
            dontUnpack = true;
            nativeBuildInputs = [ (if w.binary then pkgs.makeBinaryWrapper else pkgs.makeWrapper) ];

            passthru = {
              inherit wrapperName;
              package = throw "wrapper '${wrapperName}': no package set (add `withPackage <pkg>` to its extensions)";
              settings = { };
              wrapper = {
                env = { };
                envDefault = { };
                prefix = { };
                suffix = { };
                flags = [ ];
                exes = null; # null: wrap every executable in bin/
                extraArgs = [ ];
                # compiled instead of shell wrappers: faster, but no `--run`
                binary = false;
                # make .desktop files launch the wrapper, not the package
                fixDesktopEntries = true;
              };
              extend = ext: extendWith final.finalPackage ext;
            };

            wrapperArgs = lib.escapeShellArgs (
              pairs (k: v: [
                "--set"
                k
                v
              ]) w.env
              ++ pairs (k: v: [
                "--set-default"
                k
                v
              ]) w.envDefault
              ++ pairs (k: v: [ "--prefix" ] ++ joined k v) w.prefix
              ++ pairs (k: v: [ "--suffix" ] ++ joined k v) w.suffix
              ++ lib.concatMap (f: [
                "--add-flags"
                f
              ]) w.flags
              ++ w.extraArgs
            );

            buildCommand = ''
              mkdir -p "$out/bin"
              for entry in ${pkg}/*; do
                [ "$(basename "$entry")" = bin ] || ln -s "$entry" "$out/"
              done
              for exe in ${pkg}/bin/*; do
                exeName="$(basename "$exe")"
                if ${wrapsExe}; then
                  ${makeWrapperCmd} "$exe" "$out/bin/$exeName" ${final.wrapperArgs}
                else
                  ln -s "$exe" "$out/bin/$exeName"
                fi
              done
              ${lib.optionalString w.fixDesktopEntries ''
                if [ -d ${pkg}/share/applications ]; then
                  # share/ and share/applications are symlinks into the package;
                  # open them up so the .desktop files can be rewritten
                  rm "$out/share"
                  mkdir "$out/share"
                  for entry in ${pkg}/share/*; do
                    [ "$(basename "$entry")" = applications ] || ln -s "$entry" "$out/share/"
                  done
                  mkdir "$out/share/applications"
                  for entry in ${pkg}/share/applications/*; do
                    entryName="$(basename "$entry")"
                    case "$entryName" in
                      *.desktop)
                        install -m 0644 "$(readlink -f "$entry")" "$out/share/applications/$entryName"
                        substituteInPlace "$out/share/applications/$entryName" \
                          --replace-quiet "${pkg}/bin/" "$out/bin/"
                        ;;
                      *) ln -s "$entry" "$out/share/applications/" ;;
                    esac
                  done
                fi
              ''}
            '';
          }
        );
    in
    {
      flake.lib.wrappers = rec {
        inherit infuse mkBase extendWith;

        # mkWrapper pkgs name extensions -> derivation (with `.extend`)
        mkWrapper =
          pkgs: name: exts:
          extendWith (mkBase pkgs name) exts;

        # Sets the wrapped package (and the meta that follows from it).
        withPackage = package: {
          passthru.package.__assign = package;
          meta.__assign = package.meta or { };
        };

        # Order a program's own extensions before host and user extensions
        # defined in other modules, independent of file order.
        program = lib.mkOrder 100;

        # ---- files (used by the `files` feature, modules/wrappers/files.nix)
        #
        # A file's content is anything `toFile` understands: a string
        # (verbatim), a path or derivation (as is), `{ text }`, `{ source }`,
        # or a function `name -> path`, which is what the format helpers return.
        fileHelpers =
          pkgs:
          let
            formats = {
              json = pkgs.formats.json { };
              yaml = pkgs.formats.yaml { };
              toml = pkgs.formats.toml { };
              ini = pkgs.formats.ini { };
              iniList = pkgs.formats.ini { listsAsDuplicateKeys = true; };
              keyValue = pkgs.formats.keyValue { };
            };
            generate =
              format: value: name:
              format.generate (baseNameOf name) value;
          in
          {
            inherit formats;
            json = generate formats.json;
            yaml = generate formats.yaml;
            toml = generate formats.toml;
            ini = generate formats.ini;
            iniList = generate formats.iniList;
            keyValue = generate formats.keyValue;
            text = value: name: pkgs.writeText (baseNameOf name) value;
            lines = value: name: pkgs.writeText (baseNameOf name) (lib.concatStringsSep "\n" (value ++ [ "" ]));
          };

        toFile =
          pkgs: name: content:
          if lib.isFunction content then
            content name
          else if lib.isDerivation content || builtins.isPath content then
            content
          else if lib.isString content then
            pkgs.writeText (baseNameOf name) content
          else if lib.isAttrs content && content ? source then
            content.source
          else if lib.isAttrs content && content ? text then
            pkgs.writeText (baseNameOf name) content.text
          else
            throw "wrappers: don't know how to turn `${name}` into a file";

        # tree pkgs name { "rel/path" = content; } -> a directory of symlinks
        tree =
          pkgs: name: files:
          pkgs.linkFarm "${name}-config" (
            lib.mapAttrsToList (n: c: {
              name = n;
              path = toFile pkgs n c;
            }) files
          );

        # ---- extension constructors
        #
        # Plain values are not valid infusion leaves, so these wrap them.
        withFiles = files: {
          passthru.files = lib.mapAttrs (
            _: content: _:
            content
          ) files;
        };
        withPath = path: { passthru.path = _: path; };
        withReload = reload: { passthru.reload = _: reload; };

        # collect [ wrapper ... ] -> NixOS config fragment: installs the
        # packages and merges their `passthru.activation`.
        collect = wrapped: {
          environment.systemPackages = wrapped;
          system.activationScripts = lib.foldl' (acc: p: acc // (p.passthru.activation or { })) { } wrapped;
        };
      };
    }
  )
