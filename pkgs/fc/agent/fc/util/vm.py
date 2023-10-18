def count_cores(cpuinfo="/proc/cpuinfo"):
    count = 0
    with open(cpuinfo) as f:
        for line in f.readlines():
            if line.startswith("processor"):
                count += 1
    assert count > 0
    return count
