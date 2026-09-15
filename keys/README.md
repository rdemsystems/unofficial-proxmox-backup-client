# Pinned upstream key

`proxmox-archive-keyring-trixie.gpg` is the keyring Proxmox publishes for its Debian 13 based
repositories. `check-upstream.sh` verifies `InRelease` against this file only, so a
compromised mirror cannot slip in a different key.

| | |
|---|---|
| Source | https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg |
| SHA256 | `136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45` (matches the value printed in the PBS 4.2 installation docs, checked 2026-09-11) |
| Keys | `F4E1 36C6 7CDC E41A E6DE 6FC8 1140 AF8F 639E 0C39` Proxmox Bookworm Release Key (expires 2032-11-24) |
| | `24B3 0F06 ECC1 836A 4E5E FECB A7BC D142 0BFE 778E` Proxmox Trixie Release Key (expires 2034-11-10), signs the trixie `InRelease` |

When Proxmox rotates keys (next Debian release), replace the file, record the new SHA256
and fingerprints here, and say where they were checked.

Our own public signing keys are not stored here: they are published by the pipeline under
`<base>/keys/`.
