def ceph_live_setup():
    # This is a convergent setup and DOES NOT clean up after itself
    # in nixos tests this will happen during every test anyway, due to the
    # temporary nature of the VMs.
    # For the batou-based development environments
    root = Path("/ceph")
    if root.exists():
        # XXX This could be improved to make things more convergent.
        return
    root.mkdir()

    journal_disk = root / "disk-journal"
    journal_loopback = setup_loopback_device(journal_disk, 4 * GiB)

    osd_disk = root / "disk-osd"
    osd_loopback = setup_loopback_device(osd_disk, 4 * GiB)

    env = os.environ.copy()
    del env["PYTHONPATH"]
    env.pop("CEPH_ARGS", None)

    def call(cmd):
        print(f"$ {cmd}")
        check_call(cmd, env=env, shell=True)

    call(f"fc-ceph osd prepare-journal {journal_loopback}")
    call("fc-ceph mon create --no-encrypt --size 500m --bootstrap-cluster")

    # Give the monitor a chance to come up, otherwise the next commands have a high chance
    # of getting stuck.
    counter = 0
    while (
        subprocess.run(
            ["ceph", "-s", "--connect-timeout", "1"], env=env
        ).returncode
        == 1
    ):
        if counter >= 10:
            raise RuntimeError()
        counter += 1
        print(
            subprocess.getoutput(["tail", "/var/log/ceph/ceph-mon.host1.log"])
        )

    call(
        "fc-ceph keys mon-update-single-client host1 ceph_osd,ceph_mon,kvm_host salt-for-host-dhkasjy9"
    )
    call(
        "fc-ceph keys mon-update-single-client host2 kvm_host salt-for-host-dhkasjy9"
    )
    call("fc-ceph mgr create --no-encrypt --size 500m")
    call(f"fc-ceph osd create-bluestore --no-encrypt {osd_loopback}")
    call("ceph osd crush move host1 root=default")
    call("ceph osd pool create rbd 32")
    call("ceph osd pool set rbd size 1")
    call("ceph osd pool set rbd min_size 1")
    call("ceph osd pool create rbd.ssd 32")
    call("ceph osd pool set rbd.ssd size 1")
    call("ceph osd pool set rbd.ssd min_size 1")
    call("ceph osd pool create rbd.hdd 32")
    call("ceph osd pool set rbd.hdd size 1")
    call("ceph osd pool set rbd.hdd min_size 1")
    call("ceph osd lspools")
    call("rbd pool init rbd.ssd")
    call("rbd pool init rbd.hdd")
    call("rbd create --size 500 rbd.hdd/fc-21.05-dev")
    call("rbd map rbd.hdd/fc-21.05-dev")
    call("sgdisk /dev/rbd0 -o -a 2048 -n 1:8192:0 -c 1:ROOT -t 1:8300")
    call("partprobe")
    call("mkfs.xfs /dev/rbd0p1")
    call("rbd unmap /dev/rbd0")
    call("rbd snap create rbd.hdd/fc-21.05-dev@v1")
    call("rbd snap protect rbd.hdd/fc-21.05-dev@v1")
    call("rbd create -s 1M rbd/.maintenance")
