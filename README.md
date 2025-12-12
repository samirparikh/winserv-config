## Notes to bootstrap Fedora CoreOS server running Jellyfin.

***Created with extremely heavy use of Claude AI and ChatGPT***

# To set the user `core` password hash, use this command:
```
mkpasswd --method=yescrypt
```

and substitute it here:
```
password_hash: $y$j9...
```

# Update the SSH key as required.

# To prepare the SSD data drive that will store Jellyfin media, follow these steps:
```
# Format and label
sudo mkfs.btrfs -L storage /dev/sdX

# Create the subvolume
sudo mount /dev/disk/by-label/storage /mnt
sudo btrfs subvolume create /mnt/media
sudo umount /mnt
```

# To generate a Tailscale Auth Key

1. Go to [Tailscale Admin Console → Settings → Keys](https://login.tailscale.com/admin/settings/keys)

2. Generate a new auth key with these settings:

* Reusable: Optional (one-time is fine for a single server)
* Ephemeral: No (you want this machine to persist)
* Pre-approved: Yes (skips manual approval)
* Tags: Add a tag like `tag:server` if you use ACLs


For Funnel to work, ensure your ACL policy includes funnel permissions for this node (in the Tailscale admin under Access Controls)/

# Key Points

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

# Usage

Set your auth key (get from https://login.tailscale.com/admin/settings/keys).

If they are in a directory on your main machine, run:
`python3 -m http.server 8000`

Get the keyfile from the main machine onto the bare metal machine.  On the bare metal machine, run:
```
curl -v -O http://192.168.XXX.XXX:8000/tailscale_keyfile
export TAILSCALE_AUTHKEY=$(cat tailscale_keyfile)
```

Generate the Ignition file and install:
```
# Generate Ignition with the secret substituted
sed "s/__TAILSCALE_AUTHKEY__/$TAILSCALE_AUTHKEY/" winserv.bu | butane > /tmp/winserv.ign

# Install Fedora CoreOS
sudo coreos-installer install /dev/sda \
    --ignition-file /tmp/winserv.ign

# Clean up the Ignition file containing the secret
rm /tmp/winserv.ign
```

# What Happens on First Boot

1. `rpm-ostree-install-tailscale.service` — Installs Tailscale and starts tailscaled

2. `tailscale-auth.service` — Authenticates using your auth key, then deletes the key file

3. `tailscale-funnel-jellyfin.service` — Waits for Tailscale to connect, then starts the funnel on port 8096
