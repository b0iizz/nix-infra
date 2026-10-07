{
  lib,
  config,
  self,
  ...
}:
let
  rcfg = config.registry;

  # The CLI works on the checked-out repository, not on the store copy, so
  # every path it needs is handed over relative to the flake root.
  relPath = p: lib.removePrefix (toString self) (toString p);

  hostsData = lib.mapAttrs (_name: host: {
    age = relPath host.hostkey.privateKeyFile;
    pub = relPath (host.path + "/host.pub");
    target = host.deploy.targetHost;
    user = host.deploy.targetUser;
    sshOpts = host.deploy.sshOpts;
  }) (lib.filterAttrs (_: host: host.enable) rcfg.hosts);

  masterDir = relPath (rcfg.secretsDir + "/master");

  # A host with only one half of its key pair can neither decrypt nor be
  # encrypted to; `nix flake check` should catch that before a deploy does.
  halfPaired = lib.attrNames (
    lib.filterAttrs (
      _: host:
      builtins.pathExists host.hostkey.privateKeyFile != builtins.pathExists (host.path + "/host.pub")
    ) (lib.filterAttrs (_: host: host.enable) rcfg.hosts)
  );
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      hostsFile = pkgs.writeText "host-keys-hosts.json" (builtins.toJSON hostsData);

      completion = pkgs.writeText "host-keys.bash" ''
        _host_keys() {
          local cur=''${COMP_WORDS[COMP_CWORD]} prev=''${COMP_WORDS[COMP_CWORD-1]}
          local cmd=''${COMP_WORDS[1]:-} opts=""

          if [ "$COMP_CWORD" -eq 1 ]; then
            mapfile -t COMPREPLY < <(compgen -W "list generate rotate deploy verify export show pub fingerprint completion help" -- "$cur")
            return
          fi
          [ "$prev" = --target ] && return

          case $cmd in
            generate) opts="--all" ;;
            rotate) opts="--rekey --deploy --local --target --restart-sshd" ;;
            deploy) opts="--local --target --restart-sshd" ;;
            verify) opts="--local --target" ;;
            show) opts="--yes" ;;
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
            generate | rotate | deploy | verify | show | pub | fingerprint)
              mapfile -t COMPREPLY < <(compgen -W "$(host-keys _hosts 2>/dev/null)" -- "$cur")
              ;;
            export)
              if [ "$COMP_CWORD" -eq 2 ]; then
                mapfile -t COMPREPLY < <(compgen -W "$(host-keys _hosts 2>/dev/null)" -- "$cur")
              else
                mapfile -t COMPREPLY < <(compgen -d -- "$cur")
              fi
              ;;
          esac
        }
        complete -F _host_keys host-keys
      '';

      host-keys-script = pkgs.writeShellApplication {
        name = "host-keys";
        runtimeInputs = [
          pkgs.rage
          pkgs.age-plugin-fido2-hmac
          pkgs.openssh
          pkgs.jq
          pkgs.git
          pkgs.gawk
          pkgs.coreutils
          config.agenix-rekey.package
        ];
        text = ''
          hosts_file=${hostsFile}
          master_rel=${lib.escapeShellArg masterDir}

          # Where NixOS (see secrets.nix) expects the host key on the target.
          key_path=/etc/ssh/ssh_host_ed25519_key

          usage() {
            cat <<'EOF'
          Usage: host-keys <command> [args]

          Host SSH keys (ed25519) are stored age-encrypted to the master
          recipients in secrets/master/*.pub, next to a plaintext public key
          that agenix-rekey rekeys every host secret to.

          Commands:
            list                         Hosts, key state, deploy target
            generate <host>... | --all   Create keys (--all: only hosts without one)
            rotate <host> [opts]         Replace a key with a fresh one
                --rekey                    run `agenix rekey` afterwards
                --deploy                   install the new key on the host afterwards
                (plus any deploy option below)
            deploy <host> [opts]         Install the key on the machine
                --local                    install on this machine
                --target [user@]addr       ssh there instead of the registry target
                --restart-sshd             restart sshd.service afterwards
            verify <host> [opts]         Check the machine has the registered key
                --local, --target          as for deploy
            export <host> <dir>          Write <dir>/etc/ssh/... for
                                         nixos-anywhere --extra-files <dir>
            show <host> [--yes]          Print the private key to stdout
            pub <host>                   Print the public key
            fingerprint <host>           Print the SHA256 fingerprint
            completion bash              Print the bash completion script:
                                         source <(host-keys completion bash)
            help

          Environment:
            FLAKE_ROOT  repository root (default: git toplevel or cwd)

          Without --local/--target, deploy and verify run locally if <host>
          is this machine's hostname, otherwise over ssh to the registry's
          deploy.targetHost.

          Typical rotation:  host-keys rotate <host> --rekey --deploy
          Then deploy the system as usual.
          EOF
          }

          die() { echo "host-keys: $*" >&2; exit 1; }
          info() { echo "host-keys: $*" >&2; }

          root=''${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
          master_dir=$root$master_rel

          field() { jq -r --arg h "$1" --arg k "$2" '.[$h][$k] // empty' "$hosts_file"; }
          age_path() { echo "$root$(field "$1" age)"; }
          pub_path() { echo "$root$(field "$1" pub)"; }

          # none | half | ok. A half pair means either nothing can decrypt
          # secrets for the host or nothing is encrypted to it: never guess.
          key_state() {
            local a=0 p=0
            [ -f "$(age_path "$1")" ] && a=1
            [ -f "$(pub_path "$1")" ] && p=1
            case $a$p in
              00) echo none ;;
              11) echo ok ;;
              *) echo half ;;
            esac
          }
          has_key() { [ "$(key_state "$1")" != none ]; }
          die_half() {
            die "$1 has half a key pair ($(age_path "$1"), $(pub_path "$1")). Restore the missing half from git, or delete the other if nothing is encrypted to it yet."
          }

          need_host() {
            [ -n "''${1:-}" ] || die "missing <host> argument"
            jq -e --arg h "$1" 'has($h)' "$hosts_file" >/dev/null ||
              die "unknown host '$1' (known: $(jq -r 'keys | join(", ")' "$hosts_file"))"
          }

          recipient_args=()
          identity_args=()
          load_master() {
            shopt -s nullglob
            local f
            for f in "$master_dir"/*.pub; do recipient_args+=(-R "$f"); done
            for f in "$master_dir"/*.age-identity; do identity_args+=(-i "$f"); done
            shopt -u nullglob
          }

          # Plaintext only ever lives on a tmpfs when possible, mode 700.
          tmp=
          cleanup() {
            if [ -n "$tmp" ]; then
              find "$tmp" -type f -exec shred -u {} + 2>/dev/null || true
              rm -rf "$tmp"
            fi
          }
          trap cleanup EXIT
          mk_tmp() { tmp=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}" host-keys.XXXXXX); }

          git_add() { git -C "$root" add -- "$@" 2>/dev/null || true; }

          decrypt() {
            local age
            age=$(age_path "$1")
            [ -f "$age" ] || die "$1: no key at $age (run: host-keys generate $1)"
            load_master
            [ ''${#identity_args[@]} -gt 0 ] || die "no *.age-identity in $master_dir"
            info "$1: touch your token if it blinks"
            rage -d "''${identity_args[@]}" "$age"
          }

          read_pub() {
            [ -f "$(pub_path "$1")" ] || die "$1: no public key at $(pub_path "$1")"
            cat "$(pub_path "$1")"
          }

          # -- generate ----------------------------------------------------

          gen_one() {
            local h=$1 age pub
            age=$(age_path "$h")
            pub=$(pub_path "$h")
            load_master
            [ ''${#recipient_args[@]} -gt 0 ] || die "no master *.pub in $master_dir"

            mk_tmp
            ssh-keygen -q -t ed25519 -N "" -C "" -f "$tmp/key"
            mkdir -p "$(dirname "$age")" "$(dirname "$pub")"
            rage -a -e "''${recipient_args[@]}" -o "$age.new" "$tmp/key"
            awk '{ print $1, $2 }' "$tmp/key.pub" >"$pub.new"
            mv -f "$age.new" "$age"
            mv -f "$pub.new" "$pub"
            cleanup
            tmp=
            # Flakes only see tracked files.
            git_add "$age" "$pub"
            info "$h: wrote ''${age#"$root"/} and ''${pub#"$root"/}"
          }

          cmd_generate() {
            local all=0 hosts=() h
            while [ $# -gt 0 ]; do
              case $1 in
                --all) all=1 ;;
                -*) die "generate: unknown option $1" ;;
                *) hosts+=("$1") ;;
              esac
              shift
            done
            if [ $all = 1 ]; then
              mapfile -t hosts < <(jq -r 'keys[]' "$hosts_file")
              for h in "''${hosts[@]}"; do
                case $(key_state "$h") in
                  ok) info "$h: already has a key, skipping" ;;
                  half) die_half "$h" ;;
                  none) gen_one "$h" ;;
                esac
              done
              return
            fi
            [ ''${#hosts[@]} -gt 0 ] || die "generate: give hosts or --all"
            for h in "''${hosts[@]}"; do
              need_host "$h"
              case $(key_state "$h") in
                ok) die "$h: already has a key; use 'rotate' to replace it" ;;
                half) die_half "$h" ;;
              esac
            done
            for h in "''${hosts[@]}"; do gen_one "$h"; done
          }

          # -- deploy / verify ---------------------------------------------

          # Sets $mode (local|ssh) and $dest (user@addr) from the options.
          mode=
          dest=
          resolve_target() {
            local h=$1 force_local=$2 target=$3
            if [ "$force_local" = 1 ]; then
              mode=local
              return
            fi
            if [ -z "$target" ]; then
              if [ "$h" = "$(uname -n)" ]; then
                mode=local
                return
              fi
              target=$(field "$h" target)
              [ -n "$target" ] || die "$h: no deploy.targetHost and not this machine; pass --target"
            fi
            case $target in
              *@*) dest=$target ;;
              *) dest="$(field "$h" user)@$target" ;;
            esac
            mode=ssh
          }

          # POSIX sh, no single quotes: it is passed through `sh -c '...'`.
          # shellcheck disable=SC2016
          install_script='set -eu; umask 077; d=/etc/ssh; mkdir -p "$d"; read -r pub; cat > "$d/.host_key.new"; chmod 600 "$d/.host_key.new"; if command -v ssh-keygen >/dev/null; then got=$(ssh-keygen -y -f "$d/.host_key.new" | cut -d" " -f2); want=$(echo "$pub" | cut -d" " -f2); [ "$got" = "$want" ] || { echo "host key does not match public key, aborting" >&2; rm -f "$d/.host_key.new"; exit 1; }; fi; printf "%s\n" "$pub" > "$d/.host_key.pub.new"; chmod 644 "$d/.host_key.pub.new"; mv -f "$d/.host_key.new" "$d/ssh_host_ed25519_key"; mv -f "$d/.host_key.pub.new" "$d/ssh_host_ed25519_key.pub"'

          parse_target_opts() {
            force_local=0 target="" restart=0 rest=()
            while [ $# -gt 0 ]; do
              case $1 in
                --local) force_local=1 ;;
                --target) target=''${2:?--target needs a value}; shift ;;
                --restart-sshd) restart=1 ;;
                *) rest+=("$1") ;;
              esac
              shift
            done
          }

          deploy_one() {
            local h=$1 force_local=$2 target=$3 restart=$4 key pub script opts sudo=
            resolve_target "$h" "$force_local" "$target"
            pub=$(read_pub "$h")
            key=$(decrypt "$h") # touch the token before any ssh/sudo prompt
            script=$install_script
            if [ "$restart" = 1 ]; then script="$script; systemctl restart sshd.service"; fi

            if [ "$mode" = local ]; then
              if [ "$(id -u)" -ne 0 ]; then sudo=sudo; fi
              info "$h: installing key locally"
              { echo "$pub"; printf '%s\n' "$key"; } | $sudo sh -c "$script"
            else
              mapfile -t opts < <(jq -r --arg h "$h" '.[$h].sshOpts[]' "$hosts_file")
              if [ "''${dest%@*}" != root ]; then sudo="sudo -n"; fi
              info "$h: installing key on $dest"
              # shellcheck disable=SC2029
              { echo "$pub"; printf '%s\n' "$key"; } | ssh "''${opts[@]}" "$dest" "$sudo sh -c '$script'"
            fi
          }

          cmd_deploy() {
            parse_target_opts "$@"
            set -- "''${rest[@]}"
            need_host "''${1:-}"
            [ $# -eq 1 ] || die "deploy: expected exactly one host"
            deploy_one "$1" "$force_local" "$target" "$restart"
          }

          cmd_verify() {
            parse_target_opts "$@"
            set -- "''${rest[@]}"
            need_host "''${1:-}"
            local h=$1 want got opts
            want=$(read_pub "$h" | awk '{ print $2 }')
            resolve_target "$h" "$force_local" "$target"
            if [ "$mode" = local ]; then
              got=$(awk '{ print $2 }' "$key_path.pub")
            else
              mapfile -t opts < <(jq -r --arg h "$h" '.[$h].sshOpts[]' "$hosts_file")
              # shellcheck disable=SC2029
              got=$(ssh "''${opts[@]}" "$dest" cat "$key_path.pub" | awk '{ print $2 }')
            fi
            if [ "$got" = "$want" ]; then
              info "$h: OK, machine has the registered key"
            else
              die "$h: MISMATCH, machine has '$got', registry has '$want'"
            fi
          }

          cmd_export() {
            [ $# -eq 2 ] || die "export: expected <host> <dir>"
            need_host "$1"
            local h=$1 dir=$2/etc/ssh
            local pub key
            pub=$(read_pub "$h")
            key=$(decrypt "$h")
            (
              umask 077
              mkdir -p "$dir"
              printf '%s\n' "$key" >"$dir/ssh_host_ed25519_key"
              printf '%s\n' "$pub" >"$dir/ssh_host_ed25519_key.pub"
              chmod 755 "$2/etc" "$dir"
              chmod 644 "$dir/ssh_host_ed25519_key.pub"
            )
            info "$h: wrote $dir; use: nixos-anywhere --extra-files $2 ..."
          }

          # -- rotate ------------------------------------------------------

          cmd_rotate() {
            local do_rekey=0 do_deploy=0 a args=()
            for a in "$@"; do
              case $a in
                --rekey) do_rekey=1 ;;
                --deploy) do_deploy=1 ;;
                *) args+=("$a") ;;
              esac
            done
            parse_target_opts "''${args[@]}"
            set -- "''${rest[@]}"
            need_host "''${1:-}"
            [ $# -eq 1 ] || die "rotate: expected exactly one host"
            local h=$1
            case $(key_state "$h") in
              half) die_half "$h" ;;
              none) info "$h: had no key, generating a first one" ;;
            esac
            gen_one "$h"
            if [ $do_rekey = 1 ]; then
              info "rekeying secrets"
              (cd "$root" && agenix rekey -a)
            fi
            if [ $do_deploy = 1 ]; then
              deploy_one "$h" "$force_local" "$target" "$restart"
            else
              info "$h: not deployed yet; run: host-keys deploy $h"
            fi
            [ $do_rekey = 1 ] || info "run 'agenix rekey -a' so secrets are encrypted to the new key"
            info "order matters: key on the host BEFORE the system with rekeyed secrets is switched"
            info "sshd serves this key too: update known_hosts after deploying"
          }

          # -- read access -------------------------------------------------

          cmd_show() {
            local yes=0 h=
            for a in "$@"; do
              case $a in
                --yes) yes=1 ;;
                *) h=$a ;;
              esac
            done
            need_host "$h"
            if [ -t 1 ] && [ $yes = 0 ]; then
              die "refusing to print a private key to a terminal; pipe it or pass --yes"
            fi
            decrypt "$h"
          }

          cmd_pub() {
            need_host "''${1:-}"
            read_pub "$1"
          }

          cmd_fingerprint() {
            need_host "''${1:-}"
            read_pub "$1" | ssh-keygen -lf - | awk '{ print $2 }'
          }

          cmd_list() {
            local h target state
            printf '%-24s %-52s %s\n' HOST KEY TARGET
            while read -r h; do
              case $(key_state "$h") in
                ok) state=$(ssh-keygen -lf "$(pub_path "$h")" | awk '{ print $2 }') ;;
                half) state="HALF A PAIR, repair before deploying" ;;
                none) state="none (run: host-keys generate $h)" ;;
              esac
              target=$(field "$h" target)
              printf '%-24s %-52s %s\n' "$h" "$state" "''${target:-local only}"
            done < <(jq -r 'keys[]' "$hosts_file")
          }

          [ $# -gt 0 ] || { usage; exit 1; }
          cmd=$1
          shift
          case $cmd in
            list) cmd_list ;;
            generate) cmd_generate "$@" ;;
            rotate) cmd_rotate "$@" ;;
            deploy) cmd_deploy "$@" ;;
            verify) cmd_verify "$@" ;;
            export) cmd_export "$@" ;;
            show | cat | private) cmd_show "$@" ;;
            pub | public) cmd_pub "$@" ;;
            fingerprint) cmd_fingerprint "$@" ;;
            completion)
              [ "''${1:-}" = bash ] || die "completion: only 'bash' is supported"
              cat ${completion}
              ;;
            _hosts) jq -r 'keys[]' "$hosts_file" ;;
            help | -h | --help) usage ;;
            *) usage; die "unknown command '$cmd'" ;;
          esac
        '';
      };

      # Also installs the completion where bash-completion looks for it.
      host-keys = pkgs.symlinkJoin {
        name = "host-keys";
        paths = [ host-keys-script ];
        postBuild = ''
          install -Dm644 ${completion} $out/share/bash-completion/completions/host-keys
        '';
        meta.mainProgram = "host-keys";
      };
    in
    {
      packages.host-key-cli = host-keys;
      make-shells.default = {
        packages = [ host-keys ];
        # nix develop does not put share/bash-completion on XDG_DATA_DIRS.
        shellHook = ''
          if [ -n "''${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
            source <(host-keys completion bash)
          fi
        '';
      };

      checks.host-keys = pkgs.runCommand "check-host-keys" { } (
        if halfPaired == [ ] then
          "touch $out"
        else
          ''
            echo "hosts with half a host key pair: ${toString halfPaired}" >&2
            echo "run: host-keys list" >&2
            exit 1
          ''
      );
    };
}
