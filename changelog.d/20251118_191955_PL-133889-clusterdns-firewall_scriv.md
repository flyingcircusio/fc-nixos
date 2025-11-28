<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

<!-- Impact means "when this change is rolled out, there
     might be interruptions/downtimes/required actions/... that
     IMPACT THE RUNNING APPLICATION NEGATIVELY.

     Having new features or changed is not an "impact". That's what
     the main changelog (see below) is for.
     -->

- k3s clusters with custom `clusterDNS`, `podCidr`, `serviceCidr` will fail to evaluate until adapted. See the change description below for details.


### NixOS XX.XX platform

- k3s clusters: options `clusterDns`, `podCidr`, `serviceCidr` are now a list

  affected roles: `k3s-agent`, `k3s-server`, `k3s-single-node`, `webgateway` when in a resource group with k3s nodes (PL-133889)

  The options `clusterDns`, `podCidr`, `serviceCidr` in the namespace `flyingcircus.kubernetes.network` have changed
  from option type *string* to a *list of strings*. This better reflects the ability to specify multiple IP
  address entries and process them at other parts of the configuration. \
  Deployments deviating from the default option value require manual adjustment of the option. The new system
  will fail to evaluate, preventing this release from bein installed automatically until the configuration
  value has been adjusted.
