{
  lib,
  config,
  self,
  ...
}:
let
  rcfg = config.registry;

  # The CLI works on the checked-out repository, not on the store copy.
  relPath = p: lib.removePrefix (toString self) (toString p);

  hostsData = lib.mapAttrs (_name: host: {
    # Committed ssh host public key; deploys pin it when present.
    pub = relPath (host.path + "/host.pub");
    hasPub = builtins.pathExists (host.path + "/host.pub");
    target = host.deploy.targetHost;
    user = host.deploy.targetUser;
    sshOpts = host.deploy.sshOpts;
    buildOnTarget = host.deploy.buildOnTarget;
    # A host may belong to any number of groups.
    groups = lib.unique host.deploy.groups;
  }) (lib.filterAttrs (_: host: host.enable) rcfg.hosts);
in
{
  # The CLI reads this live (`nix eval .#deployData`), so new hosts and group
  # changes are known at once, without rebuilding the tool.
  flake.deployData = hostsData;

  perSystem =
    { pkgs, ... }:
    let
      # Static lists: only used for tab completion, so staleness is fine.
      hostNames = pkgs.writeText "deploy-hosts" (lib.concatStringsSep "\n" (lib.attrNames hostsData));
      groupNames = pkgs.writeText "deploy-groups" (
        lib.concatMapStringsSep "\n" (g: "@${g}") (
          lib.unique (lib.concatMap (h: h.groups) (lib.attrValues hostsData))
        )
      );

      completion = pkgs.writeText "deploy.bash" ''
        _deploy() {
          local cur=''${COMP_WORDS[COMP_CWORD]} prev=''${COMP_WORDS[COMP_CWORD-1]}
          local cmd=''${COMP_WORDS[1]:-} opts=""

          if [ "$COMP_CWORD" -eq 1 ]; then
            mapfile -t COMPREPLY < <(compgen -W "list build plan switch boot test dry-activate completion help" -- "$cur")
            return
          fi
          [ "$prev" = --target ] || [ "$prev" = -j ] && return

          case $cmd in
            build | plan | switch | boot | test | dry-activate)
              opts="--all --local --target --build-on-target --build-local --keep-going -j" ;;
            completion)
              mapfile -t COMPREPLY < <(compgen -W "bash" -- "$cur")
              return
              ;;
          esac

          if [[ $cur == -* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
            return
          fi

          case $cmd in
            build | plan | switch | boot | test | dry-activate)
              mapfile -t COMPREPLY < <(compgen -W "$(cat ${hostNames}) $(cat ${groupNames})" -- "$cur")
              ;;
          esac
        }
        complete -F _deploy deploy
      '';

      deploy-script = pkgs.writeShellApplication {
        name = "deploy";
        runtimeInputs = [
          pkgs.nixos-rebuild
          pkgs.nix
          pkgs.openssh
          pkgs.jq
          pkgs.gitMinimal
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = ''
          usage() {
            cat <<'EOF'
          Usage: deploy <command> [options] <host|@group>... | --all

          Updates installed machines with nixos-rebuild. (First installs:
          see `provision`; ssh host keys: see `host-keys`.)

          Commands:
            list                  Hosts, targets and groups
            build                 Build only, here; no target is contacted
            plan                  Build, then show what would change
            switch                Build, activate now, make it the boot default
            boot                  Make it the boot default, do not activate
            test                  Activate now, leave the bootloader alone
            dry-activate          Show what activation would do
            completion bash       source <(deploy completion bash)
            help

          Selectors (combinable, duplicates removed):
            <host>                one host
            @<group>              every host in the group (a host can be in
                                  several groups)
            --all                 every host

          Options:
            --target [user@]addr  override the registry target (one host only)
            --local               deploy to this machine
            --build-on-target     build on the target machine
            --build-local         build here (default: registry buildOnTarget)
            --keep-going          do not stop at the first failing host
            -j N                  deploy N hosts in parallel (default 1;
                                  implies --keep-going)
            -- args               passed on to nixos-rebuild (--show-trace ...)

          A host without deploy.targetHost, or named like this machine, is
          deployed locally. A target user other than root uses sudo.

          Host keys: if the host has a committed host.pub, ssh only accepts
          exactly that key (known_hosts is generated from it). Without one it
          falls back to accept-new; see `host-keys`.

          Environment:
            FLAKE_ROOT  repository root (default: git toplevel or cwd)

          Examples:
            deploy plan web1
            deploy switch @servers --build-local -j 4
            deploy boot --all
          EOF
          }

          die() { echo "deploy: $*" >&2; exit 1; }
          info() { echo "deploy: $*" >&2; }

          root=''${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
          export FLAKE_ROOT=$root

          data=
          load_data() {
            [ -n "$data" ] || data=$(nix eval --json "$root#deployData") ||
              die "cannot evaluate $root#deployData"
          }
          field() { load_data; jq -r --arg h "$1" --arg k "$2" '.[$h][$k] // empty' <<<"$data"; }
          all_hosts() { load_data; jq -r 'keys[]' <<<"$data"; }
          group_hosts() {
            load_data
            jq -r --arg g "$1" 'to_entries[] | select(.value.groups | index($g)) | .key' <<<"$data"
          }
          is_host() { load_data; jq -e --arg h "$1" 'has($h)' <<<"$data" >/dev/null; }

          # -- selection ---------------------------------------------------

          hosts=()
          target=
          force_local=0
          build_mode=default
          keep_going=0
          jobs=1
          rest=()

          add_hosts() {
            local h
            for h in "$@"; do
              case " ''${hosts[*]} " in *" $h "*) ;; *) hosts+=("$h") ;; esac
            done
          }

          parse_args() {
            local sel=() a members
            while [ $# -gt 0 ]; do
              case $1 in
                --all) sel+=(--all) ;;
                --local) force_local=1 ;;
                --target) target=''${2:?--target needs a value}; shift ;;
                --build-on-target) build_mode=target ;;
                --build-local) build_mode=local ;;
                --keep-going) keep_going=1 ;;
                -j) jobs=''${2:?-j needs a value}; shift ;;
                --) shift; rest=("$@"); break ;;
                -*) die "unknown option '$1'" ;;
                *) sel+=("$1") ;;
              esac
              shift
            done
            [ "''${#sel[@]}" -gt 0 ] || die "no host selected (give a host, @group or --all)"
            [[ $jobs =~ ^[1-9][0-9]*$ ]] || die "-j needs a positive number"
            [ $force_local = 0 ] || [ -z "$target" ] || die "--local and --target exclude each other"

            for a in "''${sel[@]}"; do
              case $a in
                --all)
                  mapfile -t members < <(all_hosts)
                  add_hosts "''${members[@]}"
                  ;;
                @*)
                  mapfile -t members < <(group_hosts "''${a#@}")
                  [ "''${#members[@]}" -gt 0 ] ||
                    die "group '$a' has no hosts (groups: $(jq -r '[.[].groups[]] | unique | join(", ")' <<<"$data"))"
                  add_hosts "''${members[@]}"
                  ;;
                *)
                  is_host "$a" ||
                    die "unknown host '$a' (known: $(jq -r 'keys | join(", ")' <<<"$data"))"
                  add_hosts "$a"
                  ;;
              esac
            done
            if [ "''${#hosts[@]}" -gt 1 ] && { [ -n "$target" ] || [ $force_local = 1 ]; }; then
              die "--target and --local need exactly one host"
            fi
          }

          # -- one host ----------------------------------------------------

          # Sets $dest (user@addr) or leaves it empty for a local deploy.
          dest=
          resolve_target() {
            local h=$1 t=$target
            dest=
            [ $force_local = 0 ] || return 0
            if [ -z "$t" ]; then
              [ "$h" != "$(uname -n)" ] || return 0
              t=$(field "$h" target)
              [ -n "$t" ] || return 0
            fi
            case $t in
              *@*) dest=$t ;;
              *) dest="$(field "$h" user)@$t" ;;
            esac
          }

          # nixos-rebuild-ng renamed --use-remote-sudo to --sudo. Ask rather
          # than guess: both spellings are in the wild.
          sudo_flag=--use-remote-sudo
          if nixos-rebuild --help 2>&1 | grep -q -- '--sudo'; then sudo_flag=--sudo; fi

          # Sets $sshopts (array) and exports NIX_SSHOPTS for the host in
          # $dest. With a committed host.pub, ssh trusts exactly that key.
          # A known_hosts line is `<host> <type> <key>`: host.pub's trailing
          # comment must go, ssh would read it as a marker and ignore the line.
          sshopts=()
          ssh_setup() {
            local h=$1 pubfile kh type key
            mapfile -t sshopts < <(jq -r --arg h "$h" '.[$h].sshOpts[]' <<<"$data")
            pubfile=$root$(field "$h" pub)
            if [ "$(field "$h" hasPub)" = true ] && [ -f "$pubfile" ]; then
              kh=$tmp/$h.known_hosts
              read -r type key _ <"$pubfile"
              echo "''${dest#*@} $type $key" >"$kh"
              sshopts+=(-o "UserKnownHostsFile=$kh" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes)
            else
              info "$h: no committed host key; falling back to accept-new"
              sshopts+=(-o StrictHostKeyChecking=accept-new)
            fi
            export NIX_SSHOPTS="''${sshopts[*]}"
          }

          # Everything per-host runs in a subshell, so it can run in parallel.
          deploy_one() {
            local h=$1 action=$2 build_on_target flags=()
            flags=(--flake "$root#$h" --fast)
            resolve_target "$h"

            # `build` contacts nothing, so it skips the local/remote question.
            if [ "$action" = build ]; then
              info "$h: build"
              nixos-rebuild build "''${flags[@]}" "''${rest[@]}"
              return
            fi

            if [ -z "$dest" ]; then
              info "$h: $action (local)"
              # nixos-rebuild builds as you and only escalates to activate, so
              # sudo wraps the whole call rather than the build.
              if [ "$(id -u)" -eq 0 ]; then
                nixos-rebuild "$action" "''${flags[@]}" "''${rest[@]}"
              else
                sudo nixos-rebuild "$action" "''${flags[@]}" "''${rest[@]}"
              fi
              return
            fi

            ssh_setup "$h"
            flags+=(--target-host "$dest")
            [ "''${dest%@*}" = root ] || flags+=("$sudo_flag")

            build_on_target=$(field "$h" buildOnTarget)
            case $build_mode in
              target) build_on_target=true ;;
              local) build_on_target=false ;;
            esac
            [ "$build_on_target" != true ] || flags+=(--build-host "$dest")

            info "$h: $action -> $dest"
            nixos-rebuild "$action" "''${flags[@]}" "''${rest[@]}"
          }

          # Build, then diff against what the machine runs now.
          plan_one() {
            local h=$1 new cur
            resolve_target "$h"
            info "$h: building"
            new=$(nix build --no-link --print-out-paths \
              "$root#nixosConfigurations.$h.config.system.build.toplevel" "''${rest[@]}")
            if [ -z "$dest" ]; then
              cur=/run/current-system
            else
              ssh_setup "$h"
              cur=$(ssh "''${sshopts[@]}" "$dest" readlink -f /run/current-system) ||
                die "$h: cannot read the running system over ssh"
              nix copy --no-check-sigs --from "ssh://$dest" "$cur" 2>/dev/null ||
                die "$h: cannot fetch the running system to diff against"
            fi
            if [ "$(readlink -f "$cur")" = "$new" ]; then
              info "$h: up to date"
            else
              nix store diff-closures "$cur" "$new"
            fi
          }

          # -- run ---------------------------------------------------------

          tmp=
          trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT

          # Runs one host in a subshell with errexit really on (it is ignored
          # inside `if`/`||`), and leaves a marker the parallel mode can find.
          run_host() {
            local rc
            set +e
            ( set -e; "$@" )
            rc=$?
            set -e
            [ $rc -eq 0 ] || echo "deploy: $2: FAILED" >&2
            return $rc
          }

          run_all() {
            local action=$1 fn=deploy_one h running=0 failed=() ok=()
            [ "$action" != plan ] || fn=plan_one
            load_data
            tmp=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}" deploy.XXXXXX)

            if [ "$jobs" -eq 1 ]; then
              for h in "''${hosts[@]}"; do
                if run_host "$fn" "$h" "$action"; then
                  ok+=("$h")
                else
                  failed+=("$h")
                  [ $keep_going = 1 ] || { info "stopping (--keep-going continues with the rest)"; break; }
                fi
              done
            else
              for h in "''${hosts[@]}"; do
                if [ "$running" -ge "$jobs" ]; then wait -n || true; running=$((running - 1)); fi
                run_host "$fn" "$h" "$action" >"$tmp/$h.log" 2>&1 &
                running=$((running + 1))
              done
              wait || true
              for h in "''${hosts[@]}"; do
                echo "== $h ==" >&2
                cat "$tmp/$h.log" >&2
              done
              # `wait` loses per-job status; the log markers carry it.
              for h in "''${hosts[@]}"; do
                if grep -q "^deploy: $h: FAILED" "$tmp/$h.log"; then failed+=("$h"); else ok+=("$h"); fi
              done
            fi

            if [ "''${#hosts[@]}" -gt 1 ]; then
              [ "''${#ok[@]}" -eq 0 ] || info "ok: ''${ok[*]}"
              [ "''${#failed[@]}" -eq 0 ] || info "FAILED: ''${failed[*]}"
            fi
            [ "''${#failed[@]}" -eq 0 ]
          }

          cmd_list() {
            load_data
            jq -r 'to_entries[] | [.key, (.value.target // "(local)"), .value.user,
                   (.value.groups | map("@" + .) | join(","))] | @tsv' <<<"$data" |
              column -t -s "$(printf '\t')"
          }

          cmd=''${1:-help}
          [ $# -eq 0 ] || shift
          case $cmd in
            list) cmd_list ;;
            build | plan | switch | boot | test | dry-activate)
              load_data
              parse_args "$@"
              run_all "$cmd"
              ;;
            completion)
              [ "''${1:-}" = bash ] || die "usage: deploy completion bash"
              cat ${completion}
              ;;
            help | -h | --help) usage ;;
            *) usage >&2; die "unknown command '$cmd'" ;;
          esac
        '';
      };

      deploy = pkgs.symlinkJoin {
        name = "deploy";
        paths = [ deploy-script ];
        postBuild = ''
          install -Dm644 ${completion} $out/share/bash-completion/completions/deploy
        '';
        meta.mainProgram = "deploy";
      };
    in
    {
      packages.deploy-cli = deploy;
      make-shells.default = {
        packages = [ deploy ];
        shellHook = ''
          if [ -n "''${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
            source <(deploy completion bash)
          fi
        '';
      };
    };
}
