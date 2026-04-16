{ config, lib }:

with builtins;
with lib;
with config.flyingcircus.roles.mailserver;

let
  dkimSelector =
    domain:
    config.mailserver.dkim.domains.${domain}.selector or config.mailserver.dkim.defaults.selector;
  readDKIM =
    domain:
    let
      path = "/var/dkim/${domain}.${dkimSelector domain}.txt";
    in
    lib.optionalString (pathExists path) (readFile path);
in
''
  ; include the following records in your DNS at appropriate places
  ${mailHost}. A ${smtpBind4}
  ${mailHost}. AAAA ${smtpBind6}
  ; add matching PTR records to reverse zones

''
+ (lib.optionalString (webmailHost != null && webmailHost != mailHost) ''
  ${webmailHost}. CNAME ${mailHost}.
'')
+ (concatStringsSep "\n" (
  map (
    d:
    (
      ''

        ${d}. MX 10 ${mailHost}.
        ${d}. TXT "v=spf1 ip4:${smtpBind4} ip6:${smtpBind6} -all"
        autoconfig.${d}. CNAME ${mailHost}.
        _dmarc.${d}. TXT "v=DMARC1; p=none"
      ''
      + replaceStrings [ "${dkimSelector d}._domainkey" ] [ "${dkimSelector d}._domainkey.${d}." ] (
        readDKIM d
      )
    )
  ) (attrNames (filterAttrs (domain: config: config.enable) domains))
))
