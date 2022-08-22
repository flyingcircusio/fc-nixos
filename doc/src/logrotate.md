(nixos-logrotate)=

# Logrotate

To rotate log files that are growing in service user directories, drop custom
{file}`logrotate.conf` snippets into {file}`/etc/local/logrotate/{USER}`. This
service is automatically enabled for all service users.

:::{note}
If you store multiple files into this folders, **all** files
will be activated.
:::

Default options will be applied and are continuously documented in
{file}`/etc/local/logrotate/README.txt`.

For details about logrotate, check the [logrotate project](https://github.com/logrotate/logrotate) and it's documentation.

Here's an example for a simple rotation signalling the owning process to
re-open its file:

```text
/srv/s-test/logs/*.log {
    rotate 5
    weekly

    postrotate
        kill -USR2 $(/srv/s-test/deployment/work/supervisor/bin/supervisorctl pid)
    endscript
}
```
