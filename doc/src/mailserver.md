(nixos-mailserver)=

# Mail server

The role `mailserver` installs a complete mail server for incoming and outgoing mail.
Incoming mail is either delivered to IMAP mailboxes via dovecot, or forwarded to
an application via alias/transport configs. Outgoing mail is accepted on the
submission port or via a *sendmail* executable.

An optional web mail UI is included. This role also includes state-of-the-art
spam control.

User accounts can be created/modified dynamically. There is, however, no default
mechanism for user management besides text files.

```{contents}
```

## Which components are included?

The main ingredients of this role are [Postfix] for mail delivery, [Dovecot] as
IMAP access server, and [Roundcube] as web frontend.
{ref}`nixos-postgresql-server` is used as database for Roundcube settings.

We rely mainly on [rspamd] for spam protection. To get outgoing mails
delivered, they are signed with[OpenDKIM] and a basic [SPF] and [SRS] setup
is included.

Additionally, a Thunderbird-compatible client[autoconfiguration] XML file is
provided which helps many clients to configure themselves properly.

(nixos-mailserver-basic-setup)=

## How do I perform a basic setup?

:::{warning}
We strongly recommend putting the `mailserver` role on a separate
VM without other roles (`postgresql` being the only exception). The role
has many moving parts which could interfere with roles and applications.
:::

First, you need public IPv4 and IPv6 addresses for your mail server's frontend
interface. Contact {ref}`support` if you don't have. Then, pick a mail host name
which will be advertised as MX name on your mail domain. This host name (called
**mailHost** from here on) must resolve to the FE addresses with both forward
and reverse lookups.

Additionally, some mail providers (namely \[Telekom/T-Online\]
(<https://postmaster.t-online.de/#t4.1>)) may require that your mailserver
has an imprint served at its hostname.

For this you can either set `imprintUrl` to the location of your existing
imprint, or use `imprintText` to specify an imprint in HTML format

Note that it is not possible to set both `imprintUrl` and `imprintText` at the
same time and imprint cannot be used if you serve webmail under the
`mailHost` (meaning `mailHost` and `webmailHost` cannot be the same).

:::{warning}
Incorrect DNS setup is the most frequent source of delivery problems. Let our
{ref}`support` check your setup if in doubt.
:::

If you choose to use the Roundcube webmail UI by adding the `webmailHost`
setting, like in the example, make sure to enable a `postgresql` role on the
machine because Roundcube needs it to store settings. Just use the newest
version that is available at the moment.

Create a configuration file {file}`/etc/local/mail/config.json` which contains
all the basic pieces. In the following example, the server's mailHost is
*mail.test.fcio.net* and it serves as MX for the mail domains *test.fcio.net*
and *test2.fcio.net*:

```
{
  "mailHost": "mail.test.fcio.net",
  "webmailHost": "webmail.test.fcio.net",
  "domains": {
    "test.fcio.net": {
      "primary": true
    },
    "test2.fcio.net": {
      "autoconfig": false
    }
  },
  "imprintUrl": "your-company.tld/imprint"
}
```

:::{note}
There must always be exactly one domain with the primary option set.
:::

This sets up [autoconfiguration] for mail clients that wish to use *test.fcio.net*.
Autoconfiguration is disabled for *test2.fcio.net* in the example.

Run {command}`sudo fc-manage -b` to have everything configured on the system.

Afterwards, a generated file {file}`/etc/local/mail/dns.zone` contains all
necessary DNS settings for your mail server. Insert the records found in this
file into the appropriate DNS zones and don't forget to check reverses.

## How do I create users?

Edit {file}`/etc/local/mail/users.json` to add user accounts. Example:

```
{
  "user1@test.fcio.net": {
    "aliases": ["first.last@test.fcio.net"],
    "hashedPassword": "$5$NTTg86onSoM1MK$Xir/pTc9G/TLM1LResKlyAip1oO9XcsmUKXaf7ALIS2",
    "quota": "4G",
    "sieveScript": null
  }
}
```

This file contains of key/value pairs where the key is the main email address
and the value is a attribute set of configuration options. Domain
parts of all e-mail addresses must be listed in the `domains` option in
{file}`/etc/local/mail/config.json`.

The password must be hashed with {command}`mkpasswd -m sha-256 {PASSWORD}`.

## How do mail users log into the mail server?

- Username: full e-mail address
- Incoming: IMAP with STARTTLS, mailHost port 143
- Outgoing: SMTP with STARTTLS, mailHost port 587.

If the *webmailHost* option is defined, users can log into the web frontend with
their full e-mail address and password.

## How to change passwords

We support two scenarios: static passwords and dynamic passwords.

### Static passwords

Passwords are set by the administrator and put into users.json. They cannot be
changed by users.

### Dynamic passwords

To enable users to change their password themselves, leave the
**hashedPassword** option in {file}`/etc/local/mail/users.json` empty and set
the initial password in {file}`/var/lib/dovecot/passwd` instead. This file
consists of a e-mail address/password pair per user. Example:

```
user1@test.fcio.net:$5$NwBmrzj2vPlIdoa0$Go0zrVY5ZQncFXlCAxA.Gqj.e4Ym6Ic242O6Mj3BK1
```

The initial password hash can be created with {command}`mkpasswd -m sha-256
{PASSWORD}` as shown above. Afterwards, user can log into the Roundcube web mail
frontend and change their password in the settings menu.

## The spam filter misclassifies mails. What to do?

rspamd has a good set of defaults but is not perfect. To get be results, it must
receive training.

False positive (ham classified as spam)

: Move that e-mail message from the `Junk` folder back into the `INBOX` folder.

False negative (spam classified as ham)

: Move that e-mail message from the `INBOX` folder into the `Junk` folder.

In both cases, the spam filter's statistics module will be automatically
trained. Note that the spam filter needs a certain amount of training material
to become effective. This means that training effects will show up after time
and not immediately.

(mail-into-backends)=

## How do I forward mails to remote addresses?

Declare a [virtual alias] map and create remote aliases there. Add the
following snippet to config.json:

```
"dynamicMaps": {
  "virtual_alias_maps": ["/etc/local/mail/virtual_aliases"]
}
```

Create {file}`/etc/local/mail/virtual_aliases`. Example contents:

```
alias@test.fcio.net remote@address
```

Invoke {command}`sudo systemctl reload postfix` to recompile maps after map
contents has been changed. Invoke {command}`sudo fc-manage --build` as usual if
the contents of config.json has been changed.

## How do I feed mails into an application?

Feeding mails destined to special accounts into backend application servers can
be done with a [transport] map. Transport and other Postfix lookup tables are
declared inside a `dynamicMaps` key in config.json. The application should open a
port capable of speaking SMTP on its srv interface. Example:

```
"dynamicMaps": {
  "transport_maps": [ "/etc/local/mail/transport" ]
}
```

Example transport file contents:

```
specialaddress@test.fcio.net relay:172.30.40.50:8025
```

In case a whole subdomain should be piped into an application server, we need
both a transport and a [relay_domains] map. Both map declarations may point to
the same source as *relay_domains* uses only the first field of each line.

Example config.json snippet:

```
dynamicMaps": {
  "transport_maps": [ "/etc/local/mail/transport" ],
  "relay_domains": [ "/etc/local/mail/transport" ]
}
```

Example transport file contents:

```
subdomain.test.fcio.net relay:172.30.40.50:8025
```

An DNS MX record for that subdomain must be present as well.

Invoke {command}`sudo systemctl reload postfix` to recompile maps after map
contents has been changed. Invoke {command}`sudo fc-manage --build` as usual if
the contents of config.json has been changed.

## Reference

### DNS Glossary

Some important terminology for understanding DNS issues:

HELO name

: The canonical name of the mail server. The HELO name is the same as the value
  of the **mailHost** option and the **myhostname** Postfix configuration
  variable. The HELO name must be listed in the **MX** records of
  all served *mail domains*.

  Example: mail.test.fcio.net

Frontend IP addresses

: Public IPv4 and/or IPv6 addresses. **A** and **AAAA** queries of the HELO name
  must resolve to the frontend IP addresses. Each address must have a **PTR**
  record which must resolve exactly to the HELO name.

  Example: 195.62.126.119, 2a02:248:101:62::1191

Mail domain

: List of DNS domains that serve as domain part in mail addresses hosted by a
  mail server. Not to be confused with the domain part of the server's FQDN
  which may be the same or may not.  Each *domain* must have a **MX** record
  which points to the mail server's *HELO name*.

  Example: test.fcio.net, test2.fcio.net

### Role options

All options can be set in {file}`/etc/local/mail/config.json`
or in {ref}`Nix config <nixos-custom-modules>` with the prefix *flyingcircus.roles.mailserver*.

Frequently used options:

domains (attribute set (object) or list)

: *mail domains* which should be served by this mail server.
  Keys of the set are the domains, values are options for a specific domain.
  You can find these options below. See {ref}`nixos-mailserver-basic-setup`
  for a working example.

  The option still supports a list of strings instead of a attribute set (object).
  Using a list is deprecated and should be migrated to the attribute set form.

domains.\<domain>.enable (boolean, default true)

: Enable or disable a domain.

domains.\<domain>.autoconfig (boolean, default true)

: [Autoconfiguration] for mail clients is enabled by default.
  A DNS entry must exist for *autoconfig.\<domain>*.
  Sets up a SSL certificate automatically using Let's Encrypt.

domains.\<domain>.primary (boolean)

: Make this the primary domain for internal services (bounce emails, etc).

mailHost

: *HELO name*, see above.

webmailHost

: Virtual server name for the Roundcube web mail service. Appropriate DNS
  entries are expected to point to the VM's frontend address. If this option is
  set, the Roundcube service will be enabled. Make sure that a `postgresql`
  role is enabled when adding this option.

rootAlias

: E-mail address to receive all mails to the local root account.

dynamicMaps

: Hash map of Postfix maps (like [transport]) and one or more file paths
  containing map records. See section {ref}`mail-into-backends` for details.

Specialist options:

redisDatabase

: Database number (0-15) for rspamd. Defaults to 5. The database number can
  be adjusted if any another local application happens to use DB 5.

smtpBind4 and smtpBind6

: Which frontend address to use in case ethfe has several of them.

explicitSmtpBind

: Whether to include explicit smtp_bind_address in the Postfix main.cf file.
  Defaults to true if ethfe has more than one IPv4 or IPv6 address. Needs
  to be overridden only in very special cases.

passwdFile

: Virtual mail users listing in {manpage}`passwd(7)` format. Set this if an
  application generates this file automatically and puts it into an
  application-specific location.

### User options

Keys that can be set per user in {file}`/etc/local/mail/users.json`.

aliases

: List of alternative e-mail addresses that will be delivered into this
  mailbox. Note that domain parts of all aliases must be listed in the *domains*
  option.

catchAll

: List of subdomains for which all incoming mails, regardless of their local
  parts, will be delivered into this mailbox. All subdomains must be listed in
  the *domains* option.

hashedPassword

: Either a salted SHA-256 password hash (for static passwords) or empty string.
  In the latter case, the password is read from {file}`/var/lib/dovecot/passwd`.

quota

: Mailbox space limit like "512M" or "2G".

sieveScript

: Mail processing rules in the [Sieve] language. Users can set dynamic sieve
  scripts from the Roundcube web UI if left empty.

### Further configuration files

/etc/local/mail/local_valiases.json

: Additional aliases which are not mentioned in users.json. Expected to be a
  dict with the alias as key and the receiving address as value.

/etc/local/mail/main.cf

: Additional Postfix {manpage}`postconf(5)` settings.

/etc/local/mail/dns.zone

: Copy-and-paste DNS records for inclusion in zone files. Adapt if necessary.

### Monitoring

Monitoring checks/metrics created by this role:

- Port checks for SMTP, submission, IMAP, and IMAPs.
- Postfix excessive queue length check.
- Postfix queue length, size, and age metrics.

% vim: set spell spelllang=en:

[autoconfiguration]: https://wiki.mozilla.org/Thunderbird:Autoconfiguration
[dovecot]: https://dovecot.org/
[opendkim]: http://www.opendkim.org/
[postfix]: http://www.postfix.org/
[relay_domains]: http://www.postfix.org/postconf.5.html#relay_domains
[roundcube]: https://roundcube.net/
[rspamd]: https://rspamd.com/
[sieve]: https://en.wikipedia.org/wiki/Sieve_(mail_filtering_language)
[spf]: https://en.wikipedia.org/wiki/Sender_Policy_Framework
[srs]: https://github.com/roehling/postsrsd
[transport]: http://www.postfix.org/transport.5.html
[virtual alias]: http://www.postfix.org/postconf.5.html#virtual_alias_maps
