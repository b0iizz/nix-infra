{ lib, self, ... }:
let
  inherit (lib)
    all
    concatMapStringsSep
    elemAt
    foldl'
    genList
    head
    length
    splitString
    take
    drop
    ;

  # Addresses are parsed into `{ family; words; }` where `words` are the
  # octets (IPv4) or hextets (IPv6), most significant first. This makes
  # masking and arithmetic the same code for both families.
  wordBits = family: if family == 4 then 8 else 16;
  wordCount = family: if family == 4 then 4 else 8;
  totalBits = family: wordBits family * wordCount family;
  pow2 = self.lib.pow 2;

  fail = msg: throw "ip: ${msg}";

  # -- IPv4 ------------------------------------------------------------------

  isOctet = s: builtins.match "0|[1-9][0-9]{0,2}" s != null && lib.toInt s <= 255;

  tryParseIPv4 =
    s:
    let
      parts = splitString "." s;
    in
    if builtins.isString s && length parts == 4 && all isOctet parts then
      {
        family = 4;
        words = map lib.toInt parts;
      }
    else
      null;

  # -- IPv6 ------------------------------------------------------------------

  isHextet = s: builtins.match "[0-9a-fA-F]{1,4}" s != null;

  # "a:b:c" -> [ a b c ] (empty string -> [ ]); null on malformed input.
  # A trailing dotted quad (::ffff:1.2.3.4) is expanded to two hextets.
  parseHextets =
    s:
    if s == "" then
      [ ]
    else
      let
        parts = splitString ":" s;
        last = lib.last parts;
        v4 = tryParseIPv4 last;
        hex = if v4 != null then lib.init parts else parts;
        tail =
          if v4 == null then
            [ ]
          else
            let
              w = v4.words;
            in
            [
              (elemAt w 0 * 256 + elemAt w 1)
              (elemAt w 2 * 256 + elemAt w 3)
            ];
      in
      if all isHextet hex then map lib.fromHexString hex ++ tail else null;

  tryParseIPv6 =
    s:
    if !(builtins.isString s) || builtins.match "[0-9a-fA-F:.]+" s == null then
      null
    else
      let
        halves = lib.splitString "::" s;
        build =
          head': tail':
          let
            h = parseHextets head';
            t = parseHextets tail';
          in
          # A dotted quad may only end the address, never precede `::`.
          if h == null || t == null || lib.hasInfix "." head' then
            null
          else
            {
              inherit h t;
            };
      in
      if length halves == 1 then
        let
          w = parseHextets s;
        in
        if w != null && length w == 8 then
          {
            family = 6;
            words = w;
          }
        else
          null
      else if length halves == 2 then
        let
          r = build (elemAt halves 0) (elemAt halves 1);
          missing = if r == null then 0 else 8 - length r.h - length r.t;
        in
        if r != null && missing >= 1 then
          {
            family = 6;
            words = r.h ++ genList (_: 0) missing ++ r.t;
          }
        else
          null
      else
        null;

  # RFC 5952: lowercase, compress the longest run (>= 2) of zero hextets,
  # leftmost wins on ties.
  formatIPv6 =
    words:
    let
      scan =
        foldl'
          (
            st: w:
            let
              i = st.i;
              run = if w == 0 then (if st.cur == null then i else st.cur) else null;
              runLen = if run == null then 0 else i - run + 1;
              better = runLen > st.bestLen;
            in
            {
              i = i + 1;
              cur = run;
              bestStart = if better then run else st.bestStart;
              bestLen = if better then runLen else st.bestLen;
            }
          )
          {
            i = 0;
            cur = null;
            bestStart = 0;
            bestLen = 0;
          }
          words;
      show = ws: concatMapStringsSep ":" (w: lib.toLower (lib.toHexString w)) ws;
    in
    if scan.bestLen < 2 then
      show words
    else
      "${show (take scan.bestStart words)}::${show (drop (scan.bestStart + scan.bestLen) words)}";

  # -- generic ---------------------------------------------------------------

  tryParse =
    s:
    let
      v4 = tryParseIPv4 s;
    in
    if v4 != null then v4 else tryParseIPv6 s;

  parse =
    s:
    let
      r = tryParse s;
    in
    if r == null then fail "'${toString s}' is not a valid IPv4 or IPv6 address" else r;

  format =
    addr:
    if addr.family == 4 then concatMapStringsSep "." toString addr.words else formatIPv6 addr.words;

  # Word-wise netmask for a prefix length.
  maskWords =
    family: prefixLength:
    let
      wb = wordBits family;
    in
    genList (
      i:
      let
        bits = lib.min wb (lib.max 0 (prefixLength - i * wb));
      in
      pow2 wb - pow2 (wb - bits)
    ) (wordCount family);

  tryParseCidr =
    s:
    let
      m = if builtins.isString s then builtins.match "([^/]+)/([0-9]{1,3})" s else null;
      addr = if m == null then null else tryParse (elemAt m 0);
      len = if m == null then null else lib.toInt (elemAt m 1);
    in
    if addr != null && len <= totalBits addr.family then addr // { prefixLength = len; } else null;

  parseCidr =
    s:
    let
      r = tryParseCidr s;
    in
    if r == null then fail "'${toString s}' is not a valid CIDR" else r;

  formatCidr = c: "${format c}/${toString c.prefixLength}";

  # Zero all host bits.
  networkOf =
    c:
    c
    // {
      words = lib.zipListsWith builtins.bitAnd c.words (maskWords c.family c.prefixLength);
    };

  # Add a non-negative offset to an address.
  addOffset =
    addr: n:
    let
      base = pow2 (wordBits addr.family);
      go =
        ws: carry:
        if ws == [ ] then
          if carry != 0 then fail "address overflow" else [ ]
        else
          let
            total = lib.last ws + carry;
          in
          (go (lib.init ws) (total / base)) ++ [ (lib.mod total base) ];
    in
    if n < 0 then fail "negative offset" else addr // { words = go addr.words n; };

  # Number of host bits in a prefix.
  hostBits = c: totalBits c.family - c.prefixLength;

  contains =
    cidr: addr:
    let
      c = if builtins.isString cidr then parseCidr cidr else cidr;
      a = if builtins.isString addr then parse addr else addr;
    in
    c.family == a.family
    && (networkOf (a // { inherit (c) prefixLength; })).words == (networkOf c).words;

  # The `index`-th address of a prefix (index 0 is the network address).
  # Returns the parsed address.
  hostAddress =
    cidr: index:
    let
      c = if builtins.isString cidr then parseCidr cidr else cidr;
    in
    if hostBits c < 62 && index >= pow2 (hostBits c) then
      fail "host index ${toString index} does not fit into ${formatCidr c}"
    else
      addOffset (networkOf c) index;

  # An address as a single-host CIDR (/32 or /128).
  hostCidr = addr: "${format addr}/${toString (totalBits addr.family)}";

  # host[:port] for use as a socket address; brackets IPv6 literals.
  formatEndpoint =
    host: port:
    let
      a = tryParse host;
    in
    if a != null && a.family == 6 then "[${host}]:${toString port}" else "${host}:${toString port}";

  mkTypes =
    let
      checked =
        name: check:
        lib.types.addCheck lib.types.str check
        // {
          inherit name;
          description = name;
        };
      isFam =
        f: s:
        let
          a = tryParse s;
        in
        a != null && a.family == f;
      isCidrFam =
        f: s:
        let
          c = tryParseCidr s;
        in
        c != null && c.family == f;
    in
    {
      ipv4 = checked "IPv4 address" (isFam 4);
      ipv6 = checked "IPv6 address" (isFam 6);
      ip = checked "IP address" (s: tryParse s != null);
      ipv4Cidr = checked "IPv4 CIDR" (isCidrFam 4);
      ipv6Cidr = checked "IPv6 CIDR" (isCidrFam 6);
      cidr = checked "CIDR" (s: tryParseCidr s != null);
    };
in
{
  flake.lib.ip = {
    inherit
      parse
      format
      parseCidr
      formatCidr
      networkOf
      hostBits
      contains
      hostAddress
      hostCidr
      formatEndpoint
      ;
    types = mkTypes;
  };
}
