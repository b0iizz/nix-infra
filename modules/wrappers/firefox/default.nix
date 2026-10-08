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
#
# The result of `wrapFirefox` is a finished wrapper already, so the generic
# wrapper does not wrap it again (`wrapper.exes = [ ]`); `wrapper.env` and
# friends therefore have no effect unless `exes` is set.
#
# `.override` and `.overrideAttrs` of the wrapper act on the browser package (see
# modules/lib/wrappers.nix), so it works as `programs.firefox.package`. That
# module's /etc/firefox/policies file shadows the wrapper's own policies on
# Firefox, which `flake.modules.nixos.firefox` takes care of. LibreWolf is
# installed by `flake.modules.nixos.librewolf`.
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
      };
      passthru.wrapper.exes = _: [ ];
    }
    (
      final:
      let
        s = final.passthru.settings;
        t = final.passthru.theme;
        dark = t.polarity == "dark";
        # Fonts and color scheme from `passthru.theme`, before `settings.extraPrefs`.
        themePrefs = ''
          defaultPref("font.name.monospace.x-western", ${builtins.toJSON t.fonts.monospace});
          defaultPref("font.name.sans-serif.x-western", ${builtins.toJSON t.fonts.sansSerif});
          defaultPref("font.name.serif.x-western", ${builtins.toJSON t.fonts.serif});
          defaultPref("browser.theme.toolbar-theme", ${if dark then "0" else "1"});
          defaultPref("browser.theme.content-theme", ${if dark then "0" else "1"});
          defaultPref("layout.css.prefers-color-scheme.content-override", ${if dark then "0" else "1"});
        '';
        package = s.browser.override (
          {
            extraPolicies = s.policies;
            extraPrefs = themePrefs + s.extraPrefs;
          }
          // lib.optionalAttrs (s.extensions != null) { nixExtensions = s.extensions; }
        );
      in
      {
        passthru.package.__assign = package;
        meta.__assign = package.meta or { };
      }
    )
  ];

  personal =
    final:
    let
      c = final.passthru.theme.colors;
      # DuckDuckGo's own theme parameters, filled from `passthru.theme`
      ddgUrl = "https://duckduckgo.com/?kaj=m&kbg=-1&kbe=0&kbi=1&kbj=1&kp=-2&kav=1&k1=-1&kt=${lib.escapeURL final.passthru.theme.fonts.monospace}&kae=d&k7=${c.base00}&kj=${c.base01}&k9=${c.base05}&kaa=${c.base04}&k8=${c.base05}&kx=${c.base05}&k21=${c.base01}&q={searchTerms}";
    in
    {
      passthru.settings = {
        policies = _: {
          DisableAppUpdate = true;
          ExtensionUpdate = true;

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
    { environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.librewolf ]; };

  # Firefox reads /etc/firefox/policies/policies.json *instead of* the one next
  # to the binary whenever it exists, and `programs.firefox` always writes it.
  # So the wrapper's policies are handed to that module, which makes the file
  # the system reads the complete one (LibreWolf has no such system file).
  flake.modules.nixos.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.firefox = {
        enable = true;
        package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.firefox;
        policies = config.programs.firefox.package.passthru.settings.policies or { };
      };
    };
}
