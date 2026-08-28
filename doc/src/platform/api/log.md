---
global_sync_id: "v1"
---

# Log

You can access a log of all calls made to the API for a project by
visiting [your API page](https://my.flyingcircus.io/api/tokens) and selecting
the `Log` utility for a project:

![](../../images/apilog_choose.png)

The log shows all calls (successful or not) including their parameters
and results (or errors) and keeps them for 30 days.

Long results are folded by default. They are marked with an `(expand)` badge
and can be clicked to show them completely:

![](../../images/apilog_folded.png)

![](../../images/apilog_expanded.png)

!!! note
    The log itself is also available throug the API.
    See the [log() method](methods.md#log-method).

