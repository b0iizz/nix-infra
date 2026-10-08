# Feature: hot reloading via a NixOS activation script.
#
#   passthru.reload      null | "SIGHUP" | {
#                          signal ? null;      # sent to running instances
#                          exec ? null;        # run as each logged-in user
#                          pattern ? <regex>;  # matched against the full
#                                              # command line, default: the
#                                              # program name
#                          users ? null;       # restrict `exec` to these users
#                          environment ? { };  # extra env for `exec`
#                        }
#
# Setting `reload` implies `passthru.live` (see files.nix). Not reloading means
# the store path is baked in, nothing lands in /run and there is no activation
# script.
#
#   passthru.activation  system.activationScripts fragment, empty unless
#                        `live`: it keeps the live symlink pointing at the
#                        current config and, when that changes, reloads
#                        running instances. Use `self.lib.wrappers.collect` to
#                        merge those of several wrappers into a NixOS config.
#
# The pattern is matched against the full command line and not `comm`:
# wrappers exec `.<prog>-wrapped`, so `pkill -x <prog>` would never match, and
# `comm` is truncated to 15 characters.
{ lib, ... }:
let
  feature = pkgs: [
    { passthru.reload = _: null; }
    (
      final:
      let
        p = final.passthru;
        name = p.wrapperName;
        liveDir = "${p.liveRoot}/${name}";
        tree = p.config.store;
        program = p.package.meta.mainProgram or (lib.getName p.package);

        rc =
          if p.reload == null then
            null
          else if lib.isString p.reload then
            { signal = p.reload; }
          else
            p.reload;

        pattern = rc.pattern or "(^|/)${program}([[:space:]]|$)";
        users = rc.users or null;
        userArg = lib.optionalString (
          users != null
        ) "--uid ${lib.escapeShellArg (lib.concatStringsSep "," users)}";

        runAsUsers = cmd: ''
          for uid in $(${pkgs.systemd}/bin/loginctl list-users --no-legend | ${pkgs.gawk}/bin/awk '{ print $1 }'); do
            [ -d "/run/user/$uid" ] || continue
            user=$(id -nu "$uid" 2>/dev/null) || continue
            ${lib.optionalString (users != null) ''
              case " ${lib.concatStringsSep " " users} " in
                *" $user "*) ;;
                *) continue ;;
              esac
            ''}
            ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
              XDG_RUNTIME_DIR="/run/user/$uid" \
              DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
              ${
                lib.concatStringsSep " " (
                  lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg (toString v)}") (rc.environment or { })
                )
              } \
              ${cmd} || true
          done
        '';

        reloadScript = lib.concatStringsSep "\n" (
          [ ''echo "${name}: configuration changed, reloading running instances" >&2'' ]
          ++ lib.optional ((rc.signal or null) != null) ''
            ${pkgs.procps}/bin/pkill --signal ${rc.signal} --full ${userArg} ${lib.escapeShellArg pattern} || true
          ''
          ++ lib.optional ((rc.exec or null) != null) (runAsUsers rc.exec)
        );
      in
      {
        passthru.live = _: p.reload != null;

        passthru.activation =
          _:
          lib.optionalAttrs p.live {
            "wrapped-${name}" = {
              deps = [ "specialfs" ];
              text = ''
                install -d -m 0755 ${p.liveRoot}
                previous=$(readlink ${liveDir} 2>/dev/null || true)
                ln -sfnT ${tree} ${liveDir}
                ${lib.optionalString (rc != null) ''
                  if [ -n "$previous" ] && [ "$previous" != "${tree}" ]; then
                    ${reloadScript}
                  fi
                ''}
              '';
            };
          };
      }
    )
  ];
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrapperExtensions = lib.mkOrder 200 (feature pkgs);
    };
}
