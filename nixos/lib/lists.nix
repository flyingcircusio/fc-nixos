{ lib, ...}:

with lib;

rec {

  # flattens list one layer
  # join :: [[a]] -> [a]
  join = foldl' (x: y: x ++ y) [];

  # last returns the last element of a list or null if the list is empty
  # last :: [a] -> a
  last = foldl' (x: y: y) null;

  # dropLast drops the last lement of a list
  # dropLast :: [a] -> [a]
  dropLast = list: let
    listLength = length list;
    newList = genList (elemAt list) (listLength - 1);
  in newList;

  # dropLastIfEquals drops the last element of a list
  # if it is equals to the first parameter
  # dropLastIfEquals :: Eq a => a -> [a] -> [a]
  dropLastIfEquals = elem: list: let
    lastElement = last list;
  in (if lastElement == elem then dropLast list else list);

  # indentWith prepends a list fo strings with the first parameter
  # indentWith :: String -> [String] -> [String]
  # ```haskell
  # indentWith spaces = map (spaces ++)
  # ```
  indentWith = spaces: map (x: spaces + x);

  # separates a string into list of lines
  # lines :: String -> [String]
  lines = str: lib.trivial.pipe str [
    (splitString "\n") # :: String -> [String]
    (dropLastIfEquals "") # :: [String] -> [String]
  ];

  # concats strings in list with newlines
  # unlines :: [String] -> String
  unlines = concatStringsSep "\n";

}
