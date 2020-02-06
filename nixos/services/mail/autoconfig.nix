{ pkgs, lib, domain, mailHost, webmailHost }:

with builtins;

# https://developer.mozilla.org/en-US/docs/Mozilla/Thunderbird/Autoconfiguration/FileFormat/HowTo
pkgs.writeTextFile {
  name = "mozilla-mail-config-v1.1.xml";
  text = ''
    <clientConfig version="1.1">
      <emailProvider id="kauhaus.de">
        <domain>${domain}</domain>
        <displayName>${domain}</displayName>
        <displayShortName>${head (lib.splitString "." domain)}</displayShortName>
        <incomingServer type="imap">
          <hostname>${mailHost}</hostname>
          <port>143</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>${mailHost}</hostname>
          <port>587</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
      </emailProvider>
    ${lib.optionalString (webmailHost != null) ''
    ${"  "}<webMail>
        <loginPage url="https://${webmailHost}/" />
      </webMail>''}
    </clientConfig>
  '';
}
