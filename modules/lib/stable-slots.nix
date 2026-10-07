{ lib, ... }:
let
  inherit (lib)
    attrNames
    filter
    foldl'
    length
    listToAttrs
    mod
    nameValuePair
    sort
    ;

  hash =
    salt: key: n:
    lib.fromHexString (
      builtins.substring 0 8 (builtins.hashString "sha256" "${salt}/${key}/${toString n}")
    );

  # Give every key a slot in [0, capacity) that depends on the key itself and
  # not on the order or number of the other keys.
  #
  # A key's preferred slot is a hash of `salt` and the key; on a collision
  # it is rehashed. Keys claim slots in hash order (not alphabetical), so
  # adding or removing a key can only move keys that collide with it.
  # Slots in `pinned` (key -> slot) are taken first and never move.
  #
  # Example: stableSlots { salt = "net"; capacity = 254; keys = [ "a" "b" ]; pinned = { }; }
  stableSlots =
    {
      salt,
      capacity,
      keys,
      pinned ? { },
    }:
    let
      free = filter (k: !(pinned ? ${k})) keys;
      pinnedTaken = listToAttrs (map (k: nameValuePair (toString pinned.${k}) k) (attrNames pinned));

      # After a few rehashes, fall back to scanning from the preferred slot so
      # that a nearly full space still terminates.
      probe =
        taken: key:
        let
          go =
            n:
            let
              slot = if n < 16 then mod (hash salt key n) capacity else mod (hash salt key 0 + (n - 15)) capacity;
            in
            if !(taken ? ${toString slot}) then slot else go (n + 1);
        in
        go 0;

      order = sort (
        a: b: (hash salt a 0 < hash salt b 0) || (hash salt a 0 == hash salt b 0 && a < b)
      ) free;

      result =
        foldl'
          (
            acc: key:
            let
              slot = probe acc.taken key;
            in
            {
              taken = acc.taken // {
                ${toString slot} = key;
              };
              slots = acc.slots // {
                ${key} = slot;
              };
            }
          )
          {
            taken = pinnedTaken;
            slots = pinned;
          }
          order;
    in
    if length keys > capacity then
      throw "stableSlots: ${toString (length keys)} keys do not fit into ${toString capacity} slots"
    else
      result.slots;
in
{
  flake.lib.stableSlots = stableSlots;
}
