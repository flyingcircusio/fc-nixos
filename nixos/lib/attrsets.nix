{ lib, ...}:

with lib;

rec {
  # Returns a list of attribute names that appear in more than one attrset.
  # Useful for checking if merging the attrsets would overwrite a previous value.
  #
  # duplicateAttrNames [ { a = 1; } { b = 2; } { a = 3; } ]
  # => [ "a" ]
  duplicateAttrNames = listOfAttrs:
    attrNames
      (filterAttrs
        (n: a: a > 1)
        (foldAttrs
          (n: acc: acc + 1)
          0
          listOfAttrs));
}
