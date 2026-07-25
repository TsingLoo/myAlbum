# Architecture

```text
phones and browsers
        |
        v
Immich :2283
  |-- originals -> /srv/immich-data/immich/{upload,library,profile}
  |-- generated -> /srv/immich-data/immich/{thumbs,encoded-video}
  `-- PostgreSQL -> /var/lib/immich-postgres

OpenList :5244
  `-- China Mobile Cloud authorization (runtime secret, not in Git)
```

The internal SSD contains Debian, containers, and PostgreSQL. The external ext4
disk contains Immich assets. Neither disk is itself a backup.

The cloud backup must contain original assets, a consistent PostgreSQL dump,
deployment configuration, checksums, and restore instructions. Thumbnails and
encoded videos may be regenerated.

Large transient cloud-backup files are written to
`/srv/immich-data/.backup-work` on the external disk so they cannot fill the
internal system SSD. Successful jobs remove their generation directory.

`/srv/family-share` is an elastic directory on the internal SSD. It has no
preallocated size and consumes space only as files are added. Access is
controlled by the `familyshare` group; network-sharing services should grant
write access through that group.
