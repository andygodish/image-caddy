# Caddy Reverse Proxy Image

Builds an opinionated wrapper around the upstream [Caddy](https://caddyserver.com/) container image for homelab reverse proxy deployment.

This image uses the maintained upstream Caddy image and applies the local homelab contract around version pinning, non-root runtime, named volumes, and Makefile operations. The container listens on unprivileged ports internally and Compose maps host ports `80` and `443` to those ports.

## Runtime Contract

| Requirement | Value |
| --- | --- |
| Base image | `caddy:2.11.7-alpine` |
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

## Optional Pi-hole integration on the same Docker host

Add a local A record in Pi-hole: `pihole.home.arpa -> 192.168.1.202`.
When explicitly started with their `docker-compose.proxy.yaml` overlays,
both Compose projects join the external `homelab-proxy` bridge in addition to
their existing default networks. Caddy uses Docker DNS to reach `pihole-new:80`;
it does not connect to the host's loopback port 8080. Pi-hole's existing
loopback admin binding remains available for recovery through an SSH tunnel.

Add this block to the local `Caddyfile`, preserving existing routes:

```caddyfile
pihole.home.arpa {
    tls internal
    reverse_proxy pihole-new:80
}
```

`Caddyfile` is intentionally ignored by Git. The tracked `Caddyfile.example`
contains this route as a commented example; a Git pull on the Docker host does
not update its local Caddyfile. Do not copy the example over an existing config.

After updating both repositories and the host's local Caddyfile, run each step
on the Docker host. Recreating Pi-hole briefly interrupts DNS; named volumes
are retained. No image rebuild is needed for these Compose/config changes.

```bash
# Once per Docker host; reuse the network if it already exists.
docker network inspect homelab-proxy >/dev/null 2>&1 || docker network create homelab-proxy

# From ~/image-pihole (retain its existing .env and .secrets).
docker compose -f docker-compose.yaml -f docker-compose.proxy.yaml config --quiet
docker compose -f docker-compose.yaml -f docker-compose.proxy.yaml up -d --no-deps pihole

# From ~/image-caddy; validate before recreating Caddy to attach its network.
docker compose -f docker-compose.yaml -f docker-compose.proxy.yaml config --quiet
docker compose -f docker-compose.yaml -f docker-compose.proxy.yaml run --rm --no-deps --entrypoint caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose -f docker-compose.yaml -f docker-compose.proxy.yaml up -d --no-deps caddy
```

Visit `https://pihole.home.arpa/admin/`. `tls internal` uses Caddy's existing
local CA, separate from FreeIPA's CA. Client devices need to trust that CA to
avoid certificate warnings. If it is not already trusted, export only its public
root certificate from the running Caddy container:

```bash
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
```

Transfer that public certificate securely and trust it on authorized home
devices. Do not copy the CA private key or change managed work-device policies.
The work Mac's managed DNS may still prevent browser resolution even when a
direct `dig @192.168.1.202 pihole.home.arpa A +short` succeeds.

Caddy can run without Pi-hole: other routes remain available, while this route
returns 502 if its backend is absent. The external network must exist at startup;
Compose does not create or delete it. Either project's `docker compose down`
leaves the shared network and named volumes intact. No `depends_on` links the
projects. Only trusted proxy backends should join this shared network.

References: [Docker cross-project networking](https://docs.docker.com/compose/how-tos/networking/),
[Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy),
and [Caddy local HTTPS trust](https://caddyserver.com/docs/automatic-https#local-https).

### Why an optional shared network?

The base `docker-compose.yaml` runs this service independently. Ordinary
`docker compose up -d` or `make up` does not require `homelab-proxy`, a sibling
repository, or the other container. Image builds and image runtime defaults do
not depend on this network.

Each Compose project normally has its own private default bridge. A container
on one project's default bridge cannot discover the other project's service
through Docker DNS. Also, `127.0.0.1` inside Caddy refers to Caddy itself, not
the Docker host or Pi-hole. The optional shared bridge gives Caddy a stable
Docker name, `pihole-new`, through which it can reach Pi-hole's internal HTTP
port 80. No fixed container IP or additional LAN web port is needed.

This bridge exists only inside one Docker host. It is not a UniFi VLAN, a LAN
DNS zone, or a replacement for Pi-hole's DNS service. Browser requests still
resolve `pihole.home.arpa` to the host's LAN IP and connect to Caddy on 443.
Caddy then makes a separate HTTP request over the bridge to Pi-hole. DNS
queries from LAN clients still use Pi-hole's published host port 53. The
`.202` address and `pihole.home.arpa` name describe this homelab, not required
values for another developer.

The overlay is optional because another deployment may run only one service,
use another reverse proxy, or put the services on different machines. For
separate machines, configure a reachable, appropriately protected backend
address instead; this single-host bridge cannot connect them. A standalone
Pi-hole installation can use its published admin port, and standalone Caddy
can proxy any configured reachable backend.

When this integration is enabled, create `homelab-proxy` once on the Docker
host. `external: true` means the operator owns its lifecycle: neither Compose
project creates or deletes it. The services have no cross-project startup
ordering or `depends_on`. Caddy starts without Pi-hole, but requests to the
Pi-hole route return 502 while the backend is unavailable. Pi-hole continues
serving DNS without Caddy. Only trusted proxy backends should share this
network, since members can reach each other's container ports.

Keep including both `-f` files when updating the integrated deployment.
Running plain `make up` or base-only `docker compose up -d` reconciles it back
to standalone networking and removes the shared connection, breaking the
proxy route. To intentionally return to standalone operation, remove the
Pi-hole route from Caddy's local Caddyfile first, then run base-only
`docker compose up -d` in each project. Named volumes and the external network
are retained; do not use `down -v`.

See [Docker's cross-project networking documentation](https://docs.docker.com/compose/how-tos/networking/#connecting-multiple-compose-projects).
