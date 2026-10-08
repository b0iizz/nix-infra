{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib)
    attrNames
    elem
    filterAttrs
    genAttrs
    intersectLists
    mapAttrs
    mkDefault
    mkMerge
    mkOption
    types
    unique
    ;

  rcfg = config.registry;

  adminSecretId = user: "user-ssh-${user}";

  # agenix-rekey's `ssh-ed25519` generator writes the public key next to the
  # generated secret as `<secret>.pub`.
  adminPublicKey =
    user:
    let
      file = rcfg.secretsDir + "/generated/${adminSecretId user}.pub";
    in
    if builtins.pathExists file then lib.fileContents file else null;

  passwordModeType = types.enum [
    "generated"
    "locked"
  ];

  passwordOption = mkOption {
    type = passwordModeType;
    default = "generated";
    description = ''
      `generated`: a random password is created with agenix-rekey
      (`agenix generate`). The plaintext is kept as an intermediary secret
      that never reaches a host, only its yescrypt hash is deployed and
      used as `hashedPasswordFile`. Read the plaintext with
      `agenix edit` on `user-plain-<host>-<user>`.

      `locked`: no password at all, the account can only be used through
      SSH keys (or `su`/`sudo` from another account).

      Hosts without a host key can't decrypt secrets yet and get a locked
      account until one is added.
    '';
  };

  userSubmodule = types.submodule (
    { name, ... }:
    {
      options = {

        enable = mkOption {
          type = types.bool;
          default = true;
        };

        description = mkOption {
          type = types.str;
          default = "";
          description = "Full name, shown as GECOS field.";
        };

        uid = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Fixed uid. Pin it to keep ownership consistent across hosts
            (NFS, copied data, ...).
          '';
        };

        admin = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Administrator: member of `wheel`. Instead of accepting
            `registry.adminKeys`, an SSH key pair is generated for the user
            with agenix-rekey (`agenix generate`). The public key
            `secrets/generated/user-ssh-<user>.pub` is authorized for the
            user and for root (`registry.rootKeys`) on top of `sshKeys`.
            Commit the `.pub` file. The private key is only installed on
            the hosts in `keyHosts`.
          '';
        };

        keyHosts = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "workstation" ];
          description = ''
            Hosts (that can decrypt secrets) where an admin's generated
            private key is installed as `~/.ssh/id_ed25519` (plus `.pub`).
            Keep this to the machines you work from: the key opens every
            host, so each host listed here can reach all the others.
          '';
        };

        extraGroups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Groups besides `wheel`. All of them must exist on every host
            the user is created on.
          '';
        };

        shell = mkOption {
          type = types.str;
          default = "bash";
          example = "zsh";
          description = "Attribute name of the login shell in `pkgs`.";
        };

        sshKeys = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "SSH public keys allowed to log in as this user.";
        };

        hosts = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = "Hosts to create the user on. `null` means every host.";
        };

        password = passwordOption;

      };

      config.description = lib.mkDefault name;
    }
  );

  # Everything a single host needs to know, handed to the NixOS module as
  # the `userAccounts` module argument.
  accountsFor = host: {
    inherit (rcfg.userPolicy) mutableUsers sudoNeedsPassword perHostPasswords;
    root = rcfg.rootUser;
    adminPublicKeys = lib.mapAttrs (name: _: adminPublicKey name) rcfg.users;
    roleGroups = lib.unique (
      lib.concatMap (role: rcfg.userPolicy.roleGroups.${role} or [ ]) host.roles
    );
    users = filterAttrs (_: u: u.enable && (u.hosts == null || elem host.hostName u.hosts)) rcfg.users;
  };

  adminNames = attrNames (filterAttrs (_: u: u.enable && u.admin) rcfg.users);
in
{

  options.registry = {

    users = mkOption {
      type = types.attrsOf userSubmodule;
      default = { };
      description = "Human accounts which are created on every host (or the hosts they list).";
    };

    rootUser = {

      password = passwordOption;

      shell = mkOption {
        type = types.str;
        default = "bash";
        description = "Attribute name of root's shell in `pkgs`.";
      };

      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Keys for root in addition to `registry.adminKeys`.";
      };

    };

    rootKeys = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = rcfg.adminKeys ++ lib.remove null (map adminPublicKey adminNames);
      defaultText = "`adminKeys` plus the generated public keys of all admins";
      description = ''
        Keys authorized for root on every host and on the installer
        images. Without any, nothing can log in to a fresh install.
      '';
    };

    userPolicy = {

      mutableUsers = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Allow `passwd`/`useradd` to persist changes. When disabled
          (default) accounts and passwords come from this configuration
          only and are reset on every activation.
        '';
      };

      sudoNeedsPassword = mkOption {
        type = types.bool;
        default = true;
        description = "Whether `wheel` has to enter their password for sudo.";
      };

      perHostPasswords = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Generate a separate password per user and host so that one
          compromised host does not reveal the password of the others.
          When disabled each user has a single password on all hosts.
        '';
      };

      roleGroups = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        example = {
          desktop = [ "networkmanager" ];
        };
        description = ''
          Groups added to every user on hosts that have the given role
          (`registry.hosts.<name>.roles`). The groups must exist on those
          hosts, so only list groups the role itself creates.
        '';
      };

    };

  };

  config = {

    registry.extraHostArgs.userAccounts = accountsFor;

    flake.modules.nixos.base.imports = [ self.modules.nixos.users ];

    flake.modules.nixos.users =
      {
        config,
        lib,
        pkgs,
        userAccounts,
        ...
      }:
      let
        inherit (userAccounts) users root;
        hostName = config.networking.hostName;
        canDecrypt = config.host-context.hostkey.publicKey != null;

        secretId =
          kind: user:
          if userAccounts.perHostPasswords then
            "user-${kind}-${hostName}-${user}"
          else
            "user-${kind}-${user}";

        generated = lib.optionalAttrs canDecrypt (
          filterAttrs (_: u: u.password == "generated") (users // { inherit root; })
        );

        shellOf = name: pkgs.${name};
        shellNames = unique (map (u: u.shell) (lib.attrValues users) ++ [ root.shell ]);

        passwordSecrets =
          user:
          let
            plain = config.age.secrets.${secretId "plain" user};
          in
          {
            # Only exists for the generator: 48 random alphanumerics.
            ${secretId "plain" user} = {
              generator.script = "alnum";
              intermediary = true;
            };
            ${secretId "hash" user} = {
              generator = {
                dependencies = [ plain ];
                script =
                  {
                    lib,
                    pkgs,
                    decrypt,
                    deps,
                    ...
                  }:
                  ''
                    pw=$(${decrypt} ${lib.escapeShellArg (lib.head deps).file})
                    printf '%s' "$pw" | ${pkgs.whois}/bin/mkpasswd -s -m yescrypt
                  '';
              };
              mode = "0400";
            };
          };

        adminUsers = filterAttrs (_: u: u.admin) users;

        homeOf = user: config.users.users.${user}.home;

        # Pregenerated identity, installed as ~/.ssh/id_ed25519 on the user's
        # `keyHosts`. Every other host only declares it so that
        # `agenix generate` creates it; it never reaches them.
        holdsKey = user: elem hostName adminUsers.${user}.keyHosts;
        adminKeySecret = user: {
          ${adminSecretId user} = {
            generator.script = "ssh-ed25519";
          }
          // (
            if holdsKey user then
              {
                path = "${homeOf user}/.ssh/id_ed25519";
                owner = user;
                mode = "0400";
              }
            else
              { intermediary = true; }
          );
        };

        adminKeyTmpfiles =
          user:
          let
            group = config.users.users.${user}.group;
            pub = userAccounts.adminPublicKeys.${user};
          in
          [ "d ${homeOf user}/.ssh 0700 ${user} ${group} -" ]
          ++ lib.optional (
            pub != null
          ) "f+ ${homeOf user}/.ssh/id_ed25519.pub 0644 ${user} ${group} - ${pub}";

        hashFile = user: config.age.secrets.${secretId "hash" user}.path;
        passwordFor = user: lib.optionalAttrs (generated ? ${user}) { hashedPasswordFile = hashFile user; };
      in
      {
        config = {

          users.mutableUsers = mkDefault userAccounts.mutableUsers;
          security.sudo.wheelNeedsPassword = mkDefault userAccounts.sudoNeedsPassword;

          users.users = mkMerge [
            (mapAttrs (
              name: u:
              {
                isNormalUser = true;
                inherit (u) description uid;
                shell = shellOf u.shell;
                extraGroups = lib.optional u.admin "wheel" ++ u.extraGroups ++ userAccounts.roleGroups;
                openssh.authorizedKeys.keys =
                  u.sshKeys
                  ++ lib.optional (
                    u.admin && userAccounts.adminPublicKeys.${name} != null
                  ) userAccounts.adminPublicKeys.${name};
              }
              // (passwordFor name)
            ) users)

            {
              root = {
                shell = shellOf root.shell;
                openssh.authorizedKeys.keys = root.sshKeys;
              }
              // (passwordFor "root");
            }
          ];

          # Login shells other than bash need their program module for
          # /etc/shells and completion.
          programs =
            genAttrs
              (intersectLists shellNames [
                "zsh"
                "fish"
              ])
              (_: {
                enable = mkDefault true;
              });

          age.secrets = mkMerge (
            map passwordSecrets (attrNames generated)
            ++ lib.optionals canDecrypt (map adminKeySecret (attrNames adminUsers))
          );

          systemd.tmpfiles.rules = lib.optionals canDecrypt (
            lib.concatMap adminKeyTmpfiles (lib.filter holdsKey (attrNames adminUsers))
          );

          assertions = [
            {
              assertion = lib.all (n: userAccounts.adminPublicKeys.${n} != null) (attrNames adminUsers);
              message = "admin users without a generated key: run `agenix generate` and commit secrets/generated/user-ssh-*.pub";
            }
            {
              assertion = !(elem "root" (attrNames users));
              message = "registry.users must not define 'root', use registry.rootUser";
            }
          ];

        };
      };

  };

}
