# 3. Physical machine and rack information visibility

Date: 2026-08-31

## Status

Accepted

## Context

We are starting to show more physical machine information in the customer UI and also need to show information about racks.

Some racks are owned by customers fully, whereas other racks may contain our own infrastructure together with individual customer-owned machines. Also, customers may place machines from different resource groups in the same rack.

## Decision

Racks will be associated with 'owning' resource groups. Having access to that resource group shows all information about that rack and all machines an overview from a rack-specific perspective.

If a user has only access to individual machines that belong to other resource groups the rack overview will not be visible.

We provide a separate physical machine overview which will provide different information in a tabular manner, not from a rack perspective. This information is provided based on the same permissions as virtual machine visibility.

## Consequences

Customers with only individual machines do not get any information about the rack aside from the machine's physical location given as rack ID and rack units.

Sharing racks between multiple infrastructure resource groups is not covered. This would likely lead to more complication in the future, e.g. how to show power consumption, etc. that might only available on a per-rack basis. Having "virtual racks" is out of scope for now.
