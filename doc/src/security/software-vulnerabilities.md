---
global_sync_id: "v1"
---

% last review: 2026-05-07

% review schedule: 1 year

% ISMSControl: A.12.6.1
% ISMSControl: A.8.8

# Software vulnerabilities

Security issues with system software installed on machines mainly rely on the
NixOS security process for mitigations. 

When mitigating a vulnerability we may choose different strategies depending
on the situation:

- Ideally we will update the package to an unaffected version that stays API
  compatible.
- We may update to a package with API incompatibility but will help our customers
  to fix breakage.
- We may stay on the existing version and include a patch provided by the
  vendor, security researchers, other distributions or other sources we
  deem trustworthy after a review.
- We may contain the effect of the vulnerability by disabling features, adjusting
  configuration, firewalling or other measures.
- We may choose to ignore the security vulnerability if the impact or attack
  vectors are not relevant on our platform.
- We might take other actions not listed here, depending on the situation.

## NixOS 26.11 (upcoming)

This is the currently actively developed unstable NixOS release that receives timely
security updates.

We update our platform frequently to follow upstream development.

## NixOS 26.05 (current)

This NixOS release is currently actively maintained and receives timely security update.

We update our platform with security updates every week, but may update
intermittently if high risk vulnerabilities become known.

## NixOS 25.11 (old stable)

This NixOS release is currently actively maintained and receives timely security update.

We update our platform with security updates every week, but may update
intermittently if high risk vulnerabilities become known.

## NixOS 25.05 and older (unsupported)

No security updates are provided. Customers are advised to update to NixOS 25.05 or 25.11
to receive security updates.

## Gentoo (retired)

We do not provide security updates for this platform any longer. Customers
have been informed about the sunsetting of Gentoo since 2018.
