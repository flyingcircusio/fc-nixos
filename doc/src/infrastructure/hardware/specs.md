---
global_sync_id: "v1"
Publish Date: '2013-06-13'
---

% last review: 2026-03-10

% review schedule: 1 year


# Hardware specifications { #hardware-specs }

All hardware we procure for our infrastructure will comply to the following
specifications. Older hardware may have been bought adhering to former
versions of the specification and will be upgraded over time and as necessary.

Housing customers' equipment also needs to comply to the specification valid
at the time of installation.

## Servers

All servers, independently of their role, require:

- 1 1G network port onboard with shared IPMI and PXE boot functionality
- 2 25G network ports with VXLAN offloading (Nvidia Connect X-4 or newer)
- Support for UEFI boot
- OS disks: 1 SSD M.2 internal, >= 240 GiB
- CPU-Architecture: x86_64, preferably AMD
- BMC supporting IPMI 2.0 with serial console via LAN on shared port
- Redundant power supply
- Sliding rack rails

Historic requirements, usually always given nowadways:

- Needs to be bootable from USB flash drive
- PCIe bus

### Application servers

- Chassis: 2 rack units
- at least 768 GiB RAM
- at least 2x28 Core CPU at affordable speeds
- Microarchitecture: at least Zen 3 (Milan)
- Machine name: kyleXX

### Storage servers

- Base: 2 rack units
- 24 slots for U.2/U.3 NVMe drives
- at least 1x24 cores with sufficient single-thread performance (3GHz+)
- 256 GiB RAM
- Drives: 15 TiB NVMe, e.g. Micron 7450 Pro
- code name: cartmanXY

### Backup servers

- Base: 2 rack units
- 24 slots for U.2/U.3 NVMe drives
- at least 1x16 cores
- 96 GiB RAM
- Drives: 15 TiB NVMe, e.g. Micron 7450 Pro, Kioxia and Solidigm are valid, too.
- code name: barbradyXY

### Routers

- Base: 2 rack units
- 3-4 PCIe slots for additional network cards
- at least 16 GiB RAM
- at least 1x8 cores, potentially power saving options
- code name: kennyXY

## Network infrastructure

### Switches

- Recommended model: Nokia 7220 IXR D2L
- 48 Ports
- code name: stanXY

### Cabling

- LC-Duplex OS2
- Use patchboxes for clean cable management
