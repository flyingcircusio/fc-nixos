#!/usr/bin/env python3

import imaplib


def verify(user, password, exp_subjects):
    exp_subjects.sort()
    with imaplib.IMAP4('mail.example.local') as m:
        m.starttls()
        m.login(user, password)
        m.select()
        msgs = m.sort('(SUBJECT)', 'UTF-8', 'ALL')[1][0].decode()
        msgs = msgs.split()
        print(msgs)
        assert len(msgs) == len(exp_subjects)
        for (i, subject) in enumerate(exp_subjects):
            msg = m.fetch(msgs[i], 'BODY[HEADER]')[1][0][1].decode()
            print(msg)
            assert f'Subject: {subject}' in msg


verify('user1@example.local', 'User1User1', ['testmail1', 'testmail3'])
verify('user2@example.local', 'User2User2',
       ['testmail2', 'testmail4', 'testmail5'])
