{ lib, ... }:

with lib;

{
  # Returns a list of attribute names that appear in more than one attrset.
  # Useful for checking if merging the attrsets would overwrite a previous value.
  #
  # duplicateAttrNames [ { a = 1; } { b = 2; } { a = 3; } ]
  # => [ "a" ]
  duplicateAttrNames =
    listOfAttrs: attrNames (filterAttrs (n: a: a > 1) (foldAttrs (n: acc: acc + 1) 0 listOfAttrs));

  # Applies `builtins.tryEval` to an attrset of derivations, and returns an
  # attrset containing only the successful ones.
  filterSuccessfulEval =
    attrs:
    builtins.mapAttrs (_: val: val.value) (
      lib.filterAttrs (_: val: val.success) (builtins.mapAttrs (_: builtins.tryEval) attrs)
    );
}
