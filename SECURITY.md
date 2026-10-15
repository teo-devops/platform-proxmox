# Security policy

## Supported versions

This project is in **beta** (`v0.x`). Only the latest release and `main` receive fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on this repository.

In scope:
- secrets (root password, its hash, PBS tokens) ending up in logs, generated files committed to
  git, or on the nodes in clear text;
- anything that disables host key verification or TLS verification;
- roles that grant more Proxmox privileges than documented, or that weaken the network
  rollback safety net;
- the install scripts (`install/`, `bmc/`) running destructive actions without confirmation.

Out of scope: the security of Proxmox VE itself (report it to Proxmox) and the configuration of a
specific installation.
