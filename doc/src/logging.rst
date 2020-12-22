.. _nixos2-logging:

Logging
=======

.. image:: images/logging250.png
   :class: logo
   :width: 250px

Creating, storing, and analysing logs from components and your application is
an important part of keeping your service healthy and developing it further.

On the most basic level, our :ref:`managed components <nixos2-components>`
log to the systemd journal or provide regular log files.
Log files are rotated by :ref:`nixos2-logrotate` which can also be configured for
custom log files.

For more advanced use cases, you can choose to use the managed :ref:`loghost
<nixos2-loghost>` component which uses `Graylog <http://www.graylog.org>`_
for centralized log collection.
