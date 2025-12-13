# Fedora CoreOS Jellyfin Server with Tailscale Funnel

Automated deployment of a Jellyfin media server on Fedora CoreOS, exposed to the internet via Tailscale Funnel.

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
4. **jellyfin.container** — Runs as a rootless Podman container under the `jellyfin` user

## Architecture Notes

**Auth key security**: The key is stored in `/etc/tailscale/authkey` with mode 0600. After successful authentication, `tailscale-auth.service` deletes it via `ExecStartPost`.

**Service ordering**: Services use `After=` for ordering and `Wants=` (not `Requires=`) for dependencies. This is necessary because `tailscaled.service` doesn't exist at boot time—it only appears after Tailscale is installed by rpm-ostree.

**Stamp files**: One-time setup services create stamp files in `/var/lib/` (e.g., `/var/lib/tailscale-auth.service.stamp`) to prevent re-running on subsequent boots.

**Jellyfin user**: Runs as UID 1001 with lingering enabled, allowing the rootless container to start at boot without a login session.

## Troubleshooting

### Check service status
```bash
systemctl status rpm-ostree-install-tailscale.service
systemctl status tailscale-auth.service
systemctl status tailscale-funnel-jellyfin.service
sudo -u jellyfin systemctl --user status jellyfin.service
```

### View service logs
```bash
sudo journalctl -u tailscale-auth.service --no-pager
sudo journalctl -u tailscaled.service --no-pager
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

### Duplicate machine names in Tailscale
After reinstalling, you may see both `winserv` (offline) and `winserv-1` in your tailnet. Delete the old entry from the [Tailscale admin console](https://login.tailscale.com/admin/machines) and optionally rename the new one.

## Files

| File | Purpose |
|------|---------|
| `winserv.bu` | Butane configuration (human-readable) |
| `install.sh` | Installation script that renders the config and runs coreos-installer |
| `tailscale_keyfile` | Your Tailscale auth key (not committed to repo) |
