# generic arithmetic functions not included in Nix core
{ lib, ... }:

with builtins;

rec {

  # funny that the modulo function seems not to be defined anywhere
  mod = x : n : x - (div x n) * n;

  # convert value [0..15] into a single hex digit
  hexDigit = x : elemAt (lib.stringToCharacters "0123456789abcdef") x;

  # convert value [0..255] into two hex digits
  byteToHex = x : lib.concatStrings [
    (hexDigit (div x 16)) (hexDigit (mod x 16))
  ];

  # convert *positive* integer into hex string
  toHex' = i:
    if i == 0 then "" else (toHex' (div i 16)) + (hexDigit (mod i 16));

  # convert arbitrary int into hex string
  toHex = i:
    if i == 0 then "0" else
    if i < 0 then "-" + toHex' (-i)
    else toHex' i;

  min = list: head (sort lessThan list);
  max = list: lib.last (sort lessThan list);

  # Taken from
  # https://github.com/NixOS/nixpkgs/issues/41251
  pow = n : i :
            if i == 1 then n
            else if i == 0 then 1
            else n * pow n (i - 1);

}
