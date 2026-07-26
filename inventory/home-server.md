# Current host inventory

Captured on 2026-07-25.

| Item | Value |
|---|---|
| Hostname | `home-server` |
| OS | Debian GNU/Linux 13 (trixie), x86-64 |
| LAN address | `192.168.30.136` |
| Immich URL | `http://192.168.30.136:2283` |
| OpenList URL | `http://192.168.30.136:5244` |
| Internal disk | 256 GB SATA SSD (`/dev/sda`) |
| Media disk | 2 TB Toshiba USB HDD (`/dev/sdb`) |
| Media filesystem | ext4, UUID `8551ca9f-2f26-4af4-8802-8628e5e0a7e8` |
| Shared storage mount | `/srv/hdd_storage`, `noatime,nofail` |
| LAN DNS name | `myhome.server` |
| Network failover | `eno1` preferred; `wlo2` joins `TheNet_AX`/`TheNet` only without wired carrier |
| Docker | 29.6.2 |
| Docker Compose | 5.3.1 |

Device names such as `/dev/sdb` are not stable. Recovery scripts identify and
persist the filesystem by UUID.
