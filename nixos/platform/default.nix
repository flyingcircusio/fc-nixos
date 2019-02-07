{ lib, config, ... }:

with lib;
{

  # make the image smaller
  environment.noXlibs = mkDefault true;
  sound.enable = mkDefault false;
  documentation.enable = mkDefault false;
  services.nixosManual.enable = mkDefault false;

  # This isn't perfect, but let's expect the user specifies an UTF-8 defaultLocale
  i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

  system.stateVersion = mkDefault "18.09";

}
