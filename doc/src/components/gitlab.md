# Gitlab { #nixos-gitlab }

Managed instance of [Gitlab](https://gitlab.com/about), an end-to-end code forge, built-in version control, issue tracking, code review, CI/CD, and more.

Gitlab is a complex piece of software which we do not recommend you to approach on your own. We assume that all installations of the Gitlab role are managed by or coordinated with Flyingcircus staff.
Please contact our [support](../support/index.md#support) for deploying a new Gitlab instance.

## Telemetry and user tracking { #nixos-gitlab-tracking }

By default, Gitlab installations send several telemetry data to the upstream vendor. Disabling them requires a **manual opt-out**:

- *Event Tracking*:

  Starting at version 18.0, Gitlab sends pseudonymised [tracking reports of events data](https://about.gitlab.com/blog/2025/03/26/more-granular-product-usage-insights-for-gitlab-self-managed-and-dedicated/). This can be disabled by an administrator:
  - Visit `<yourgitlabdomain>/admin/application_settings/metrics_and_profiling`
  - uncheck *Event tracking -> Enable event tracking*
- *Version Check*:

  Gitlab regularly checks for the availability of new versions at the gitlab.com server. As the Gitlab software is updated as part of the Flyingcircus platform, we recommend disabling that check:
  - Visit `<yourgitlabdomain>/admin/application_settings/metrics_and_profiling`
  - uncheck *Usage statistics -> Enable version check*
- *Service Ping*:

  Gitlab collects [aggregated information about instance metrics and used features](https://handbook.gitlab.com/handbook/legal/privacy/customer-product-usage-information/#service-ping-formerly-known-as-usage-ping). These can be disabled or limited to include fewer information:
  - Visit `<yourgitlabdomain>/admin/application_settings/metrics_and_profiling`
  - uncheck *Usage statistics -> Enable Service Ping* and *Include optional data in Service Ping.*
