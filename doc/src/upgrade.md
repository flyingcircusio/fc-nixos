(nixos-upgrade)=

# Platform Upgrades & What's New

Here you find information about changes compared to the previous platform
version, what to consider and where to take action before upgrading.

:::{note}
Before upgrading a machine, please read the {ref}`nixos-upgrade-general`
and {ref}`nixos-upgrade-breaking`.
Contact our [support](/platform/index.html#support) for upgrade assistance.
:::

(nixos-upgrade-overview)=

## Overview

- New roles:
- Removed roles:
- Roles affected by significant breaking changes:
- Removed significant packages:

## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 26.05 ends on **2026-06-30**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.

## How to upgrade?

To upgrade your machines, the *Environment* to one of the `fc-26.05-…`
values. \
This can be done either via our customer portal, or by setting the platform
version using the API.

(nixos-upgrade-general)=

## General upgrade remarks

Our goal is to make upgrades as smooth as possible without manual intervention
but sometimes incompatible configuration has to be fixed before starting an
upgrade.

Here are some remarks to make sure that an upgrade will run successfully:

### Isolate application deployments

As a general advice: reduce platform dependencies of your application
deployment by using Nix-managed service user environments as described in
{ref}`nixos-user-package-management` or other forms of dependency isolation
like containers.

### Upgrade staging first

Upgrades should always be checked in a staging environment first. We usually
upgrade customer staging machines from our side as soon as the new platform
version is ready for general testing. This is announced via our
[Flying Circus Statuspage](https://status.flyingcircus.io) where you can
also subscribe to updates.

### Upgrade to the next platform version

We strongly advise upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 24.11 platform.
Please refrain from opening support cases for broken upgrade paths from older
platform versions. The resolution is to upgrade one version at a time.

Direct upgrades from older versions are not tested since we cannot
reliably test all combinations for all roles and custom configuration also
plays a role here. Usually, problems that occur when skipping versions are
only temporary, like service failures that go away with the next system
rebuild or a system/service restart.

### Check free disk space

About 8-10 GiB should be available on disk before starting an upgrade to avoid
triggering a low-disk alarm.

Usually, upgrades have an on-disk size of about 3-6 GiB which may be higher in
certain configurations. We keep old system versions and let the Nix garbage
collection clean them up, so the additional space will be used for at least 3
days.

### Consider performance impact while upgrading

Upgrading may take some time, depending on the number of activated roles and
disk speed. For production machines, upgrades are usually done in a
maintenance window to reduce impact on regular operations. A VM may have
degraded performance for some minutes when packages are being downloaded and
built.

With NixOS, the switch to the new system happens after a successful system
build so most services are unavailable at the same time and only for a small
time-window.

(nixos-upgrade-breaking)=

## Significant breaking changes

### Mailserver / Mailstub

Dovecot was updated from 2.3 to 2.4. This update contains a full rewrite of the configuration.
Please read the [dovecot upgrade documentation](https://doc.dovecot.org/2.4.3/installation/upgrade/2.3-to-2.4.html)
for more information about the upgrade.
The NixOS option `services.dovecot2.extraConfig` has been removed.
Configuration for dovecot in NixOS now works via `services.dovecot2.settings`.

Configuring postfix via `services.postfix.extraConfig`, `/etc/local/mail/main.cf`,
`/etc/local/postfix/main.cf` is not allowed anymore.
Please migrate to structured config with `services.postfix.settings.main`.

SMTP with STARTTLS over port 587 (also known as Submission) is deprecated and
scheduled for deactivation in fc-nixos 26.11.
We will provide a migration check that checks for remaining usages of SMTP
over STARTTLS soon. Please already migrate your applications to use SMTP over SSL/TLS via port 465.

(nixos-upgrade-percona)=

### Percona / MySQL

We removed the `percona80` role, as MySQL 8.0 is end-of-life and Percona 8.0 is likely not receiving security updates anymore.

Please upgrade to `percona84` before upgrading.

Percona Server 8.4 now has `caching_sha2_password` as default authentication plugin.
This means that new user passwords are hashed with this mechanism and clients need to support this.
We still support the old hashes up to Percona Server 9.7 when these will be removed.
Please read the [Percona Server Upgrade Guide](https://docs.percona.com/percona-server/8.4/upgrade.html) for more
information about the upgrade.

(nixos-upgrade-slurm)=

### Slurm

This release contains a major version upgrade of Slurm from 25.05.x.x (NixOS 25.11) to 25.11.x.x. Nodes of a cluster
need to be upgraded in a particular order, please consult the [upgrade instructions of the role](#nixos-slurm-upgrade)
for details.

Regarding new features or changes in Slurm itself,
consult [its release notes](https://github.com/SchedMD/slurm/blob/slurm-25-11-1-1/RELEASE_NOTES.md).

### RabbitMQ

Metrics for RabbitMQ are now only provided by the `rabbitmq_prometheus` exporter,
the legacy Telegraf plugin is disabled due to the deprecation of `management_metrics_collection`.

This results in changed metric names. The new metrics are already emitted
since the Flying Circus 25.05 platform release.
Our statshost have a *RabbitMQ-Overview* dashboard available displaying this data.

<details><summary>Removed metric names:</summary>
```
rabbitmq_exchange_messages_publish_in
rabbitmq_exchange_messages_publish_in_rate
rabbitmq_exchange_messages_publish_out
rabbitmq_exchange_messages_publish_out_rate
rabbitmq_node_disk_free
rabbitmq_node_disk_free_alarm
rabbitmq_node_disk_free_limit
rabbitmq_node_fd_total
rabbitmq_node_fd_used
rabbitmq_node_gc_bytes_reclaimed
rabbitmq_node_gc_bytes_reclaimed_rate
rabbitmq_node_gc_num
rabbitmq_node_gc_num_rate
rabbitmq_node_io_read_avg_time
rabbitmq_node_io_read_avg_time_rate
rabbitmq_node_io_read_bytes
rabbitmq_node_io_read_bytes_rate
rabbitmq_node_io_write_avg_time
rabbitmq_node_io_write_avg_time_rate
rabbitmq_node_io_write_bytes
rabbitmq_node_io_write_bytes_rate
rabbitmq_node_mem_alarm
rabbitmq_node_mem_allocated_unused
rabbitmq_node_mem_atom
rabbitmq_node_mem_binary
rabbitmq_node_mem_code
rabbitmq_node_mem_connection_channels
rabbitmq_node_mem_connection_other
rabbitmq_node_mem_connection_readers
rabbitmq_node_mem_connection_writers
rabbitmq_node_mem_limit
rabbitmq_node_mem_metrics
rabbitmq_node_mem_mgmt_db
rabbitmq_node_mem_mnesia
rabbitmq_node_mem_msg_index
rabbitmq_node_mem_other_ets
rabbitmq_node_mem_other_proc
rabbitmq_node_mem_other_system
rabbitmq_node_mem_plugins
rabbitmq_node_mem_queue_procs
rabbitmq_node_mem_queue_slave_procs
rabbitmq_node_mem_reserved_unallocated
rabbitmq_node_mem_total
rabbitmq_node_mem_used
rabbitmq_node_mnesia_disk_tx_count
rabbitmq_node_mnesia_disk_tx_count_rate
rabbitmq_node_mnesia_ram_tx_count
rabbitmq_node_mnesia_ram_tx_count_rate
rabbitmq_node_proc_total
rabbitmq_node_proc_used
rabbitmq_node_run_queue
rabbitmq_node_running
rabbitmq_node_sockets_total
rabbitmq_node_sockets_used
rabbitmq_node_uptime
rabbitmq_overview_amqp_listeners
rabbitmq_overview_channels
rabbitmq_overview_clustering_listeners
rabbitmq_overview_connections
rabbitmq_overview_consumers
rabbitmq_overview_exchanges
rabbitmq_overview_messages
rabbitmq_overview_messages_acked
rabbitmq_overview_messages_delivered
rabbitmq_overview_messages_delivered_get
rabbitmq_overview_messages_published
rabbitmq_overview_messages_ready
rabbitmq_overview_messages_unacked
rabbitmq_overview_queues
rabbitmq_overview_return_unroutable
rabbitmq_overview_return_unroutable_rate
```
</details>

<details><summary>Added metric names:</summary>
```
erlang_vm_allocators
erlang_vm_atom_count
erlang_vm_atom_limit
erlang_vm_dirty_cpu_schedulers
erlang_vm_dirty_cpu_schedulers_online
erlang_vm_dirty_io_schedulers
erlang_vm_ets_limit
erlang_vm_logical_processors
erlang_vm_logical_processors_available
erlang_vm_logical_processors_online
erlang_vm_memory_atom_bytes_total
erlang_vm_memory_bytes_total
erlang_vm_memory_dets_tables
erlang_vm_memory_ets_tables
erlang_vm_memory_processes_bytes_total
erlang_vm_memory_system_bytes_total
erlang_vm_msacc_aux_seconds_total
erlang_vm_msacc_check_io_seconds_total
erlang_vm_msacc_emulator_seconds_total
erlang_vm_msacc_gc_seconds_total
erlang_vm_msacc_other_seconds_total
erlang_vm_msacc_port_seconds_total
erlang_vm_msacc_sleep_seconds_total
erlang_vm_port_count
erlang_vm_port_limit
erlang_vm_process_count
erlang_vm_process_limit
erlang_vm_schedulers
erlang_vm_schedulers_online
erlang_vm_smp_support
erlang_vm_statistics_bytes_output_total
erlang_vm_statistics_bytes_received_total
erlang_vm_statistics_context_switches
erlang_vm_statistics_dirty_cpu_run_queue_length
erlang_vm_statistics_dirty_io_run_queue_length
erlang_vm_statistics_garbage_collection_bytes_reclaimed
erlang_vm_statistics_garbage_collection_number_of_gcs
erlang_vm_statistics_garbage_collection_words_reclaimed
erlang_vm_statistics_reductions_total
erlang_vm_statistics_run_queues_length
erlang_vm_statistics_runtime_milliseconds
erlang_vm_statistics_wallclock_time_milliseconds
erlang_vm_thread_pool_size
erlang_vm_threads
erlang_vm_time_correction
erlang_vm_wordsize_bytes
rabbitmq_alarms_file_descriptor_limit
rabbitmq_alarms_free_disk_space_watermark
rabbitmq_alarms_memory_used_watermark
rabbitmq_auth_attempts_failed_total
rabbitmq_auth_attempts_succeeded_total
rabbitmq_auth_attempts_total
rabbitmq_build_info
rabbitmq_channel_acks_uncommitted
rabbitmq_channel_consumers
rabbitmq_channel_get_ack_total
rabbitmq_channel_get_empty_total
rabbitmq_channel_get_total
rabbitmq_channel_messages_acked_total
rabbitmq_channel_messages_confirmed_total
rabbitmq_channel_messages_delivered_ack_total
rabbitmq_channel_messages_delivered_total
rabbitmq_channel_messages_published_total
rabbitmq_channel_messages_redelivered_total
rabbitmq_channel_messages_unacked
rabbitmq_channel_messages_uncommitted
rabbitmq_channel_messages_unconfirmed
rabbitmq_channel_messages_unroutable_dropped_total
rabbitmq_channel_messages_unroutable_returned_total
rabbitmq_channel_prefetch
rabbitmq_channel_process_reductions_total
rabbitmq_channels
rabbitmq_channels_closed_total
rabbitmq_channels_opened_total
rabbitmq_connection_channels
rabbitmq_connection_incoming_bytes_total
rabbitmq_connection_incoming_packets_total
rabbitmq_connection_outgoing_bytes_total
rabbitmq_connection_outgoing_packets_total
rabbitmq_connection_pending_packets
rabbitmq_connection_process_reductions_total
rabbitmq_connections
rabbitmq_connections_closed_total
rabbitmq_connections_opened_total
rabbitmq_consumer_prefetch
rabbitmq_consumers
rabbitmq_disk_space_available_bytes
rabbitmq_disk_space_available_limit_bytes
rabbitmq_erlang_gc_reclaimed_bytes_total
rabbitmq_erlang_gc_runs_total
rabbitmq_erlang_net_ticktime_seconds
rabbitmq_erlang_processes_limit
rabbitmq_erlang_processes_used
rabbitmq_erlang_scheduler_context_switches_total
rabbitmq_erlang_scheduler_run_queue
rabbitmq_erlang_uptime_seconds
rabbitmq_exchange_messages_confirmed_total
rabbitmq_exchange_messages_published_total
rabbitmq_exchange_messages_unroutable_dropped_total
rabbitmq_exchange_messages_unroutable_returned_total
rabbitmq_global_consumers
rabbitmq_global_messages_acknowledged_total
rabbitmq_global_messages_confirmed_total
rabbitmq_global_messages_dead_lettered_confirmed_total
rabbitmq_global_messages_dead_lettered_delivery_limit_total
rabbitmq_global_messages_dead_lettered_expired_total
rabbitmq_global_messages_dead_lettered_maxlen_total
rabbitmq_global_messages_dead_lettered_rejected_total
rabbitmq_global_messages_delivered_consume_auto_ack_total
rabbitmq_global_messages_delivered_consume_manual_ack_total
rabbitmq_global_messages_delivered_get_auto_ack_total
rabbitmq_global_messages_delivered_get_manual_ack_total
rabbitmq_global_messages_delivered_total
rabbitmq_global_messages_get_empty_total
rabbitmq_global_messages_received_confirm_total
rabbitmq_global_messages_received_total
rabbitmq_global_messages_redelivered_total
rabbitmq_global_messages_routed_total
rabbitmq_global_messages_unroutable_dropped_total
rabbitmq_global_messages_unroutable_returned_total
rabbitmq_global_publishers
rabbitmq_identity_info
rabbitmq_io_read_bytes_total
rabbitmq_io_read_ops_total
rabbitmq_io_read_time_seconds_total
rabbitmq_io_reopen_ops_total
rabbitmq_io_seek_ops_total
rabbitmq_io_seek_time_seconds_total
rabbitmq_io_sync_ops_total
rabbitmq_io_sync_time_seconds_total
rabbitmq_io_write_bytes_total
rabbitmq_io_write_ops_total
rabbitmq_io_write_time_seconds_total
rabbitmq_message_size_bytes_bucket
rabbitmq_message_size_bytes_count
rabbitmq_message_size_bytes_sum
rabbitmq_msg_store_read_total
rabbitmq_msg_store_write_total
rabbitmq_process_max_fds
rabbitmq_process_open_fds
rabbitmq_process_resident_memory_bytes
rabbitmq_queue_consumer_utilisation
rabbitmq_queue_consumers
rabbitmq_queue_disk_reads_total
rabbitmq_queue_disk_writes_total
rabbitmq_queue_exchange_messages_published_total
rabbitmq_queue_get_ack_total
rabbitmq_queue_get_empty_total
rabbitmq_queue_get_total
rabbitmq_queue_index_read_ops_total
rabbitmq_queue_index_write_ops_total
rabbitmq_queue_messages
rabbitmq_queue_messages_acked_total
rabbitmq_queue_messages_bytes
rabbitmq_queue_messages_delivered_ack_total
rabbitmq_queue_messages_delivered_total
rabbitmq_queue_messages_paged_out
rabbitmq_queue_messages_paged_out_bytes
rabbitmq_queue_messages_persistent
rabbitmq_queue_messages_published_total
rabbitmq_queue_messages_ram
rabbitmq_queue_messages_ram_bytes
rabbitmq_queue_messages_ready
rabbitmq_queue_messages_ready_bytes
rabbitmq_queue_messages_ready_ram
rabbitmq_queue_messages_redelivered_total
rabbitmq_queue_messages_unacked
rabbitmq_queue_messages_unacked_bytes
rabbitmq_queue_messages_unacked_ram
rabbitmq_queue_process_memory_bytes
rabbitmq_queue_process_reductions_total
rabbitmq_queues
rabbitmq_queues_created_total
rabbitmq_queues_declared_total
rabbitmq_queues_deleted_total
rabbitmq_raft_batches
rabbitmq_raft_bytes_written
rabbitmq_raft_entries
rabbitmq_raft_mem_tables
rabbitmq_raft_segments
rabbitmq_raft_wal_files
rabbitmq_raft_writes
rabbitmq_resident_memory_limit_bytes
rabbitmq_schema_db_disk_tx_total
rabbitmq_schema_db_ram_tx_total
rabbitmq_stream_segments
rabbitmq_unreachable_cluster_peers_count
```
</details>

### fc-userscan

fc-userscan no longer scans for nix store references in human users and all
existing garbage collection roots will be removed. Service users are not
affected. You can still add gcroots manually (e.g. via `nix-store --add-root`).


### Webproxy: Vinyl Cache and Varnish Cache

The Varnish Cache open-source project renamed itself to Vinyl Cache.
We follow this rename and use Vinyl Cache 9 as the new default package for the `webproxy` role.
We still allow using Varnish Cache 8 in this release, but will remove this option with fc-nixos 26.11,
read the [role documentation](#nixos-webproxy) for more information on how to use Varnish Cache 8.

The project [`varnish-modules`](https://github.com/varnish/varnish-modules), which is published under `pkgs.varnish80Packages.modules` is not available for Vinyl Cache 9, as it is incompatible.

The Vinyl Cache 9 release contains breaking changes, see [Upgrading to Vinyl Cache 9.0](https://vinyl-cache.org/docs/9.0/whats-new/upgrading-9.0.html).

With the update to Vinyl Cache 9, all binary names changed from `varnishXXX` to `vinylXXX`
and the user it runs in changed to `vinyl-cache`.

We still support configuring Vinyl Cache 9 via `flyingcircus.services.varnish.virtualHosts` and `/etc/local/varnish/default.vcl` for this release, but please migrate this configuration to `flyingcircus.services.vinyl-cache.virtualHosts` and `/etc/local/vinyl-cache/default.vcl`.

We support this migration with NixOS warnings, which you can review using the command 'fc-manage check'.
After migrating to fc-nixos 26.05, this command will highlight any deprecated behaviour and
suggest migration paths tailored to the VMs' specific situation.

## Other notable changes

- The `imagemagick6` family of packages has known vulnerabilities and is not permitted by default anymore. Update your applications to work with a current version of imagemagick, or add this to `flyingcircus.permittedInsecurePackages`.

- The sensu `swap` checks have been removed, as they are no longer relevant with systemd-oomd, which we introduced in fc-nixos 25.11

- The default `k3s` package has been bumped to 1.33

- `services.dovecot2.extraConfig` was removed. Migrate configuration to `services.dovecot2.settings`.

- `security.dhparams` has been deprecated. Remove any uses of DHE and migrate to ECDHE (RFC 8422, 2018) and Hybrid PQ (draft-ietf-tls-ecdhe-mlkem, 2026) key exchange algorithms. `security.dhparams` will be removed in fc-nixos 26.11

## Known issues

None.

## Significant package updates
