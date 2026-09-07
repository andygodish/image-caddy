# Caddy Reverse Proxy Image

Builds an opinionated wrapper around the upstream [Caddy](https://caddyserver.com/) container image for homelab reverse proxy deployment.

This image uses the maintained upstream Caddy image and applies the local homelab contract around version pinning, non-root runtime, named volumes, and Makefile operations. The container listens on unprivileged ports internally and Compose maps host ports `80` and `443` to those ports.

## Runtime Contract

| Requirement | Value |
| --- | --- |
| Base image | `caddy:2.11.4-alpine` |
| Runtime UID/GID | `10005:10005` |
| Config directory | `/config` |
| Data directory | `/data` |
| HTTP port | `8080` in container, `80` on host |
| HTTPS port | `8443` in container, `443` on host |
| Config file | local `./Caddyfile` mounted to `/etc/caddy/Caddyfile` |
| Compose image | `ghcr.io/andygodish/caddy:v2.11.4-0` |

## Operational Guide

Run these commands inside the `image-caddy` directory.

```bash
make up
make status
make logs
make down
```

`make up` builds the local wrapper image and launches the standalone `docker-compose.yaml` service. Compose mounts the local untracked `Caddyfile` over `/etc/caddy/Caddyfile` and uses Docker named volumes for `/config` and `/data`, preserving Caddy state and certificates across restarts.

The default Caddyfile exposes a simple health endpoint:

```bash
curl http://127.0.0.1/health
```

## Adding Homelab Routes

Create a local `Caddyfile` from the tracked example, edit it for the target host, and restart:

```bash
cp Caddyfile.example Caddyfile
make up
```

Example Proxmox route:

```caddyfile
proxmox.home.arpa {
	reverse_proxy https://192.168.1.10:8006 {
		transport http {
			tls_insecure_skip_verify
		}
	}
}
```

Use `home.arpa` or another local DNS zone instead of `.local` when possible. `.local` is reserved for mDNS and can conflict with normal DNS behavior.

For hosts-file testing, point each name at the Docker host running Caddy:

```text
192.168.1.20 proxmox.home.arpa
```

## Release

Publish a multi-platform release:

```bash
make build-multiarch
```
