{ lib, ... }:

{
  # Returns a list of attribute names that appear in more than one attrset.
  # Useful for checking if merging the attrsets would overwrite a previous value.
  #
  # duplicateAttrNames [ { a = 1; } { b = 2; } { a = 3; } ]
  # => [ "a" ]
  duplicateAttrNames =
    listOfAttrs:
    lib.attrNames (lib.filterAttrs (n: a: a > 1) (lib.foldAttrs (n: acc: acc + 1) 0 listOfAttrs));

  # Applies `builtins.tryEval` to an attrset of derivations, and returns an
  # attrset containing only the successful ones.
  filterSuccessfulEval =
    attrs:
    builtins.mapAttrs (_: val: val.value) (
      lib.filterAttrs (_: val: val.success) (builtins.mapAttrs (_: builtins.tryEval) attrs)
    );
}
