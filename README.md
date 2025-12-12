## Notes to bootstrap Fedora CoreOS server running Jellyfin.

***Created with extremely heavy use of Claude AI and ChatGPT***

### To set the user `core` password hash, use this command:
```
mkpasswd --method=yescrypt
```

and substitute it here:
```
password_hash: $y$j9...
```

### Update the SSH key as required.

### To prepare the SSD data drive that will store Jellyfin media, follow these steps:
```
# Format and label
sudo mkfs.btrfs -L storage /dev/sdX

# Create the subvolume
sudo mount /dev/disk/by-label/storage /mnt
sudo btrfs subvolume create /mnt/media
sudo umount /mnt
```

### To generate a Tailscale Auth Key

1. Go to [Tailscale Admin Console → Settings → Keys](https://login.tailscale.com/admin/settings/keys)

2. Generate a new auth key with these settings:

* Reusable: Optional (one-time is fine for a single server)
* Ephemeral: No (you want this machine to persist)
* Pre-approved: Yes (skips manual approval)
* Tags: Add a tag like `tag:server` if you use ACLs


For Funnel to work, ensure your ACL policy includes funnel permissions for this node (in the Tailscale admin under Access Controls)/

### Key Points

Auth key placement: The key is stored in `/etc/tailscale/authkey` with restrictive permissions (0600). The `tailscale-auth.service` deletes it after successful authentication for security.

Service ordering: The services chain properly: `rpm-ostree-install` → `tailscaled` → `tailscale-auth` → `tailscale-funnel-jellyfin`

Stamp files: The `.stamp` files in `/var/lib/` prevent re-running one-time setup tasks on subsequent boots.

Funnel prerequisites: For funnel to work, you'll also need to enable it in your Tailscale ACL policy. Add something like this to your policy file in the admin console:
```
{
  "nodeAttrs": [
    {
      "target": ["tag:server"],
      "attr": ["funnel"]
    }
  ]
}
```

### Usage

Get your auth key (get from https://login.tailscale.com/admin/settings/keys).

Put it in a file called `tailscale_keyfile` and from the same directory, run:
`python3 -m http.server 8000`

From the bare metal machine, run:
```
git clone https://github.com/samirparikh/winserv-config
cd winserv-config
chmod +x install.sh
./install.sh
```

### What Happens on First Boot

1. `rpm-ostree-install-tailscale.service` — Installs Tailscale and starts tailscaled

2. `tailscale-auth.service` — Authenticates using your auth key, then deletes the key file

3. `tailscale-funnel-jellyfin.service` — Waits for Tailscale to connect, then starts the funnel on port 8096
