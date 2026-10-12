<!--
Maintainer notes. Block comments are stripped before Claude reads this file.
- Keep it under about 200 lines: the Claude Code docs say longer files lower
  adherence. Only what the code does not say; the module headers say the rest.
- When an agent makes the same mistake twice, add a pitfall with its fix.
- Re-check "Current state" when a host is installed or an open point closed.
- "Ponytail rules" is AGENTS.md of github.com/DietrichGebert/ponytail v5.0.0,
  Copyright (c) 2026 DietrichGebert, MIT licence, minus its last line.
-->

# new_infra

A Nix flake for a small NixOS fleet: hosts, disk layouts, users, secrets, a Quickshell desktop, and three bash tools that install (`provision`), update (`deploy`) and key (`host-keys`) the machines. Load: one person running the tools by hand against a few machines; judge scale against that.

## Rules that protect machines and secrets

- IMPORTANT: never run `provision commit`, `provision facter|new --target`, `disko`, `deploy switch|boot|test` or `host-keys deploy|rotate` against a real machine or disk without the user's explicit go for that run. `commit` wipes disks; `facter` and `new` with a target kexec a running machine into the installer; the others change live systems. `plan`, `list` and builds are fine.
- No plaintext secret in the repo. Secrets go through agenix-rekey. Commands that need the FIDO2 token (`agenix rekey -a`, `agenix generate`, `agenix edit`, `host-keys show|export|deploy`, and any ssh to atlas or phoebe, `deploy plan` included) are the user's: suggest `! agenix rekey -a` instead of running them.
- Once a host is installed from this repo, changing its `disko-layouts.*` (layout, swap, LUKS) means reinstalling it. Say so before changing them.
- `flake.nix` is generated: declare an input with `withInputs` in the module that needs it, then run `nix run .#write-flake`.
- Work on a branch or worktree, never on `main`. Do not push changes, give the user the merge command.

## Current state (2026-10-11)

Re-check before relying on it:

- Three hosts, all installed from this repo, so changing any `disko-layouts.*` means reinstalling that host:
  - `prometheus` (Framework 13, this laptop, `uname -n`): btrfs and swap as LVM volumes in one LUKS volume (`lsblk -f`). No `deploy.targetHosts`, so `deploy` and `host-keys deploy` for it run locally, on the running system.
  - `atlas` (home server, 192.168.178.10, no LUKS): copyparty on a RAID 1 at `/data`, published as nas.grebes.net through phoebe.
  - `phoebe` (IONOS VPS, 87.106.233.164, the only public address): TLS and reverse proxy for atlas (`modules/public-proxy/`, `edge` tunnel), Cloudflare DNS, the `public-facing` role.
- WireGuard `hub` network (`modules/wireguard.nix`, defined in `modules/hosts/phoebe`): phoebe is the hub at wg.greb.es, atlas and prometheus are spokes. `deploy` and `host-keys` try atlas and phoebe at their LAN or public address first, then at their hub address (`deploy.targetHosts`, the first that takes a login with the host key wins); `--target` tries only that one. Provisioning uses the LAN and public addresses.
- Admin access: one FIDO2 key (`ed25519-sk`) per admin and token of `secrets/master`, made by `agenix generate` (`modules/users.nix`), authorized for root and the admin on every host. agenix installs the key handles on the admin's `keyHosts` (prometheus) as `~/.ssh/id_ed25519_sk_<token>`. Each login needs a touch; the CLIs share one ssh connection per host and run (`ssh_setup` in `modules/lib/cli.nix`).
- It is graphical: niri session (greeter default), quickshell, greeter in cage. The QML runs on hardware now; read the running shell's log with `quickshell log --pid $(pgrep -f 'quickshell --path')`.
- `nix.settings.trusted-users` stays at its default (root only): a trusted user is root through the Nix daemon, which made the sudo password worthless. Nothing in the tools needs it; root on a target is always trusted.
- Never import store paths from a fleet host into this laptop's store (`nix copy --from`, `--no-check-sigs`): a broken-into host could plant paths that later deploys reuse.
- Never run on hardware: the `lock-before-sleep` swayidle hook under hyprland and sway; hibernate and resume through the encrypted swap; a remote install.

## Commands

```sh
nix flake check --no-build      # evaluates everything, 1-2 min: after every change
nix build .#checks.x86_64-linux.lib   # or host-keys, desktop-roles, treefmt, check-flake-file,
                                      # deploy-targets, niri-config, sway-config, neovim, default-shell,
                                      # impermanence-rollback (a VM, as is a full flake check)
nix build .#vm-test-prometheus  # installs the host in QEMU with the real provision CLI; minutes, needs /dev/kvm
nix fmt                         # treefmt: nixfmt, prettier (also *.md), shfmt, taplo, qmlformat
nix run .#write-flake           # regenerate flake.nix after adding an input
nix develop                     # provision, deploy, host-keys, agenix, rage, with completions
```

Which checks: every change gets `nix flake check --no-build` and `treefmt`. Desktop or QML: `desktop-roles`; qmlformat is the only thing that parses QML, nothing runs it. Disks, boot, LUKS, impermanence or `provision`: `vm-test-prometheus`. `modules/lib`: `lib`.

## Where things are

- Host: `modules/hosts/<name>/default.nix` sets `registry.hosts.<name>` (`roles`, `modules`, `deploy.*`, `provision.*`) next to its `host.pub` and `facter.json`. Options: `modules/registry.nix`. `provision new` writes a new one.
- Role: any `flake.modules.nixos.<name>`, listed by name in a host's `roles` and resolved in `modules/nixos-configurations.nix`. Host data reaches NixOS modules as `config.host-context` and as the module arguments of `registry.extraHostArgs`.
- Users and admin keys: `modules/users.nix`, policy in `modules/flake-root.nix`. Secrets: `modules/secrets.nix`, ciphertext in `secrets/` (`master/`, `host-keys/`, `generated/`, `rekeyed/<host>/`).
- Disks: `modules/disk-select.nix` picks them from `facter.json`; `modules/disko-layouts.nix` holds the layouts (roles `disko-root-*`, `disko-raid`, `disko-data`). Root wipe: `modules/lib/impermanence.nix`. What survives it: `persist.*` in `modules/persist.nix`.
- Tools: `modules/provision.nix`, `modules/deploy.nix` and `modules/host-keys.nix`, on `modules/lib/cli.nix`. At run time they read `nix eval .#<tool>Data` from the checkout.
- Desktop: the `desktop.*` contract in `modules/desktop/options.nix` and its tests in `check.nix`, QML and its modules in `modules/desktop/` (one folder per feature: `bar`, `power`, `auth`, `wallpaper`), shell and greeter in `modules/wrappers/quickshell/`. Wrapped programs: read the header of `modules/lib/wrappers.nix` first.

## Conventions

- Every module starts with a header comment: what it is, how to use it, where it is imported. Change it with the code. Other comments say why, in short plain sentences.
- A module that several roles import sets `key = "modules/<path>.nix"`, so its options are declared once.
- What Nix owns (store paths, commands, settings) reaches QML only through `desktop.data`, read as `ShellData.<name>` (the greeter: `GreeterData`). No store paths in QML.
- Tests: `lib.runTests` sets checked in a `runCommand` (`checks.lib`, `checks.desktop-roles`); machines with `pkgs.testers.runNixOSTest`.
- A `ponytail:` comment marks an accepted shortcut and names its limit.
- Commits: `<area>: <what>`, e.g. `quickshell: idle daemon and low battery warnings`, after `nix fmt`.

## How to work here

1. Read before writing: the module header, the code, every caller (`grep -rn`), the tests. For upstream behaviour read the source in the store instead of guessing (query under Pitfalls): nixpkgs' `nixos/tests/` show how to answer LUKS prompts or hibernate; Quickshell's `src/` shows what an API call does.
2. Question the request: say which reading you chose when it is ambiguous, push back on parts the need does not justify, and ask only when a wrong guess is expensive.
3. Make the smallest complete change: the ponytail rules below.
4. Prove it with the checks above. Make every new check fail once on purpose, then restore the code. Run VM tests in the background and watch the log for `subtest`, `Traceback` and the exit code.
5. Make a WIP commit before a long VM run; finish with one commit per task.
6. Get a second review before building on an interpretation and again before declaring done. Here it caught a Wi-Fi fix that broke enterprise networks.
7. Report in plain, short English: what changed per item, the evidence, what was not run, the assumptions made, the next command.

Audits and reviews: use the `ponytail-audit` and `ponytail-review` skills. Without them: order of importance is correct, safe, holds under load, tested, fast, lean. Every finding needs a concrete failing case and a `file:line`, and has four parts: what this is, the problem, the smallest fix, what happens if we skip it. Group them as Must fix, Should fix, Nice to have, number them across the groups, and fix only the numbers the user picks.

## Pitfalls

- A new file Nix "cannot find": flakes see only git-tracked files. `git add` it first; the tools do that for the files they write.
- `checks.desktop-roles` runs `test -x` on each `desktop.startup` entry, so an entry must be one executable path. Wrap a command with arguments in `pkgs.writeShellApplication`, like `lock-before-sleep` in `modules/desktop/auth/lock.nix`.
- The same check fails when QML reads a `ShellData.<name>.<key>` that no module sets. `AuthView.qml` and `AuthForm.qml` are shared with the greeter tree byte for byte (`cmp` in the check).
- `writeShellApplication` puts its `runtimeInputs` first on PATH, so stubs further back never win. Tests use `provision-cli.withRuntimeInputs [ stubs ]` from `modules/lib/cli.nix`, as `modules/vm-test.nix` does for `nix`, `disko`, `ssh`, `ssh-keyscan` and `nixos-anywhere`. `nixos-install --system` calls only `nix-env`, so a stubbed `nix` does not break it.
- NixOS test scripts are type-checked: an `if` on a constant fails (`redundant-condition`). Generate the line in Nix with `lib.optionalString`, one line per interpolation, minding Python's indentation.
- LUKS in a VM test: give the VM 4 GiB, since argon2 takes 1 GiB. Answer with `wait_for_console_text("Please enter passphrase")` and `send_console`. Root and swap are logical volumes in one LUKS volume, so one prompt (systemd initrd, the default). `age: no identity matched` lines are expected: the throwaway host key cannot decrypt the host's secrets.
- `nixos-anywhere --extra-files DIR` copies all of DIR onto `/` of the new system. Pass only what belongs there (`$extra` in `provision commit`), never the scratch directory.
- `cmd | tail; echo $?` reports `tail`: use `${PIPESTATUS[0]}`. Under `pipefail`, a `grep -v` that prints nothing fails the pipeline.
- Harmless noise: `Git tree ... is dirty`, `SQLite database ... is busy`, and `unknown flake output` for `modules`, `deployData`, `provisionData`, `hostKeysData`, `publicProxyData`.
- Claude Code worktree sessions (seen 2026-10-09, may change) refused `nix eval` and commands with a runtime variable such as `$PWD` or `$CLAUDE_JOB_DIR` in `nix`, `git` or `sed` arguments. Do what the refusal says: split the command into plain, separate calls with literal absolute paths. Query values by building a file:

```nix
# /abs/q.nix, run with: nix build --no-link --print-out-paths --impure -f /abs/q.nix
let
  f = builtins.getFlake "path:/abs/path/to/the/checkout";
  p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
in
p.writeText "q" (builtins.toJSON {
  nixpkgs = f.inputs.nixpkgs.outPath; # the locked source, e.g. nixos/tests/
  quickshell = p.quickshell.src.outPath; # any package's source
})
```

## Ponytail rules

You are a lazy senior developer. The best code is the code never written. You solve the whole problem with the least new code. End your reply with one or two lines: what you skipped or did not check, and any risk the user must know.

### Before you write

Read the task and the code it touches. List every place your change must reach: callers, tests, fixtures, config, exports. Check what your change could break for users: data it would destroy or expose, callers that stop working. That is scope. Extra features are not.

### The smallest complete change

Take the first option that fully works:

1. Does it need to exist? Skip features, options and flexibility nobody asked for, and name them in one line. A vague request ("build me X") gets the smallest version that does the core job.
2. Already in this codebase (a helper, component, service, pattern)? Use it the way the surrounding code does.
3. Standard library or a platform feature? Use it, unless the project has its own. A house component beats a native widget.
4. An installed dependency? Use it. Never add a dependency for a few lines.
5. Can it be one line a reader gets at a glance? One line.
6. Otherwise: the minimum code that works.

- Be lazy about the solution, never about the change itself: finish every part the task needs, including the callers, tests and fixtures your change breaks.
- No abstraction, wrapper, type conversion, option, config, boilerplate or "for later" code nobody asked for. Keep values in the form the platform already gives you. Deletion beats addition. Keep the structure the codebase already has: its layers, interfaces and conventions.
- The shortest working diff wins, once you know everything it must touch. A one-liner that needs decoding is not short.
- Comment only the why the code cannot show, in one line.
- Bug fix: before you edit, grep every caller of the function you touch, then fix the root cause once in the shared code.
- Code you move or merge keeps its error handling and validation.
- Between options of equal size, take the one that is correct on edge cases.
- Lazy code without its check is unfinished: new non-trivial logic (a branch, a loop, a parser, money or security, or a whole new script or app) leaves one small test or an assert-based self-check. Trivial changes need none.
- A shortcut with a known limit gets a `ponytail:` comment that names the limit and when to upgrade.

Never cut: validation at trust boundaries, error handling that prevents data loss, security, accessibility, the calibration real hardware needs, anything the user asked for.
