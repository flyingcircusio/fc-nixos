# Helpers for NixOS modules and options.

{ lib, ... }:
{
  #
  # Should be used together with obsoleteOptionWarning for an option
  # that doesn't have an effect anymore but should not fail if still used.
  mkObsoleteOption = replacementInstructions:
    lib.mkOption {
      description = "Obsolete option: ${replacementInstructions}";
    };


  # Warns that an option should not be used anymore and has no effect.
  # Returns a warning (a list of strings) to be added to config.warnings.
  # Should be used together with mkObsoleteOption to declare the option.
  # Example:
  #  warnings =
  #   fclib.obsoleteOptionWarning options ["flyingcircus" "x"] "Use y instead."
  obsoleteOptionWarning = options: optionName: replacementInstructions:
    with lib.options;
    let opt = lib.getAttrFromPath optionName options; in
    lib.mkIf (opt.isDefined) [
      ("The option definition `${showOption optionName}' in ${showFiles opt.files} "
        + "no longer has any effect; please remove it. ${replacementInstructions}")
    ];
}
