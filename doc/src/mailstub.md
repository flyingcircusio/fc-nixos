(nixos-mailstub)=

# Mail stub

The `mailstub` role provides a minimal Postfix which is mostly usable to locally collect and queue mails to hand them off to another mail server for actual delivery (relay). Sending email directly will not work well due to spam protection measures on the receiving side. Notably the mail stub does not configure DKIM signing – use {ref}`nixos-mailserver`.

## Configuring as relay

This is an example configuration to collect mails locally and send them all to smtp.example.com:

{file}`/etc/local/postfix/main.cf`
```
relayhost = [smtp.example.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/local/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_use_tls = yes
```

{file}`/etc/local/postfix/sasl_passwd`
```
[smtp.example.com]:587 smtp_username:smtp_password
```

Run in `/etc/local/postfix`
```
postmap sasl_passwd
```

Run `sudo fc-manage switch` to activate.
