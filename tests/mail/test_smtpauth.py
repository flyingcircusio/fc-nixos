#!/usr/bin/env python3

import smtplib
import uuid

# Mail server is expected to reject mail relaying
with smtplib.SMTP('mail.example.local') as m:
    m.set_debuglevel(1)
    m.ehlo()
    m.starttls()
    try:
        msgid = '{}@client.example.local'.format(uuid.uuid1())
        m.sendmail('user1@example.local', ['user4@external.local'], """\
To: user4@external.local
Message-Id: f{msgid}
Subject: testmail6

Test
""")
        assert False, "Expected 'Relay access denied' but got success"
    except smtplib.SMTPRecipientsRefused:
        pass

# Mail server is expected to forward mail
with smtplib.SMTP('mail.example.local', 587) as m:
    m.set_debuglevel(1)
    m.ehlo()
    m.starttls()
    m.login('user1@example.local', 'User1User1')
    m.sendmail('user1@example.local', ['user5@external.local'], """\
To: user5@external.local
Subject: testmail7

Test
""")
