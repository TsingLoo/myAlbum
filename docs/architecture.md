# Architecture

```text
phones and browsers
        |
        v
Immich :2283
  |-- originals -> /srv/hdd_storage/immich/{upload,library,profile}
  |-- generated -> /srv/hdd_storage/immich/{thumbs,encoded-video}
  `-- PostgreSQL -> /var/lib/immich-postgres

OpenList :5244
  `-- China Mobile Cloud authorization (runtime secret, not in Git)

FileBackup share
  `-- /srv/hdd_storage/file-backup -> Kopia encrypted snapshots
                                      -> /srv/hdd_storage/kopia-repository
```

The internal SSD contains Debian, containers, and PostgreSQL. The external ext4
disk contains Immich assets. Neither disk is itself a backup.

The daily Kopia snapshot contains original assets, a consistent PostgreSQL
dump, and deployment configuration. Thumbnails and encoded videos are excluded
because they can be regenerated. The encrypted repository is synchronized
off-site every day. A separate monthly Age archive remains available as a
self-contained fallback.

Large transient cloud-backup files are written to
`/srv/hdd_storage/.backup-work` on the external disk so they cannot fill the
internal system SSD. Successful jobs remove their generation directory.

`/srv/lan-share` is an elastic directory on the internal SSD. It has no
preallocated size and consumes space only as files are added. Access is
controlled by the `familyshare` group; network-sharing services should grant
write access through that group.

The FileBackup and Immich sources use separate Kopia containers, encryption
credentials, local repositories, cloud paths, and retention policies. Their
source mounts are read-only. The repositories are
`/srv/hdd_storage/kopia-repository` and
`/srv/hdd_storage/kopia-immich-repository`; their off-site replicas are
`/kopia-repository` and `/kopia-immich-repository` in China Mobile Cloud.
