# SOPS Secrets Management

## Key Model

There are two types of age keys:

- **Personal key** (`~/.config/sops/age/keys.txt`) — lets you edit/encrypt secrets on your workstation. This is the only key you manage manually.
- **Host SSH keys** (`/etc/ssh/ssh_host_ed25519_key`) — lets each host decrypt secrets at boot. Every NixOS machine already has this key, no extra setup needed.

`.sops.yaml` lists all keys that can access the secrets:

```yaml
keys:
  - &users:
    - &ta age1csagu4...    # your personal key
  - &hosts:
    - &athena age1cvy...   # athena's SSH host key (derived)
    - &medusa age1abc...   # add more hosts as needed
```

## How Decryption Works

1. You encrypt `secrets.yaml` on your workstation using your personal age key
2. SOPS encrypts the data key for every recipient listed in `.sops.yaml`
3. At boot/activation, sops-nix on each host decrypts using its SSH host key
4. Decrypted secrets appear as files under `/run/secrets/`

## Adding a New Host

1. Get the host's age key (run on the target host):

```bash
nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
```

2. Add the key to `.sops.yaml`:

```yaml
keys:
  - &hosts:
    - &athena age1cvy...
    - &newhost age1xyz...   # add here

creation_rules:
  - path_regex: secrets.yaml$
    key_groups:
    - age:
      - *ta
      - *athena
      - *newhost              # add here
```

3. Re-encrypt secrets for the new host:

```bash
sops updatekeys secrets.yaml
```

4. On the new host, import `modules/sops.nix` and load `sops-nix.nixosModules.sops` in `flake.nix`.

## Adding a New Secret

Edit the encrypted file (decrypts in your editor, re-encrypts on save):

```bash
sops secrets.yaml
```

Then declare it in the host's `configuration.nix`:

```nix
sops.secrets."my-secret" = {
  owner = config.users.users.fobos.name;
  # mode = "0400";           # default, owner read-only
  # path = "/custom/path";   # default is /run/secrets/<name>
};
```

Rebuild and the secret appears at `/run/secrets/my-secret`.

## Per-Host Secret Files

If hosts need different secrets, split into separate files:

```
secrets/
  athena.yaml
  medusa.yaml
```

Update `.sops.yaml` with per-host creation rules:

```yaml
creation_rules:
  - path_regex: secrets/athena.yaml$
    key_groups:
    - age:
      - *ta
      - *athena

  - path_regex: secrets/medusa.yaml$
    key_groups:
    - age:
      - *ta
      - *medusa
```

Then point each host's sops config to its own file:

```nix
# in hosts/athena/configuration.nix
sops.defaultSopsFile = ./../../secrets/athena.yaml;
```

## File Locations

| File | Purpose |
|------|---------|
| `~/.config/sops/age/keys.txt` | Your personal age private key (never commit) |
| `.sops.yaml` | Key registry and encryption rules |
| `secrets.yaml` | Encrypted secrets (safe to commit) |
| `modules/sops.nix` | Shared sops-nix config for all hosts |
| `/run/secrets/` | Decrypted secrets on each host (tmpfs, runtime only) |
