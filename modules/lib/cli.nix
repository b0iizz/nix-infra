# Shared plumbing of the fleet CLIs (deploy, provision, host-keys).
#
#   cli.mkCli pkgs {
#     name = "deploy";
#     dataAttr = "deployData";   # flake output with per-host data, read live
#     runtimeInputs = [ ... ];   # on top of nix, jq, openssh, git, coreutils
#     completion = ''...'';      # bash completion script
#     text = ''...'';            # the tool, after the prelude below
#   }
#
# returns the package, with its completion installed where bash-completion
# looks. `cli.shellFor tool` is the `make-shells` entry that also sources the
# completion (nix develop does not put share/bash-completion on XDG_DATA_DIRS).
{ lib, self, ... }:
let
  # The CLIs work on the checked-out repository, not on the store copy, so
  # every path they need is handed over relative to the flake root.
  relPath = p: lib.removePrefix (toString self) (toString p);

  prelude =
    { name, dataAttr }:
    ''
      die() { echo "${name}: $*" >&2; exit 1; }
      info() { echo "${name}: $*" >&2; }

      root=''${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
      export FLAKE_ROOT=$root

      # Host data, read from the checkout on first use (not baked into the
      # tool), so hosts added since the last build are known at once.
      data=
      load_data() {
        [ -n "$data" ] || data=$(nix eval --json "$root#${dataAttr}") ||
          die "cannot evaluate $root#${dataAttr}"
      }
      field() { load_data; jq -r --arg h "$1" --arg k "$2" '.[$h][$k] // empty' <<<"$data"; }
      all_hosts() { load_data; jq -r 'keys[]' <<<"$data"; }
      is_host() { load_data; jq -e --arg h "$1" 'has($h)' <<<"$data" >/dev/null; }
      need_host() {
        [ -n "''${1:-}" ] || die "missing <host> argument"
        is_host "$1" || die "unknown host '$1' (known: $(jq -r 'keys | join(", ")' <<<"$data"))"
      }

      # user@addr: the target as given if it names a user, else <user>@<target>.
      to_dest() { case $2 in *@*) echo "$2" ;; *) echo "$1@$2" ;; esac; }

      # Scratch space, on a tmpfs when possible. Plaintext keys pass through
      # it, so files are shredded on exit.
      tmp=
      cleanup() {
        if [ -n "$tmp" ]; then
          # an ssh master (ssh_setup) is a logged-in session for whoever reaches its socket
          find "$tmp" -type s -exec ssh -o ControlPath={} -O exit _ \; 2>/dev/null || true
          find "$tmp" -type f -exec shred -u {} + 2>/dev/null || true
          rm -rf "$tmp"
        fi
      }
      trap cleanup EXIT
      mk_tmp() { [ -n "$tmp" ] || tmp=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}" ${name}.XXXXXX); }

      # ssh_setup <host> [host.pub]: sets $sshopts (array) and
      # exports NIX_SSHOPTS. With a public key file, ssh trusts exactly that
      # key, from a known_hosts file generated from it; without one it falls
      # back to accept-new. A known_hosts line is `<host> <type> <key>`: the
      # file's trailing comment must go, ssh would read it as a marker.
      # All ssh calls to a host share one connection, so a FIDO2 key is touched
      # once per run (nixos-rebuild puts its own ControlPath after NIX_SSHOPTS,
      # the first one wins); cleanup closes it.
      sshopts=()
      ssh_setup() {
        local h=$1 pubfile=''${2:-} kh type key
        mapfile -t sshopts < <(jq -r --arg h "$h" '.[$h].sshOpts[]' <<<"$data")
        mk_tmp
        sshopts+=(-o ControlMaster=auto -o "ControlPath=$tmp/%C" -o ControlPersist=60)
        if [ -n "$pubfile" ] && [ -f "$pubfile" ]; then
          kh=$tmp/$h.known_hosts
          read -r type key _ <"$pubfile"
          # HostKeyAlias: the line matches whatever address, port or ssh
          # config alias the target is reached by.
          echo "$h $type $key" >"$kh"
          sshopts+=(-o "UserKnownHostsFile=$kh" -o "HostKeyAlias=$h" -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes)
        else
          info "$h: no committed host key; falling back to accept-new"
          sshopts+=(-o StrictHostKeyChecking=accept-new)
        fi
        export NIX_SSHOPTS="''${sshopts[*]}"
      }

      # pick_dest <host> <user> <target>...: sets $dest to the first user@target
      # whose sshd answers with the key $sshopts expect (set them first). The
      # probe stops before authentication, so it costs no FIDO2 touch.
      # ponytail: reads OpenSSH's "Permission denied" wording; a probe that
      # logs in is the upgrade if that ever changes.
      pick_dest() {
        local h=$1 user=$2 t out
        shift 2
        for t in "$@"; do
          dest=$(to_dest "$user" "$t")
          # ssh keeps the first value of an option, so these beat $sshopts.
          out=$(ssh -o ControlPath=none -o PreferredAuthentications=none -o ConnectTimeout=5 \
            -o LogLevel=ERROR "''${sshopts[@]}" "$dest" true 2>&1 </dev/null || true)
          [[ $out != *"Permission denied"* ]] || return 0
          info "$h: skipping $dest: ''${out##*$'\n'}"
        done
        die "$h: no target fits (tried: $*)"
      }
    '';

  mkCli =
    pkgs:
    {
      name,
      dataAttr,
      runtimeInputs,
      completion,
      text,
    }@args:
    let
      completionFile = pkgs.writeText "${name}.bash" completion;
      script = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = runtimeInputs ++ [
          pkgs.nix
          pkgs.jq
          pkgs.openssh
          pkgs.gitMinimal
          pkgs.coreutils
        ];
        text = ''
          ${prelude { inherit name dataAttr; }}
          print_completion() {
            [ "''${1:-}" = bash ] || die "usage: ${name} completion bash"
            cat ${completionFile}
          }

          ${text}
        '';
      };
    in
    pkgs.symlinkJoin {
      inherit name;
      paths = [ script ];
      postBuild = ''
        install -Dm644 ${completionFile} $out/share/bash-completion/completions/${name}
      '';
      meta.mainProgram = name;
      # The same tool calling other programs: they come first on its PATH, so
      # a test can stand in for nix, ssh, ... (see modules/vm-test.nix).
      passthru.withRuntimeInputs = runtimeInputs: mkCli pkgs (args // { inherit runtimeInputs; });
    };

  shellFor = tool: {
    packages = [ tool ];
    shellHook = ''
      if [ -n "''${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
        source <(${tool.meta.mainProgram} completion bash)
      fi
    '';
  };
in
{
  flake.lib.cli = {
    inherit relPath mkCli shellFor;
  };
}
