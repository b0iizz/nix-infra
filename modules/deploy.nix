{
  lib,
  config,
  self,
  ...
}:
let
  rcfg = config.registry;
  cli = self.lib.cli;

  hostsData = lib.mapAttrs (_name: host: {
    # Committed ssh host public key; deploys pin it when present.
    pub = cli.relPath (host.path + "/host.pub");
    targets = host.deploy.targetHosts;
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

      deploy = cli.mkCli pkgs {
        name = "deploy";
        dataAttr = "deployData";
        runtimeInputs = [
          pkgs.nixos-rebuild
          pkgs.util-linux
        ];

        completion = ''
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

        text = ''
          usage() {
            cat <<'EOF'
          Usage: deploy <command> [options] <host|@group>... | --all

          Updates installed machines with nixos-rebuild. (First installs:
          see `provision`; ssh host keys: see `host-keys`.)

          Commands:
            list                  Hosts, targets and groups
            build                 Build only, here; no target is contacted
            plan                  Build, copy to the target, show what would change
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

          A host without deploy.targetHosts, or named like this machine, is
          deployed locally. Otherwise the first target that serves the
          host's key and takes a login (and sudo without a password, for a
          user other than root) is used; with --target only that one. A
          target user other than root uses sudo.

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

          group_hosts() {
            load_data
            jq -r --arg g "$1" 'to_entries[] | select(.value.groups | index($g)) | .key' <<<"$data"
          }

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
                  need_host "$a"
                  add_hosts "$a"
                  ;;
              esac
            done
            if [ "''${#hosts[@]}" -gt 1 ] && { [ -n "$target" ] || [ $force_local = 1 ]; }; then
              die "--target and --local need exactly one host"
            fi
          }

          # -- one host ----------------------------------------------------

          # Sets $dest (user@addr) and $sshopts, or leaves $dest empty for a
          # local deploy.
          dest=
          resolve_target() {
            local h=$1 targets=("$target")
            dest=
            [ $force_local = 0 ] || return 0
            if [ -z "$target" ]; then
              [ "$h" != "$(uname -n)" ] || return 0
              mapfile -t targets < <(jq -r --arg h "$h" '.[$h].targets[]' <<<"$data")
              [ "''${#targets[@]}" -gt 0 ] || return 0
            fi
            ssh_setup "$h" "$root$(field "$h" pub)"
            pick_dest "$h" "$(field "$h" user)" "''${targets[@]}"
          }

          # nixos-rebuild-ng renamed --use-remote-sudo to --sudo. Ask rather
          # than guess: both spellings are in the wild.
          sudo_flag=--use-remote-sudo
          if nixos-rebuild --help 2>&1 | grep -q -- '--sudo'; then sudo_flag=--sudo; fi

          # Everything per-host runs in a subshell, so it can run in parallel.
          deploy_one() {
            local h=$1 action=$2 build_on_target flags=()
            flags=(--flake "$root#$h" --no-reexec)

            # `build` contacts nothing, so it skips the local/remote question.
            if [ "$action" = build ]; then
              info "$h: build"
              nixos-rebuild build "''${flags[@]}" "''${rest[@]}"
              return
            fi

            resolve_target "$h"
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

          # Build, then diff against what the machine runs now. The diff runs on
          # the target: nothing is copied from a target into this store, where a
          # broken-into target could plant paths that later deploys reuse.
          plan_one() {
            local h=$1 new cur on=()
            info "$h: building"
            new=$(nix build --no-link --print-out-paths \
              "$root#nixosConfigurations.$h.config.system.build.toplevel" "''${rest[@]}")
            # after the build: a failed build costs no login
            resolve_target "$h"
            [ -z "$dest" ] || on=(ssh "''${sshopts[@]}" "$dest")
            cur=$("''${on[@]}" readlink -f /run/current-system) ||
              die "$h: cannot read the running system"
            if [ "$cur" = "$new" ]; then
              info "$h: up to date"
              return
            fi
            [ -z "$dest" ] || nix copy --to "ssh://$dest" "$new" ||
              die "$h: cannot copy the new system to diff against"
            "''${on[@]}" nix store diff-closures "$cur" "$new"
          }

          # -- run ---------------------------------------------------------

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
            # Before the subshells, so they share it and the exit trap removes it.
            mk_tmp

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
            jq -r 'to_entries[] | [.key, (.value.targets | join(",") | if . == "" then "(local)" else . end), .value.user,
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
            completion) print_completion "$@" ;;
            help | -h | --help) usage ;;
            *) usage >&2; die "unknown command '$cmd'" ;;
          esac
        '';
      };
    in
    {
      packages.deploy-cli = deploy;
      make-shells.default = cli.shellFor deploy;

      # Target picking: `deploy plan` against stub nix and ssh, where only
      # `good` takes a login.
      checks.deploy-targets =
        let
          stubbed = deploy.withRuntimeInputs [
            (pkgs.writeShellScriptBin "nix" ''
              case $1 in
                eval) echo '{"h":{"pub":"/h.pub","targets":["down","wrongkey","noauth","good","later"],"user":"root","sshOpts":[],"buildOnTarget":false,"groups":[]}}' ;;
                build) echo /fake ;;
              esac
            '')
            (pkgs.writeShellScriptBin "ssh" ''
              dest=''${*: -2:1}
              case ''${*: -1} in
                true) ;;
                "sudo -n true") echo "$dest sudo" >>"$PROBES"; echo "sudo: a password is required" >&2; exit 1 ;;
                *) echo /fake; exit ;; # readlink -f /run/current-system: up to date
              esac
              echo "$dest" >>"$PROBES"
              case $dest in
                *@good) exit 0 ;;
                *@wrongkey) echo "Host key verification failed." >&2 ;;
                *@noauth) echo "$dest: Permission denied (publickey)." >&2 ;;
                *) echo "ssh: connect to host ''${dest#*@} port 22: Connection timed out" >&2 ;;
              esac
              exit 255
            '')
          ];
        in
        pkgs.runCommand "check-deploy-targets" { } ''
          export FLAKE_ROOT=$PWD XDG_RUNTIME_DIR=$TMPDIR PROBES=$PWD/probes
          echo "ssh-ed25519 AAAA" >h.pub
          probes() { rm -f "$PROBES"; "$@"; tr '\n' ' ' <"$PROBES"; }
          fails() { rm -f "$PROBES"; if "$@"; then exit 1; fi; cat "$PROBES"; }

          [ "$(probes ${stubbed}/bin/deploy plan h)" = "root@down root@wrongkey root@noauth root@good " ]
          [ "$(probes ${stubbed}/bin/deploy plan h --target good)" = "root@good " ]
          [ "$(fails ${stubbed}/bin/deploy plan h --target later)" = root@later ]
          [ "$(fails ${stubbed}/bin/deploy plan h --target joni@good)" = "joni@good sudo" ]
          touch $out
        '';
    };
}
