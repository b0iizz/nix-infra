{ lib, ... }:
let
  inherit (lib) head findFirst;

  prefers =
    a: b: prefs:
    findFirst (x: x == a || x == b) b prefs == a;

  solve =
    state:
    let
      freeActive = builtins.filter (active: !(state.matches ? ${active})) (
        builtins.attrNames state.active
      );

      current = head freeActive;
      currentPreferences = state.active.${current};
      attempt = head currentPreferences;
      other = state.revMatches.${attempt};
    in
    if freeActive == [ ] then
      state
    else if currentPreferences == [ ] then
      # When no preferences remain we failed to match anything
      solve {
        inherit (state) active passive revMatches;
        matches = state.matches // {
          ${current} = null;
        };
      }
    else if !(state.revMatches ? ${attempt}) then
      # We matched this passive element for the first time
      (
        if builtins.elem current state.passive.${attempt} then
          solve {
            inherit (state) passive;
            active = state.active // {
              ${current} = lib.tail currentPreferences;
            };
            matches = state.matches // {
              ${current} = attempt;
            };
            revMatches = state.revMatches // {
              ${attempt} = current;
            };
          }
        else
          # This passive candidate does not want us in the first place
          solve {
            inherit (state) passive matches revMatches;
            active = state.active // {
              ${current} = lib.tail currentPreferences;
            };
          }
      )
    else if prefers current other state.passive.${attempt} then
      # The current one wins against previous candidate
      solve {
        inherit (state) passive;
        active = state.active // {
          ${current} = lib.tail currentPreferences;
        };
        matches = (removeAttrs state.matches [ other ]) // {
          ${current} = attempt;
        };
        revMatches = state.revMatches // {
          ${attempt} = current;
        };
      }
    else
      # We lost against the other candidate so we have to try somewhere else
      solve {
        inherit (state) passive matches revMatches;
        active = state.active // {
          ${current} = lib.tail currentPreferences;
        };
      };

  gale-shapley =
    active: passive:
    (solve {
      inherit active passive;
      matches = { };
      revMatches = { };
    }).matches;

in
{
  flake.lib.gale-shapley = gale-shapley;
}
