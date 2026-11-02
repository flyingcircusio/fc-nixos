### Impact

- The k3s systemd unit on k3s servers and single nodes will be restarted. Applications in the cluster will continue running but routing and any tasks that require access to the kubernetes API will be impacted. If you rely on nodeport type services binding to srv or fe interfaces we recommend you set up a reverse proxy instead.


### NixOS XX.XX platform

- Limit the addresses that k3s nodeport type services bind to to localhost (v4 and v6). Nodeport type services will not bind to the fe or srv interfaces anymore. (PL-135804)
