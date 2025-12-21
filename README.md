# Fedora CoreOS Jellyfin Server with Tailscale Funnel and AdGuard Home

Automated deployment of a Jellyfin media server and AdGuard Home DNS server on Fedora CoreOS, with Jellyfin exposed to the internet via Tailscale Funnel.

## Prerequisites

- Bare metal machine or VM for Fedora CoreOS
- Secondary storage drive for media (will be formatted as btrfs)
- Tailscale account with Funnel enabled
- Another machine to serve the auth key during installation

## Quick Start

1. Generate a Tailscale auth key (see [Auth Key Setup](#tailscale-auth-key-setup))
2. Save it to a file called `tailscale_keyfile` and serve it via HTTP:
   ```bash
   python3 -m http.server 8000
   ```
3. Boot the target machine from a Fedora CoreOS live ISO
4. Run the installer:
   ```bash
   git clone https://github.com/samirparikh/winserv-config
   cd winserv-config
   chmod +x install.sh
   ./install.sh
   ```

## Services

After provisioning, the following services are available:

| Service | Local Network (LAN) | Tailnet (traveling) | Notes |
|---------|---------------------|---------------------|-------|
| Jellyfin | `http://192.168.1.229:8096`<br>`http://winserv:8096` | `http://winserv:8096`<br>Via Tailscale Funnel (public) | Rootless, runs as jellyfin user |
| AdGuard Home setup | `http://192.168.1.229:3000`<br>`http://winserv:3000` | `http://winserv:3000` | Initial configuration wizard (first run only) |
| AdGuard Home admin | `http://192.168.1.229`<br>`http://winserv` | `http://winserv` | Rootful, runs as root |
| AdGuard Home DNS | `192.168.1.229:53` | `winserv:53` (Tailscale Magic DNS) | Point your router to LAN IP, devices to Tailnet hostname when traveling |

## Configuration

### User Password

Generate a password hash for the `core` user:
```bash
mkpasswd --method=yescrypt
```

Update the `password_hash` field in `winserv.bu`.

### SSH Key

Replace the `ssh_authorized_keys` entry in `winserv.bu` with your public key.

### Storage Drive

Prepare the media storage drive before installation:
```bash
# Format and label the drive
sudo mkfs.btrfs -L storage /dev/sdX

# Create the media subvolume
sudo mount /dev/disk/by-label/storage /mnt
sudo btrfs subvolume create /mnt/media
sudo umount /mnt
```

The Butane configuration expects a drive labeled `storage` with a `media` subvolume.

## Tailscale Auth Key Setup

1. Go to [Tailscale Admin Console → Settings → Keys](https://login.tailscale.com/admin/settings/keys)

2. Generate a new auth key with these settings:
   - **Reusable**: Yes (recommended if iterating on the setup)
   - **Ephemeral**: No (the machine should persist in your tailnet)
   - **Pre-approved**: Yes (skips manual approval)
   - **Tags**: Add `tag:server` if using ACLs

3. Enable Funnel in your ACL policy. In the Tailscale admin console under Access Controls, add:
   ```json
   {
     "nodeAttrs": [
       {
         "target": ["tag:server"],
         "attr": ["funnel"]
       }
     ]
   }
   ```

## What Happens on First Boot

1. **rpm-ostree-install-tailscale.service** — Installs Tailscale via rpm-ostree and starts tailscaled
2. **tailscale-auth.service** — Waits for tailscaled socket, authenticates with the auth key, then deletes the key file
3. **tailscale-funnel-jellyfin.service** — Waits for Tailscale to come online, then starts the funnel on port 8096
4. **disable-resolved-stub.service** — Restarts systemd-resolved to disable the stub listener on port 53
5. **jellyfin-firewall.service** — Opens firewall ports 8096/tcp and 7359/udp for Jellyfin
6. **adguardhome-firewall.service** — Opens firewall ports for AdGuard Home (53, 80, 853, 3000, 784, 8853, 5443)
7. **jellyfin.container** — Runs as a rootless Podman container under the `jellyfin` user
8. **adguardhome.container** — Runs as a rootful Podman container

## Architecture Notes

**Auth key security**: The key is stored in `/etc/tailscale/authkey` with mode 0600. After successful authentication, `tailscale-auth.service` deletes it via `ExecStartPost`.

**Service ordering**: Services use `After=` for ordering and `Wants=` (not `Requires=`) for dependencies. This is necessary because `tailscaled.service` doesn't exist at boot time—it only appears after Tailscale is installed by rpm-ostree.

**Stamp files**: One-time setup services create stamp files in `/var/lib/` (e.g., `/var/lib/tailscale-auth.service.stamp`) to prevent re-running on subsequent boots.

**Jellyfin user**: Runs as UID 1001 with lingering enabled, allowing the rootless container to start at boot without a login session.

**systemd-resolved and port 53**: By default, systemd-resolved binds a stub listener to port 53, which conflicts with AdGuard Home. The configuration disables this via `/etc/systemd/resolved.conf.d/disable-stub.conf` and restarts resolved before AdGuard Home starts. The host system uses external DNS directly rather than AdGuard Home for its own lookups.

**Container auto-updates**: Both rootless (jellyfin user) and rootful containers are configured to auto-update via Podman's `podman-auto-update.timer`. The timer checks daily for new images and restarts containers when updates are available.

**AdGuard Home data**: Configuration and working data are stored in `/var/srv/adguardhome/conf` and `/var/srv/adguardhome/work` respectively, persisting across container restarts.

## Troubleshooting

### Check service status
```bash
# Tailscale services
systemctl status rpm-ostree-install-tailscale.service
systemctl status tailscale-auth.service
systemctl status tailscale-funnel-jellyfin.service

# Jellyfin (rootless)
sudo systemctl --machine=jellyfin@.host --user status jellyfin.service

# AdGuard Home (rootful)
systemctl status adguardhome.service

# systemd-resolved stub disable
systemctl status disable-resolved-stub.service
```

### View service logs
```bash
sudo journalctl -u tailscale-auth.service --no-pager
sudo journalctl -u tailscaled.service --no-pager
sudo journalctl -u adguardhome.service --no-pager
```

### "invalid key" error
Your auth key is expired or was already used (if single-use). Generate a new key from the Tailscale admin console. To retry without reinstalling:
```bash
echo -n 'tskey-auth-NEW-KEY-HERE' | sudo tee /etc/tailscale/authkey > /dev/null
sudo chmod 600 /etc/tailscale/authkey
sudo rm -f /var/lib/tailscale-auth.service.stamp
sudo systemctl restart tailscale-auth.service
```

### tailscale-auth.service shows "inactive (dead)" with no logs
The service never ran, likely due to a missing dependency. Check that `tailscaled.service` is running:
```bash
systemctl status tailscaled.service
```

### Tailscale authenticated but funnel not working
Verify funnel status:
```bash
tailscale funnel status
```

Check that Funnel is enabled in your Tailscale ACL policy and that the node has the appropriate tag.

### AdGuard Home fails to start with port 53 error
Verify that systemd-resolved released port 53:
```bash
ss -tulnp | grep :53
systemctl status disable-resolved-stub.service
cat /etc/systemd/resolved.conf.d/disable-stub.conf
```

If port 53 is still bound by systemd-resolved, restart it manually:
```bash
sudo systemctl restart systemd-resolved
sudo systemctl restart adguardhome.service
```

### Check container auto-update status
```bash
# Rootful containers
sudo podman auto-update --dry-run

# Rootless containers (as jellyfin user)
sudo -u jellyfin podman auto-update --dry-run
```

### Duplicate machine names in Tailscale
After reinstalling, you may see both `winserv` (offline) and `winserv-1` in your tailnet. Delete the old entry from the [Tailscale admin console](https://login.tailscale.com/admin/machines) and optionally rename the new one.

## Project Structure

The butane configuration is now modularized for easier maintenance:

```
fcos/
├── butane/
│   ├── base.bu              # Variant and version
│   ├── network.bu           # Hostname and static IP configuration
│   ├── users.bu             # User accounts (core, jellyfin)
│   ├── storage.bu           # Mount points and storage permissions
│   ├── tailscale.bu         # Tailscale installation and configuration
│   ├── containers/
│   │   ├── jellyfin.bu      # Jellyfin container and services
│   │   ├── adguardhome.bu   # AdGuard Home container and services
│   │   └── homepage.bu      # Homepage dashboard with YAML configs
│   └── misc.bu              # Miscellaneous configs (bash_profile, etc.)
├── build.sh                 # Script to merge modular butane files
└── homelab.bu               # Generated combined butane file
```

| File | Purpose |
|------|---------|
| `fcos/butane/*.bu` | Modular butane configuration files (human-readable) |
| `fcos/build.sh` | Builds homelab.bu from modular butane files |
| `fcos/homelab.bu` | Generated combined butane file (created by build.sh) |
| `fcos/homelab.ign` | Generated ignition file (created by install.sh) |
| `install.sh` | Installation script that builds config and runs coreos-installer |
| `tailscale_keyfile` | Your Tailscale auth key (not committed to repo) |
| `winserv.bu` | Legacy monolithic butane file (kept for reference) |

## Making Changes

To modify the configuration:

1. Edit the relevant file in `fcos/butane/` or `fcos/butane/containers/`
2. Run `./install.sh` when ready to install

The `install.sh` script automatically runs `build.sh` to merge all modular files before installation.

### Testing Changes Without Installing

If you want to preview the generated configuration without installing:

```bash
fcos/build.sh           # Generate homelab.bu from modular files
cat fcos/homelab.bu     # Review the merged configuration
```

This is useful for:
- Verifying your modular changes merge correctly
- Reviewing the complete configuration before committing to installation
- Debugging configuration issues

You do **not** need to run `build.sh` manually before running `install.sh` - it's called automatically.
