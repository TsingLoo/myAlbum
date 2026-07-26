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

The cloud backup must contain original assets, a consistent PostgreSQL dump,
deployment configuration, checksums, and restore instructions. Thumbnails and
encoded videos may be regenerated.

Large transient cloud-backup files are written to
`/srv/hdd_storage/.backup-work` on the external disk so they cannot fill the
internal system SSD. Successful jobs remove their generation directory.

`/srv/lan-share` is an elastic directory on the internal SSD. It has no
preallocated size and consumes space only as files are added. Access is
controlled by the `familyshare` group; network-sharing services should grant
write access through that group.

Kopia reads only `/srv/hdd_storage/file-backup`. Its encrypted repository is on the
external media disk, providing versioned recovery from accidental deletion and
overwrites. This local repository should eventually be replicated off-site for
protection against theft, fire, or failure of both disks.
