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
