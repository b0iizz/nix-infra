# spotify-player, wrapped: config rendered from `passthru.settings`, written
# through the `files` feature (modules/wrappers/files.nix).
#
#   settings.app             app.toml (deep-infusable, starts from the defaults)
#   settings.keymap          key sequence -> command, overlaid on the built-in
#                            keymap
#   settings.keymapDefaults  false: unbind every built-in key not rebound above
#   settings.theme           theme.toml
#   settings.forceSixelAlacritty
#                            run as TERM=foot inside alacritty, which makes the
#                            cover art render via sixel
#
# Programs for the cover image viewer go in `passthru.path`, and extra files in
# `passthru.files`, as for any wrapper.
#
# `spotify-player-default` is the program as is, `spotify-player` adds the
# personal layer. The program is ordered first, so other modules can extend
# either with `lib.mkAfter`.
{ self, lib, ... }:
let
  w = self.lib.wrappers;

  defaultApp = fromTOML (builtins.readFile ./app.toml);

  # spotify-player merges the user keymap over its built-in one, which is what
  # keymap.toml lists. It is only needed to unbind keys.
  builtinKeymap = lib.listToAttrs (
    map (k: lib.nameValuePair k.key_sequence k.command) (
      (fromTOML (builtins.readFile ./keymap.toml)).keymaps
    )
  );

  program = pkgs: [
    (w.withPackage pkgs.spotify-player)
    {
      passthru.settings = {
        app = _: defaultApp;
        keymap = _: { };
        keymapDefaults = _: true;
        theme = _: { };
        forceSixelAlacritty = _: false;
      };
    }
    (
      final:
      let
        s = final.passthru.settings;
        h = w.fileHelpers pkgs;

        keymap =
          lib.optionalAttrs (!s.keymapDefaults) (lib.mapAttrs (_: _: "None") builtinKeymap) // s.keymap;

        # null: spotify-player's own default applies
        ifSet = cond: content: if cond then content else null;
      in
      {
        passthru.files = {
          "app.toml" = _: ifSet (s.app != defaultApp) (h.toml s.app);
          "keymap.toml" =
            _:
            ifSet (keymap != { }) (
              h.toml {
                keymaps = lib.mapAttrsToList (key_sequence: command: { inherit key_sequence command; }) keymap;
              }
            );
          "theme.toml" = _: ifSet (s.theme != { }) (h.toml s.theme);
        };

        passthru.wrapper = {
          # the folder holds only the files that differ from the defaults
          flags.__append = lib.optional (
            final.passthru.config.file != { }
          ) "--config-folder ${final.passthru.config.dir}";
          extraArgs.__append = lib.optionals s.forceSixelAlacritty [
            "--run"
            ''if [ "$TERM" = alacritty ]; then export TERM=foot; fi''
          ];
        };
      }
    )
  ];

  personal = {
    passthru.settings = {
      forceSixelAlacritty = _: true;
      keymapDefaults = _: false;
      app = {
        cover_img_length = _: 10;
        cover_img_width = _: 5;
        cover_img_scale = _: 1.8;
      };
      keymap = _: {
        "+".VolumeChange.offset = 5;
        "ü".VolumeChange.offset = -5;
        "*".VolumeChange.offset = 1;
        "Ü".VolumeChange.offset = -1;

        "home" = "PreviousTrack";
        "end" = "NextTrack";
        "space" = "ResumePause";
        "m" = "Mute";

        "R" = "Repeat";
        "S" = "Shuffle";
        "s s" = "SeekStart";
        "s f".SeekForward = { };
        "s b".SeekBackward = { };
        "." = "ShowActionsOnCurrentTrack";
        "_ _" = "PlayRandom";

        "backspace" = "PreviousPage";
        ": b" = "PreviousPage";
        "esc" = "ClosePopup";
        ": q" = "Quit";
        "?" = "OpenCommandHelp";
        ": h" = "OpenCommandHelp";

        ": r" = "RefreshPlayback";
        ": R" = "RestartIntegratedClient";

        "h" = "FocusPreviousWindow";
        "j" = "SelectNextOrScrollDown";
        "k" = "SelectPreviousOrScrollUp";
        "l" = "FocusNextWindow";
        "J" = "PageSelectNextOrScrollDown";
        "K" = "PageSelectPreviousOrScrollUp";
        "C-j" = "SelectLastOrScrollToBottom";
        "C-k" = "SelectFirstOrScrollToTop";

        "H" = "PreviousPage";
        "L" = "ChooseSelected";

        "left" = "FocusPreviousWindow";
        "C-left" = "FocusPreviousWindow";
        "down" = "SelectNextOrScrollDown";
        "up" = "SelectPreviousOrScrollUp";
        "right" = "FocusNextWindow";
        "C-right" = "FocusNextWindow";
        "page_down" = "PageSelectNextOrScrollDown";
        "page_up" = "PageSelectPreviousOrScrollUp";
        "C-page_down" = "SelectLastOrScrollToBottom";
        "C-page_up" = "SelectFirstOrScrollToTop";

        "enter" = "ChooseSelected";
        "tab" = "ShowActionsOnSelectedItem";
        "backtab" = "ShowActionsOnCurrentContext";
        "e" = "AddSelectedItemToQueue";

        ": s t" = "SwitchTheme";
        ": s d" = "SwitchDevice";
        "/" = "Search";
        ": u p" = "BrowseUserPlaylists";
        ": u i" = "BrowseUserFollowedArtists";
        ": u a" = "BrowseUserSavedAlbums";

        "g c" = "CurrentlyPlayingContextPage";
        "g t" = "TopTrackPage";
        "g r" = "RecentlyPlayedTrackPage";
        "g l" = "LikedTrackPage";
        "g L" = "LyricsPage";
        "g u l" = "LibraryPage";
        "g s" = "SearchPage";
        "g b" = "BrowsePage";
        "g e" = "Queue";
        ": o" = "OpenSpotifyLinkFromClipboard";
        "g g" = "JumpToCurrentTrackInContext";
        "g h" = "JumpToHighlightTrackInContext";

        "s t" = "SortTrackByTitle";
        "s i" = "SortTrackByArtists";
        "s a" = "SortTrackByAlbum";
        "s D" = "SortTrackByAddedDate";
        "s d" = "SortTrackByDuration";
        "s u l a" = "SortLibraryAlphabetically";
        "s u l r" = "SortLibraryByRecent";
        "s r" = "ReverseTrackOrder";
      };
    };
  };
in
{
  perSystem =
    { pkgs, ... }:
    {
      wrappers.spotify-player-default = w.program (program pkgs);
      wrappers.spotify-player = lib.mkMerge [
        (w.program (program pkgs))
        (lib.mkAfter [ personal ])
      ];
    };
}
