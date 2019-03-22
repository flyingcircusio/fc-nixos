===
box
===

----------------------------------------------
Administer Flying Circus NFS box access rights
----------------------------------------------

:Author: Christian Kauhaus <kc@flyingcircus.io>
:Date: 2017-06-16
:Version: @version@
:Manual section: 1
:Manual group: Flying Circus user commands


SYNOPSIS
========

**box grant** { *user* | **public** | **private** } *boxdir* ...


DECRIPTION
==========

**box** is a utility to manage the NFS shared box, usually located at *~/box*.
Specifically, **box grant** manages access rights and allows login users to:

* give away ownership of a box directory to a service user,
* reassert ownership of a box directory and make it either public or private.

In the first case, the contents of a box directory is recursively *chown*'ed to
a service user. Only service users a login user could *sudo* into are allowed.

In the second and third case, **box** changes a directory's ownership back to
the original login user and makes the directory either world-readable or
private.

The *boxdir* is usually a full path to a directory inside the box. As a short
cut, *boxdir* specifications which don't contain a slash refer to directories on
the box' top level.


OPTIONS
=======

grant
   Subcommand for managing access rights inside the box. Currently only this
   command is implemented.

grant *user* *boxdir*
   Recursively **chown(1)** *boxdir* to *user* (giveaway). *user* must be the
   name of a service user for which the calling user has the *sudo-srv*
   privilege.

grant public *boxdir*
   Recursively **chown(1)** *boxdir* back to the calling user and set it
   world-readable.

grant private *boxdir*
   Recursively **chown(1)** *boxdir* back to the calling user and set
   restrictive access rights.

-h
   Show terse usage information.


EXIT STATUS
===========

**box** returns with exit status 0 if the operation has been completed
successfully. Status codes > 0 indicate error conditions and are inspired by the
values defined in *sysexits.h*.


FILES
=====

~/box
   Default per-user mount point for the box.


EXAMPLE
=======

Consider we have a database dump in the directory *~/box/dbdump*. The command ::

   box grant svc1 dbdump

gives the files in this directory away to the service user "svc1". After a
database restore operation has been completed, the command ::

   box grant private dbdump

reasserts ownership back to the calling (human) user.


SEE ALSO
========

**chmod(1)**, **chown(1)**, **sudo(1)**


.. vim: set spell spelllang=en:
