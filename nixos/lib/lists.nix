{ lib, ... }: {
  # indentWith prepends a list fo strings with the first parameter
  # indentWith :: String -> [String] -> [String]
  # ```haskell
  # indentWith spaces = map (spaces ++)
  # ```
  indentWith = spaces: map (x: spaces + x);
}
