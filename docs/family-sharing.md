# Family network share

The elastic internal-SSD directory `/srv/family-share` is exposed only on the
home LAN through:

| Protocol | Address |
|---|---|
| SMB2/SMB3 | `\\myhome.server\Family` |
| NFSv4 | `myhome.server:/srv/family-share` |
| WebDAV | `http://myhome.server:8080/family/` |
| SFTP | `sftp://ashton@myhome.server/srv/family-share` |

Large files intended for versioned backup use the external-disk share:

| Protocol | Address |
|---|---|
| SMB2/SMB3 | `\\myhome.server\FileBackup` |
| NFSv4 | `myhome.server:/srv/hdd_storage/file-backup` |
| WebDAV | `http://myhome.server:8080/file-backup/` |
| SFTP | `sftp://ashton@myhome.server/srv/hdd_storage/file-backup` |

SMB and WebDAV authenticate as `ashton`. Their password databases are runtime
secrets and are excluded from Git. NFS is restricted to `192.168.30.0/24` and
uses root squashing. SFTP uses the existing SSH account.

WebDAV uses password-protected HTTP and is intended only for the trusted home
LAN; use SFTP when transport encryption is required.

The directory has no preallocated capacity. Monitor the system SSD and avoid
letting it exceed 85% usage:

```bash
df -h /srv/family-share
```

Reinstall with `sudo ./scripts/install-family-sharing.sh` after recreating the
WebDAV password file at
`/home/ashton/.config/homeoss/family-webdav.htpasswd` and adding the Samba
password with `sudo smbpasswd -a ashton`.
