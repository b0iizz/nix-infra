# Firefox and LibreWolf, wrapped: nixpkgs' own `wrapFirefox` package, with
# policies, autoconfig prefs and extensions rendered from `passthru.settings`.
#
#   settings.browser     the package to customise, `pkgs.librewolf` or
#                        `pkgs.firefox`. It has to be the *wrapped* package:
#                        `pkgs.librewolf` hands the unwrapped one's
#                        librewolf.cfg and policies.json to `wrapFirefox`
#                        (`extraPrefsFiles`, `extraPoliciesFiles`), and calling
#                        `wrapFirefox librewolf-unwrapped` yourself drops both.
#                        Without them LibreWolf 157 cannot even initialise its
#                        search service ("Failed to get engine data from Remote
#                        Settings"): its Remote Settings allow-list is a pref in
#                        librewolf.cfg.
#   settings.policies    enterprise policies (policies.json), merged over the
#                        ones the browser ships with
#   settings.extraPrefs  autoconfig (mozilla.cfg) appended to the browser's own
#   settings.extensions  `fetchFirefoxAddon` packages installed declaratively,
#                        or null for none (and manual installs stay allowed).
#                        Only for LibreWolf: Firefox enforces addon signatures
#                        and refuses them. A list, even an empty one, also
#                        blocks manual installs.
#   settings.overrides   `.override` arguments (attrsets or functions) applied
#                        to the browser last; `wrapper.override` appends one.
#
# The result of `wrapFirefox` is a finished wrapper already, so the generic
# wrapper does not wrap it again (`wrapper.exes = [ ]`); `wrapper.env` and
# friends therefore have no effect unless `exes` is set.
#
# The wrapper has `.override` and `.version` like the browser package, so it
# works as `programs.firefox.package` (note that module's policies file in
# /etc/firefox shadows the wrapper's own on Firefox). Without that module,
# `flake.modules.nixos.librewolf` installs the wrapper.
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  program = browser: [
    {
      passthru.settings = {
        browser = _: browser;
        policies = _: { };
        extraPrefs = _: "";
        extensions = _: null;
        overrides = _: [ ];
      };
      passthru.wrapper.exes = _: [ ];
    }
    (
      final:
      let
        s = final.passthru.settings;
        package = lib.foldl' (pkg: o: pkg.override o) (s.browser.override (
          {
            extraPolicies = s.policies;
            extraPrefs = s.extraPrefs;
          }
          // lib.optionalAttrs (s.extensions != null) { nixExtensions = s.extensions; }
        )) s.overrides;
      in
      {
        passthru.package.__assign = package;
        passthru.version.__assign = package.version;
        # `.override` as on the browser package, which is what NixOS'
        # `programs.firefox` calls: the arguments go to the wrapped browser,
        # after those from the settings.
        passthru.override.__assign =
          o: final.passthru.extend { passthru.settings.overrides = old: old ++ [ o ]; };
        meta.__assign = package.meta or { };
      }
    )
  ];

  # Styling is off for now. To theme DuckDuckGo like the desktop, swap
  # `ddgUrl` for the themed one below (catppuccin-mocha, base16, and the
  # monospace font of the system theme).
  ddgUrl = "https://duckduckgo.com/?q={searchTerms}";
  # ddg = {
  #   font = "DejaVuSansM Nerd Font Mono";
  #   colors = {
  #     base00 = "1e1e2e";
  #     base01 = "181825";
  #     base04 = "585b70";
  #     base05 = "cdd6f4";
  #   };
  # };
  # ddgUrl =
  #   with ddg.colors;
  #   "https://duckduckgo.com/?kaj=m&kbg=-1&kbe=0&kbi=1&kbj=1&kp=-2&kav=1&k1=-1&kt=${lib.escapeURL ddg.font}&kae=d&k7=${base00}&kj=${base01}&k9=${base05}&kaa=${base04}&k8=${base05}&kx=${base05}&k21=${base01}&q={searchTerms}";

  personal = {
    passthru.settings = {
      policies = _: {
        DisableAppUpdate = true;
        ExtensionUpdate = false;

        # Passwords live in Bitwarden
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;
        OfferToSaveLogins = false;
        PasswordManagerEnabled = false;
        DisableMasterPasswordCreation = true;

        DefaultDownloadDirectory = "\${home}/Downloads";
        DownloadDirectory = "\${home}/Downloads";
        PromptForDownloadLocation = false;

        NoDefaultBookmarks = true;
        DisplayBookmarksToolbar = "never";
        DisplayMenuBar = "never";
        ShowHomeButton = false;

        EncryptedMediaExtensions = {
          Enabled = true;
          Locked = true;
        };
        PictureInPicture = {
          Enabled = false;
          Locked = true;
        };

        DNSOverHTTPS = {
          Enabled = true;
          ProviderURL = "https://doh.ffmuc.net/dns-query";
          Locked = true;
          Fallback = true;
        };
        NetworkPrediction = false;
        HttpsOnlyMode = "force_enabled";
        Certificates.ImportEnterpriseRoots = true;

        SearchBar = "unified";
        SearchSuggestEnabled = true;
        SearchEngines = {
          Default = "DuckDuckGo (custom)";
          Add = [
            {
              Name = "DuckDuckGo (custom)";
              URLTemplate = ddgUrl;
              SuggestURLTemplate = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";
              Method = "GET";
              Alias = "ddgc";
            }
            {
              Name = "Noogle Dev";
              URLTemplate = "https://noogle.dev/q?term={searchTerms}";
              Method = "GET";
              Alias = "noo";
            }
            {
              Name = "Nixpkgs Search";
              URLTemplate = "https://search.nixos.org/packages?channel=unstable&query={searchTerms}";
              Method = "GET";
              Alias = "pkgs";
            }
            {
              Name = "Nixos Options Search";
              URLTemplate = "https://search.nixos.org/options?channel=unstable&query={searchTerms}";
              Method = "GET";
              Alias = "options";
            }
          ];
          # The stock engines of Firefox and LibreWolf; a name that does not
          # exist (any more) is ignored, so this only ever needs to grow.
          Remove = [
            "Google"
            "DuckDuckGo"
            "DuckDuckGo No-AI"
            "Bing"
            "Perplexity"
            "Ecosia"
            "Mojeek"
            "Startpage"
            "Wikipedia (en)"
          ];
          PreventInstalls = true;
        };

        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        FirefoxHome = {
          Search = true;
          TopSites = false;
          SponsoredTopSites = false;
          Highlights = false;
          Stories = false;
          SponsoredStories = false;
          Locked = true;
        };
        Homepage = {
          URL = "about:blank";
          StartPage = "none";
          Locked = true;
        };

        # Popups are not blocked, and that is locked. Is that wanted?
        PopupBlocking = {
          Default = false;
          Locked = true;
        };

        RequestedLocales = [
          "de"
          "en-US"
        ];

        SanitizeOnShutdown = {
          Cache = true;
          Cookies = true;
          FormData = true;
          Locked = true;
        };

        UserMessaging = {
          ExtensionRecommendations = false;
          FeatureRecommendations = false;
          UrlbarInterventions = false;
          SkipOnboarding = true;
          MoreFromMozilla = false;
          FirefoxLabs = false;
          Locked = true;
        };
        FirefoxSuggest = {
          WebSuggestions = false;
          SponsoredSuggestions = false;
          ImproveSuggest = false;
          Locked = true;
        };

        DisableFeedbackCommands = true;
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        SkipTermsOfUse = true;
        DisableFirefoxAccounts = true;
        DisableFormHistory = true;
        DisableProfileImport = true;
        DisableProfileRefresh = true;
        DisableSetDesktopBackground = true;

        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
          EmailTracking = true;
          SuspectedFingerprinting = true;
        };
        Cookies = {
          Behavior = "reject-tracker";
          BehaviorPrivateBrowsing = "reject";
          Locked = true;
        };

        InstallAddonsPermission.Default = false;
      };

      extraPrefs = _: ''
        // Show more ssl cert infos
        lockPref("security.identityblock.show_extended_validation", true);
      '';
    };
  };

  # Declarative extensions: other modules add theirs with
  #   passthru.settings.extensions = old: old ++ [ (pkgs.fetchFirefoxAddon { ... }) ];
  # uBlock Origin needs no entry: LibreWolf's policies.json installs it.
  librewolf = {
    passthru.settings.extensions = _: [ ];
  };
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrappers.librewolf = lib.mkMerge [
        (w.program (program pkgs.librewolf))
        (lib.mkAfter [
          personal
          librewolf
        ])
      ];
      wrappers.firefox = lib.mkMerge [
        (w.program (program pkgs.firefox))
        (lib.mkAfter [ personal ])
      ];
    };

  # Opt-in per host (`roles = [ "librewolf" ]`), not part of `base`.
  flake.modules.nixos.librewolf =
    { pkgs, ... }:
    w.collect [ self.packages.${pkgs.stdenv.hostPlatform.system}.librewolf ];
}
