{ config, lib }:

with builtins;
with config.flyingcircus.roles.mailserver;

let
  readDKIM =
    domain:
    let path = "/var/dkim/${domain}.mail.txt";
    in lib.optionalString (pathExists path) (readFile path);
in
''
  ; include the following records in your DNS at appropriate places
  ${mailHost}. A ${smtpBind4}
  ${mailHost}. AAAA ${smtpBind6}
  ; add matching PTR records to reverse zones

'' +
(lib.optionalString
  (webmailHost != null && webmailHost != mailHost)
  ''
    ${webmailHost}. CNAME ${mailHost}.
  '') +
(concatStringsSep "\n" (map (d: (
  ''

    ${d}. MX 10 ${mailHost}.
    ${d}. TXT "v=spf1 ip4:${smtpBind4} ip6:${smtpBind6} -all"
    autoconfig.${d}. CNAME ${mailHost}.
    _dmarc.${d}. TXT "v=DMARC1; p=none"
  '' + replaceStrings ["mail._domainkey"] ["mail._domainkey.${d}."] (readDKIM d)
)) domains))
