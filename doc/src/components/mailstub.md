# Mail stub { #nixos-mailstub }

The `mailstub` role provides a minimal Postfix which is mostly usable to locally collect and queue mails to hand them off to another mail server for actual delivery (relay). Sending email directly will not work well due to spam protection measures on the receiving side. Notably the mail stub does not configure DKIM signing – use [nixos-mailserver](../components/mailserver.md#nixos-mailserver).

Configuring Postfix is possible in NixOS configuration in the `services.postfix` module.

## Configuring as relay

This is an example configuration to collect mails locally and send them all to smtp.example.com:

```nix
services.postfix.settings.main = {
  relayhost = [
    "[smtp.example.com]:587"
  ];
  smtp_sasl_auth_enable = true;
  smtp_sasl_password_maps = "hash:/etc/local/postfix/sasl_passwd";
  smtp_sasl_security_options = "noanonymous";
  smtp_use_tls = true;
};
```

`/etc/local/postfix/sasl_passwd`
```
[smtp.example.com]:587 smtp_username:smtp_password
```

Run in `/etc/local/postfix`
```
postmap sasl_passwd
```

Run `sudo fc-manage switch` to activate.
