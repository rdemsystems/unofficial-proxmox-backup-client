# Paquets non officiels proxmox-backup-client

🇬🇧 [Read in English](README.md)

> **Dépôt non officiel, sans lien avec Proxmox Server Solutions GmbH ni approuvé par elle.**
> Proxmox est une marque déposée de Proxmox Server Solutions GmbH.

Paquets `proxmox-backup-client` signés pour **Fedora, RHEL, Rocky Linux, AlmaLinux, Arch Linux et
Alpine** (amd64, arm64) : le binaire statique officiel de Proxmox, reconditionné sans modification,
vérifié chaque jour contre le dépôt de Proxmox.

**Pour installer le client, utilisez le dépôt de paquets, pas ce dépôt Git :**

- 📦 **Dépôt de paquets et instructions d'installation (dnf, pacman, apk, apt) :**
  https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/
- 📘 **Tutoriel — sauvegarder un serveur Linux avec proxmox-backup-client :**
  https://nimbus.rdem-systems.com/blog/proxmox-backup-client-linux/
- 🪟 **Sous Windows :** [NimbusBackupClient](https://github.com/rdemsystems/NimbusBackupClient),
  notre client graphique pour Proxmox Backup Server.
- ☁️ **Maintenu par [NimbusBackup](https://nimbus.rdem-systems.com/)**, hébergement de Proxmox
  Backup Server managé par RDEM Systems.

Ce dépôt GitHub publie les scripts de build (MIT), pour que chacun puisse vérifier ou reproduire la
fabrication des paquets. La CI qui signe et publie les paquets tourne sur le GitLab de RDEM Systems ;
les clés de signature n'en sortent jamais. Le détail du pipeline est dans le [README anglais](README.md#how-a-release-is-made).

## Reconditionnement seulement : les binaires sont ceux de Proxmox

Ce projet **ne compile pas, ne modifie pas et ne forke pas** le client Proxmox Backup Server. Il
reconditionne seulement les binaires de Proxmox pour les distributions que Proxmox ne livre pas :

1. **Télécharger** le build officiel de Proxmox, lié statiquement (`proxmox-backup-client-static`),
   depuis `download.proxmox.com`, et le vérifier contre l'index signé du dépôt de Proxmox.
2. **Reconditionner** ce binaire, inchangé, en paquets RPM, Arch et APK. Debian et Ubuntu reçoivent
   le `.deb` de Proxmox octet pour octet.
3. **Signer et déployer** les paquets sur les serveurs de RDEM Systems, sous forme de dépôt
   utilisable par votre gestionnaire de paquets.

Aucune ligne du code de Proxmox n'est modifiée ni recompilée. Les paquets RPM, Arch et APK
n'ajoutent que deux liens symboliques vers les certificats, expliqués dans
[La seule modification](#la-seule-modification).

| Famille | Tests d'installation en CI | Gestionnaire de paquets |
|---|---|---|
| RHEL, Fedora | CentOS 7 · Rocky Linux 8, 9, 10 · AlmaLinux 8, 9, 10 · Fedora 42, 43, 44 | `dnf` / `yum` |
| Arch Linux | Arch (rolling) | `pacman` |
| Alpine | 3.20, 3.21, 3.22, 3.23, 3.24 | `apk` |
| Debian, Ubuntu | Debian 10, 11, 12, 13, testing, sid · Ubuntu 20.04, 22.04, 24.04, 25.10, 26.04 | `apt` (le `.deb` amont, octet pour octet) |

Politique de test : chaque version encore supportée par sa distribution, plus au moins la dernière
sortie du support ; Arch est en rolling release.
Si vous voulez d'autres distributions, [faites-le-nous savoir](https://nimbus.rdem-systems.com/contact/), en nous disant pourquoi.

Architectures : **amd64** depuis le composant `main` de Proxmox, **arm64** depuis le composant
`test` (le build statique aarch64 officiel, qui peut avoir une version de retard). Chaque paquet
indique son composant d'origine, visible dans `index.json`.

Chaque release publie aussi `source/proxmox-backup-<version>.zip` : les sources de Proxmox au commit
« bump version to <version> » dont le binaire est issu.

## Installation

Toutes les métadonnées du dépôt sont signées : n'ajoutez jamais `--nogpgcheck` ni
`--allow-untrusted`. Comparez l'empreinte affichée par votre gestionnaire de paquets avec celle
publiée sur https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/ et dans
[`FINGERPRINTS.txt`](https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/FINGERPRINTS.txt) :

```
OpenPGP (RPM, pacman, apt) : 827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F
```

Commandes à lancer en root.

### Fedora, RHEL, Rocky Linux, AlmaLinux (dnf)

```sh
curl -fsSL -o /etc/yum.repos.d/unofficial-repository-proxmox-backup-client.repo \
  https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/rpm/unofficial-repository-proxmox-backup-client.repo
dnf install proxmox-backup-client
```

### Arch Linux (pacman)

```sh
curl -fsSL -o /tmp/upc.asc https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.asc
gpg --show-keys /tmp/upc.asc      # comparez avec l'empreinte ci-dessus
pacman-key --add /tmp/upc.asc
pacman-key --lsign-key "$(gpg --with-colons --show-keys /tmp/upc.asc | awk -F: '/^fpr:/{print $10; exit}')"
printf '\n[unofficial-repository-proxmox-backup-client]\nServer = https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/arch/$arch\n' >> /etc/pacman.conf
pacman -Syu proxmox-backup-client
```

### Alpine Linux (apk)

```sh
wget -O /etc/apk/keys/unofficial-repository-proxmox-backup-client.rsa.pub \
  https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.rsa.pub
echo "https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/alpine" >> /etc/apk/repositories
apk add proxmox-backup-client
```

### Debian, Ubuntu (apt)

Le dépôt apt sert le `.deb` de Proxmox sans modification (même SHA256 qu'en amont). Sur Debian, le
dépôt `pbs-client` de Proxmox reste l'alternative officielle.

```sh
install -d /etc/apt/keyrings
curl -fsSL -o /etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.asc
echo "deb [signed-by=/etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc] https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/deb stable main" \
  > /etc/apt/sources.list.d/unofficial-repository-proxmox-backup-client.list
apt update && apt install proxmox-backup-client-static
```

### Ensuite

Reliez le client à un Proxmox Backup Server, chiffrez, planifiez et restaurez — guide pas à pas :
https://nimbus.rdem-systems.com/blog/proxmox-backup-client-linux/

## La seule modification

Le binaire statique a été compilé avec le répertoire OpenSSL de Debian (`/usr/lib/ssl`) inscrit en
dur. Hors Debian et Ubuntu, ce répertoire n'existe pas : le client refuse alors des certificats
**valides** et demande une empreinte (`certificate validation failed - Certificate fingerprint was
not confirmed`). Constaté sur Alpine 3.24 et Fedora 43.

Nos paquets RPM, Arch et APK ajoutent donc deux liens symboliques :

```
/usr/lib/ssl/cert.pem -> le fichier de certificats de la distribution
/usr/lib/ssl/certs    -> le répertoire de certificats de la distribution
```

Ces deux-là seulement : lier tout `/usr/lib/ssl` vers `/etc/ssl` ferait aussi lire à l'OpenSSL
statique le `openssl.cnf` de la distribution. Les binaires, pages de manuel et complétions shell
sont les fichiers d'origine. Les fichiers `.deb` sont servis sans modification.

## Licences

- Scripts de build de ce dépôt : MIT, voir `LICENSE` (périmètre et mention de marque dans `NOTICE`).
- Logiciel empaqueté : GNU AGPL v3 ou ultérieure, Copyright Proxmox Server Solutions GmbH. Les
  sources correspondantes sont publiées avec chaque release sous `source/`, issues du dépôt
  `proxmox-backup` de Proxmox (https://git.proxmox.com/?p=proxmox-backup.git).
