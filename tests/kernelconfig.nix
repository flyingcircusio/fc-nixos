import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:

let
    # Those are configured in base nixos and we want to ensure
    # the do not get lost.
    additionalExpectedConfig =
        ''
        BLK_DEV_DM m
        BLK_DEV_INTEGRITY y
        BLK_DEV_LOOP m
        BLK_DEV_NBD m
        BLK_DEV_NVME m
        BLK_DEV_RBD m
        BNX2 m
        BONDING m
        BRIDGE m
        BRIDGE_IGMP_SNOOPING y
        COMPACTION y
        CONFIGFS_FS m
        CPU_FREQ_GOV_ONDEMAND m
        CPU_FREQ_GOV_CONSERVATIVE m
        CPU_FREQ_GOV_PERFORMANCE y
        CPU_FREQ_GOV_POWERSAVE m
        CRYPTO_AES_NI_INTEL m
        CRYPTO_CRC32C_INTEL m
        CRYPTO_SHA256 y
        CRYPTO_SHA512 m
        DEBUG_FS y
        DEFAULT_SECURITY_APPARMOR y
        DM_CRYPT m
        DM_MIRROR m
        DM_MULTIPATH m
        DM_SNAPSHOT m
        DM_THIN_PROVISIONING m
        DM_ZERO m
        DMIID y
        E1000 m
        E1000E m
        EXT4_FS m
        EXT4_FS_POSIX_ACL y
        FTRACE_SYSCALLS y
        FUNCTION_GRAPH_TRACER y
        FUNCTION_PROFILER y
        FUNCTION_TRACER y
        FUSE_FS m
        FUSION y
        FUSION_CTL m
        FUSION_SAS m
        HANGCHECK_TIMER m
        HW_RANDOM_INTEL m
        HW_RANDOM_TIMERIOMEM m
        I40E m
        I40EVF m
        IGB m
        IKCONFIG y
        IKCONFIG_PROC y
        INET_DIAG m
        INET_UDP_DIAG m
        INTEL_IDLE y
        INTEL_IOATDMA m
        INTEL_IOMMU_DEFAULT_ON n
        IP_ADVANCED_ROUTER y
        IP_MULTICAST y
        IP_MULTIPLE_TABLES y
        IPMI_DEVICE_INTERFACE m
        IPMI_HANDLER m
        IPMI_POWEROFF m
        IPMI_SI m
        IPMI_WATCHDOG m
        IPV6 y
        IPV6_MULTIPLE_TABLES y
        IRQ_REMAP y
        IXGBE m
        IXGBE_DCA y
        IXGBE_HWMON y
        IXGBEVF m
        KPROBES y
        KVM m
        KVM_AMD m
        KVM_INTEL m
        MD y
        MD_MULTIPATH m
        MD_RAID0 m
        MD_RAID1 m
        MD_RAID456 m
        MEGARAID_MAILBOX m
        MEGARAID_MM m
        MEGARAID_NEWGEN y
        MEGARAID_SAS m
        MICROCODE y
        MICROCODE_INTEL y
        MLX5_CORE m
        MLX5_CORE_EN y
        MLX5_EN_ARFS y
        MLX5_EN_RXNFC y
        MLX5_MPFS y
        NET_IPGRE m
        NET_IPGRE_DEMUX m
        NET_IPIP m
        NET_SCH_CODEL m
        NET_SCH_FQ m
        NET_SCH_FQ_CODEL m
        NET_SCH_PRIO m
        NETFILTER_ADVANCED y
        NETFILTER_XT_MATCH_HASHLIMIT m
        NETFILTER_XT_MATCH_IPRANGE m
        NETFILTER_XT_MATCH_LIMIT m
        NETFILTER_XT_MATCH_MARK m
        NETFILTER_XT_MATCH_MULTIPORT m
        NETFILTER_XT_MATCH_OWNER m
        NETFILTER_XT_MATCH_TCPMSS m
        NETWORK_FILESYSTEMS y
        NF_CONNTRACK m
        NFSD m
        NFSD_V4 y
        NR_CPUS 384
        OPENVSWITCH m
        PACKET_DIAG m
        PAGE_POOL y
        RAID_ATTRS m
        RELAY y
        SCSI_DH_RDAC m
        SCSI_LOWLEVEL y
        SCSI_MPT3SAS m
        SCSI_SAS_ATA y
        SCSI_SAS_ATTRS m
        SCSI_SAS_LIBSAS m
        SECURITY_APPARMOR y
        SOFT_WATCHDOG m
        TCP_CONG_BBR m
        TCP_CONG_BIC m
        TCP_CONG_HTCP m
        TCP_CONG_ILLINOIS m
        TCP_CONG_VEGAS m
        TCP_CONG_WESTWOOD m
        TCP_CONG_YEAH m
        TRANSPARENT_HUGEPAGE y
        TUN m
        UNIX_DIAG m
        USB_EHCI_HCD m
        USB_SERIAL m
        USB_SERIAL_FTDI_SIO m
        USB_SERIAL_PL2303 m
        USB_UHCI_HCD m
        USB_XHCI_HCD m
        VHOST_NET m
        VLAN_8021Q m
        VXLAN m
        WATCHDOG y
        X86_ACPI_CPUFREQ m
        X86_PCC_CPUFREQ m
        XFS_FS m
        '';
in
 rec {
  name = "kernel-config";
  machine =
    { config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
    };

  testScript = let
    in
      { nodes, ... }:
    ''
    def parseConfigDef(cfg):
        cfg = cfg.split('\n')
        opts = {}
        for line in cfg:
            if line.startswith('#'):
                line = line[1:]
            line = line.strip()
            if not line:
                continue
            key, value = line.split(" ", maxsplit=1)
            opts[key] = value
        return cfg, opts

    def parseConfigFinal(cfg):
        cfg = cfg.split('\n')
        opts = {}
        for line in cfg:
            if not 'CONFIG_' in line:
                continue
            if line.startswith('#'):
                line = line[1:]
            line = line.strip()
            if not line:
                continue
            line = line.replace('CONFIG_', "", 1)
            if 'is not set' in line:
                key = line.split(' ', maxsplit=1)[0]
                value = 'n'
            else:
                key, value = line.split("=", maxsplit=1)
            opts[key] = value
        return cfg, opts

    expectedRaw, expectedConfig = parseConfigDef("""${toString nodes.machine.config.flyingcircus.kernelOptions}\n${additionalExpectedConfig}""")

    duplicateOptions = []
    # Ensure the expected config has no double entries
    expectedSeen = set()
    for line in expectedConfig:
        option = line.split()[0]
        if option in expectedSeen:
            print('Duplicate option:', line)
            duplicateOptions.append(option)
        expectedSeen.add(option)
    if duplicateOptions:
        raise ValueError('{} duplicate expected options'.format(len(duplicateOptions)))

    _, foundConfig = machine.execute("zcat /proc/config.gz")
    foundRaw, foundConfig = parseConfigFinal(foundConfig)

    print()
    missingOptions = []
    for key in expectedConfig:
        if key not in foundConfig:
            print('Missing: ', key)
            missingOptions.append(key)
        elif foundConfig[key] != expectedConfig[key]:
            print('{} expected {} but found {}'.format(
                key, expectedConfig[key], foundConfig[key]))
            missingOptions.append(key)
    if missingOptions:
        raise ValueError('{} wrong config options'.format(len(missingOptions)))
  '';
})
