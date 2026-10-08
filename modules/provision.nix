{ withInputs, ... }:
withInputs
  {
    nixos-facter = {
      url = "github:nix-community/nixos-facter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
  }
  (
    {
      lib,
      config,
      self,
      ...
    }:
    let
      rcfg = config.registry;

      cli = self.lib.cli;
      inherit (cli) relPath;

      hostsData = lib.mapAttrs (_name: host: {
        age = relPath host.hostkey.privateKeyFile;
        pub = relPath (host.path + "/host.pub");
        facter = relPath (host.path + "/facter.json");
        system = host.system;
        method = host.provision.method;
        kexec = host.provision.kexec;
        target = host.provision.targetHost;
        user = host.provision.targetUser;
        buildOnTarget = host.deploy.buildOnTarget;
      }) (lib.filterAttrs (_: host: host.enable) rcfg.hosts);
    in
    {
      # The CLI reads this live (`nix eval .#provisionData`), so a host created by
      # `provision new` is known at once, without rebuilding the tool.
      flake.provisionData = hostsData;

      perSystem =
        { pkgs, inputs', ... }:
        let
          nixos-anywhere = inputs'.nixos-anywhere.packages.default;
          # nixpkgs' disko, not the flake input: the input's closure drags in a
          # whole copy of nixpkgs (200 MB), which matters on the ISO.
          disko = pkgs.disko;
          nixos-facter = inputs'.nixos-facter.packages.default;

          # Static host list: only used for tab completion, so staleness is fine.
          hostNames = pkgs.writeText "provision-hosts" (lib.concatStringsSep "\n" (lib.attrNames hostsData));

          completion = ''
            _provision() {
              local cur=''${COMP_WORDS[COMP_CWORD]} prev=''${COMP_WORDS[COMP_CWORD-1]}
              local cmd=''${COMP_WORDS[1]:-} opts=""

              if [ "$COMP_CWORD" -eq 1 ]; then
                mapfile -t COMPREPLY < <(compgen -W "list new facter plan commit mount completion help" -- "$cur")
                return
              fi
              [ "$prev" = --target ] || [ "$prev" = --roles ] && return

              case $cmd in
                new) opts="--target --roles --no-facter" ;;
                facter) opts="--local --target" ;;
                plan | commit) opts="--local --target" ;;
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
                facter | plan | commit | mount)
                  mapfile -t COMPREPLY < <(compgen -W "$(cat ${hostNames})" -- "$cur")
                  ;;
              esac
            }
            complete -F _provision provision
          '';

          provision = cli.mkCli pkgs {
            name = "provision";
            dataAttr = "provisionData";
            runtimeInputs = [
              nixos-anywhere
              disko
            ];
            inherit completion;
            text = ''
              hosts_dir=modules/hosts

              usage() {
                cat <<'EOF'
              Usage: provision <command> [args]

              Installs NixOS on a machine with nixos-anywhere and disko. The
              machine's ssh host key (see host-keys) is installed along with it,
              so secrets work from the first boot.

              Commands:
                list                         Hosts and what they still lack
                new <host> [opts]            Create a host in the repo
                    --target [user@]addr       machine to inspect and install on
                    --roles a,b                roles to start with
                    --no-facter                do not collect a hardware report
                facter <host> [opts]         Collect the hardware report
                    --target [user@]addr       over ssh (default: registry target)
                    --local                    on this machine
                plan <host> [opts]           Show what commit would do; changes nothing
                commit <host> [opts] [-- args-for-nixos-anywhere]
                                             INSTALL: wipes the host's disks
                    --target [user@]addr       ssh there (installer or any Linux)
                    --local                    this machine, booted from a NixOS
                                               installer (disko + nixos-install)
                mount <host>                 Rescue: mount this machine's disks at /mnt
                                             without formatting
                completion bash              source <(provision completion bash)
                help

              Without --local/--target, the registry decides: provision.method
              (remote by default) and provision.targetHost.

              Environment:
                FLAKE_ROOT  repository root (default: git toplevel or cwd)

              New machine:
                provision new web1 --target root@192.0.2.10 --roles server
                $EDITOR modules/hosts/web1/default.nix
                agenix rekey -a                 # if the host has secrets
                provision plan web1
                provision commit web1
              EOF
              }

              # Always the current flake, not the copy baked into this tool.
              host_keys() { nix run "$root#host-key-cli" -- "$@"; }

              # -- target ------------------------------------------------------

              # Sets $mode (local|remote) and $dest (user@addr, remote only).
              mode=
              dest=
              force_local=0
              target=
              rest=()
              parse_opts() {
                force_local=0 target="" rest=()
                while [ $# -gt 0 ]; do
                  case $1 in
                    --local) force_local=1 ;;
                    --target) target=''${2:?--target needs a value}; shift ;;
                    --) shift; rest+=("--" "$@"); break ;;
                    *) rest+=("$1") ;;
                  esac
                  shift
                done
                [ $force_local = 0 ] || [ -z "$target" ] || die "--local and --target exclude each other"
              }

              resolve() {
                local h=$1
                if [ $force_local = 1 ] || { [ -z "$target" ] && [ "$(field "$h" method)" = local ]; }; then
                  mode=local
                  return
                fi
                [ -n "$target" ] || target=$(field "$h" target)
                [ -n "$target" ] || die "$h: no provision.targetHost in the registry; pass --target or --local"
                dest=$(to_dest "$(field "$h" user)" "$target")
                mode=remote
              }

              # -- installer ---------------------------------------------------

              # After kexec the machine has a throwaway host key, so ssh must not
              # check it. Only ever used to talk to our own installer.
              isshl() {
                ssh -o BatchMode=yes -o ConnectTimeout=5 \
                  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                  -o LogLevel=ERROR "$@"
              }

              # Our images (see images.nix) carry this marker.
              in_installer() { isshl "$dest" 'test -e /etc/provision-installer' 2>/dev/null; }

              # Builds the kexec installer for the host's architecture and prints
              # the path of its tarball.
              kexec_tarball() {
                local out
                out=$(nix build --no-link --print-out-paths \
                  "$root#packages.$(field "$1" system).kexec-installer") ||
                  die "cannot build the kexec installer"
                ls "$out"/*.tar.gz
              }

              # Gets $dest into our installer: already there, or kexec into it.
              ensure_installer() {
                local h=$1 tarball
                if in_installer; then
                  info "$dest is already in the installer"
                  return
                fi
                [ "$(field "$h" kexec)" = true ] ||
                  die "$dest is not in the installer and provision.kexec is false; boot the ISO (nix build .#iso-installer)"
                [ "''${dest%@*}" = root ] || die "kexec needs root; use --target root@''${dest#*@}"
                tarball=$(kexec_tarball "$h")
                info "uploading the kexec installer to $dest"
                isshl "$dest" 'mkdir -p /root/kexec && tar -C /root/kexec -xzf -' <"$tarball"
                info "kexec; the connection will drop"
                isshl "$dest" /root/kexec/kexec/run || true
                info "waiting for the installer"
                for _ in $(seq 1 60); do
                  sleep 5
                  if in_installer; then
                    info "installer is up"
                    return
                  fi
                done
                die "the installer did not come back within five minutes"
              }

              # -- facter ------------------------------------------------------

              # collect_facter <host> <outfile>; uses $mode/$dest. Remote: runs
              # nixos-facter inside our installer, so the target needs neither nix
              # nor anything else. Written only if it is valid JSON.
              collect_facter() {
                local h=$1 out=$2 tmpf
                tmpf=$(mktemp)
                if [ "$mode" = local ]; then
                  local sudo=""
                  if [ "$(id -u)" -ne 0 ]; then sudo=sudo; fi
                  info "collecting hardware report locally"
                  $sudo ${nixos-facter}/bin/nixos-facter >"$tmpf" || { rm -f "$tmpf"; die "nixos-facter failed"; }
                else
                  ensure_installer "$h"
                  info "collecting hardware report from $dest"
                  isshl "$dest" nixos-facter >"$tmpf" || { rm -f "$tmpf"; die "nixos-facter failed on $dest"; }
                fi
                jq -e . "$tmpf" >/dev/null || { rm -f "$tmpf"; die "nixos-facter produced no valid JSON"; }
                mkdir -p "$(dirname "$out")"
                mv -f "$tmpf" "$out"
                git -C "$root" add -- "$out" 2>/dev/null || true
                info "wrote ''${out#"$root"/}"
              }

              cmd_facter() {
                parse_opts "$@"
                set -- "''${rest[@]}"
                need_host "''${1:-}"
                [ $# -eq 1 ] || die "facter: expected exactly one host"
                resolve "$1"
                collect_facter "$1" "$root$(field "$1" facter)"
              }

              # -- new ---------------------------------------------------------

              cmd_new() {
                local roles="" facter=1 h
                local args=()
                while [ $# -gt 0 ]; do
                  case $1 in
                    --roles) roles=''${2:?--roles needs a value}; shift ;;
                    --no-facter) facter=0 ;;
                    --target) args+=(--target "''${2:?--target needs a value}"); shift ;;
                    -*) die "new: unknown option $1" ;;
                    *) h=$1 ;;
                  esac
                  shift
                done
                [ -n "''${h:-}" ] || die "new: missing <host>"
                [[ $h =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "new: '$h' is not a valid host name (a-z, 0-9, -)"
                ! is_host "$h" || die "$h: already in the registry"
                local dir=$root/$hosts_dir/$h
                [ ! -e "$dir" ] || die "$h: $dir already exists"

                parse_opts "''${args[@]}"
                local addr=$target role_list="" r
                IFS=, read -ra rs <<<"$roles"
                for r in "''${rs[@]}"; do role_list="$role_list \"$r\""; done

                mkdir -p "$dir"
                {
                  echo '{ ... }:'
                  echo '{'
                  echo "  registry.hosts.$h = {"
                  echo '    path = ./.;'
                  echo "    roles = [$role_list ];"
                  if [ -n "$addr" ]; then
                    case $addr in
                      *@*)
                        echo "    provision.targetUser = \"''${addr%@*}\";"
                        addr=''${addr#*@}
                        ;;
                    esac
                    echo "    provision.targetHost = \"$addr\";"
                  fi
                  echo '  };'
                  echo '}'
                } >"$dir/default.nix"
                git -C "$root" add -- "$dir/default.nix"
                info "wrote ''${dir#"$root"/}/default.nix"

                if [ "$facter" = 1 ] && [ -n "$target" ]; then
                  data="" # re-read, now including the new host
                  load_data
                  resolve "$h"
                  collect_facter "$h" "$dir/facter.json"
                elif [ "$facter" = 1 ]; then
                  info "no --target: collect the hardware report later with: provision facter $h [--target ...|--local]"
                fi

                host_keys generate "$h"
                info "next: edit $hosts_dir/$h/default.nix (roles, disko layout)"
                info "      agenix rekey -a      # if the host has secrets"
                info "      provision plan $h && provision commit $h"
              }

              # -- plan / commit -----------------------------------------------

              # Prints the plan and returns non-zero if commit could not proceed.
              problems=0
              problem() { echo "  PROBLEM: $*"; problems=1; }
              show_plan() {
                local h=$1 disks
                problems=0
                resolve "$h"
                echo "host:    $h"
                if [ "$mode" = local ]; then
                  echo "install: this machine, using disko + nixos-install (booted from an installer)"
                else
                  echo "install: nixos-anywhere to $dest$([ "$(field "$h" kexec)" = true ] || echo ', without kexec')"
                fi
                if [ -f "$root$(field "$h" age)" ] && [ -f "$root$(field "$h" pub)" ]; then
                  echo "key:     ok (installed with the system)"
                else
                  problem "no host key; run: host-keys generate $h, then agenix rekey -a"
                fi
                if [ -f "$root$(field "$h" facter)" ]; then
                  echo "facter:  ok"
                else
                  problem "no hardware report; run: provision facter $h"
                fi
                echo "wipes:"
                if disks=$(nix eval --json "$root#nixosConfigurations.$h.config.disko.devices.disk" \
                  --apply 'd: builtins.mapAttrs (_: x: x.device) d' 2>/dev/null); then
                  jq -r 'to_entries[] | "  \(.key)  \(.value)"' <<<"$disks"
                else
                  problem "cannot evaluate disko.devices.disk of $h (is there a disko layout role?)"
                fi
              }

              cmd_plan() {
                parse_opts "$@"
                set -- "''${rest[@]}"
                need_host "''${1:-}"
                [ $# -eq 1 ] || die "plan: expected exactly one host"
                show_plan "$1"
                [ $problems = 0 ] || exit 1
                echo
                echo "ready: provision commit $1"
              }

              cmd_commit() {
                parse_opts "$@"
                set -- "''${rest[@]}"
                need_host "''${1:-}"
                local h=$1 passthrough=()
                shift
                if [ $# -gt 0 ]; then
                  [ "$1" = -- ] || die "commit: expected exactly one host (extra nixos-anywhere args go after --)"
                  shift
                  passthrough=("$@")
                fi
                show_plan "$h"
                [ $problems = 0 ] || die "$h: fix the problems above first"
                echo

                mk_tmp
                host_keys export "$h" "$tmp"

                if [ "$mode" = remote ]; then
                  local flags=()
                  if in_installer || [ "$(field "$h" kexec)" != true ]; then
                    flags+=(--phases "disko,install,reboot")
                  else
                    flags+=(--kexec "$(kexec_tarball "$h")")
                  fi
                  [ "$(field "$h" buildOnTarget)" != true ] || flags+=(--build-on remote)
                  info "$h: committing to $dest"
                  # After kexec the machine has a throwaway host key, so ssh must not
                  # check it here; the fingerprint to expect afterwards is printed.
                  nixos-anywhere --flake "$root#$h" --extra-files "$tmp" \
                    --chown /etc/ssh/ssh_host_ed25519_key 0:0 \
                    --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null \
                    "''${flags[@]}" "''${passthrough[@]}" "$dest"
                else
                  local sudo="" system
                  if [ "$(id -u)" -ne 0 ]; then sudo=sudo; fi
                  info "$h: building the system before touching any disk"
                  system=$(nix build --no-link --print-out-paths "$root#nixosConfigurations.$h.config.system.build.toplevel")
                  info "$h: committing to this machine"
                  $sudo disko --mode destroy,format,mount --yes-wipe-all-disks --flake "$root#$h"
                  $sudo mkdir -p /mnt/etc
                  $sudo cp -a "$tmp/etc/." /mnt/etc/
                  $sudo chown -R root:root /mnt/etc/ssh
                  $sudo nixos-install --no-root-passwd --system "$system" "''${passthrough[@]}"
                fi
                info "$h: done; expect this host key from now on:"
                ssh-keygen -lf "$root$(field "$h" pub)" >&2
              }

              # Rescue: mount a local machine's disks under /mnt, no formatting.
              cmd_mount() {
                parse_opts "$@"
                set -- "''${rest[@]}"
                need_host "''${1:-}"
                local script sudo=""
                if [ "$(id -u)" -ne 0 ]; then sudo=sudo; fi
                script=$(nix build --no-link --print-out-paths "$root#nixosConfigurations.$1.config.system.build.mountScript")
                info "$1: mounting under /mnt (no formatting)"
                $sudo "$script"
              }

              cmd_list() {
                load_data
                local h k f
                printf '%-24s %-6s %-8s %s\n' HOST KEY FACTER TARGET
                while read -r h; do
                  k=no
                  [ -f "$root$(field "$h" age)" ] && [ -f "$root$(field "$h" pub)" ] && k=yes
                  f=no
                  [ -f "$root$(field "$h" facter)" ] && f=yes
                  printf '%-24s %-6s %-8s %s\n' "$h" "$k" "$f" \
                    "$(field "$h" method)$([ -n "$(field "$h" target)" ] && echo " $(field "$h" user)@$(field "$h" target)")"
                done < <(jq -r 'keys[]' <<<"$data")
              }

              [ $# -gt 0 ] || { usage; exit 1; }
              cmd=$1
              shift
              case $cmd in
                list) cmd_list ;;
                new) cmd_new "$@" ;;
                facter) cmd_facter "$@" ;;
                plan) cmd_plan "$@" ;;
                commit) cmd_commit "$@" ;;
                mount) cmd_mount "$@" ;;
                completion) print_completion "$@" ;;
                help | -h | --help) usage ;;
                *) usage; die "unknown command '$cmd'" ;;
              esac
            '';
          };
        in
        {
          packages.provision-cli = provision;
          make-shells.default = cli.shellFor provision;
        };
    }
  )
