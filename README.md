*This project has been created as part of the 42 curriculum by elikavak.*

# Inception

## Description

Inception is a system administration project whose goal is to set up a small
web infrastructure entirely with Docker, built from scratch inside a
dedicated virtual machine. Instead of relying on a single monolithic
container, the stack is split into three cooperating services, each running
in its own container, built from its own hand-written Dockerfile:

- **NGINX** — the single entry point of the infrastructure, serving HTTPS
  (TLSv1.2/TLSv1.3 only) on port 443 and forwarding PHP requests to
  PHP-FPM.
- **WordPress + PHP-FPM** — the CMS and its FastCGI process manager,
  installed and configured (no web server bundled), listening on port 9000.
- **MariaDB** — the database engine backing WordPress, listening on port
  3306, reachable only from inside the Docker network.

The three containers communicate over a dedicated Docker bridge network and
share two persistent named volumes (one for the WordPress database, one for
the WordPress site files), both stored under `/home/elikavak/data` on the
host. All credentials are kept out of the Dockerfiles and out of the images,
using a `.env` file for non-sensitive configuration and Docker secrets for
passwords.

## Instructions

### Prerequisites

- A Debian (or Alpine) virtual machine with Docker Engine and the Docker
  Compose plugin installed.
- An entry in `/etc/hosts` (or local DNS) pointing `elikavak.42.fr` to the
  VM's own IP address, e.g.:
  ```
  127.0.0.1  elikavak.42.fr
  ```
- The `secrets/` directory at the project root, containing:
  - `secrets/db_root_password.txt`
  - `secrets/db_password.txt`
  - `secrets/credentials.txt` (`WORDPRESS_ADMIN_PASSWORD=...` and
    `WORDPRESS_USER_PASSWORD=...`)

  These files are intentionally **not** versioned in git (see
  `.gitignore`) and must be created locally before the first build.

### Running the project

From the project root:

```sh
make          # creates the data folders, builds the images and starts the stack
make down     # stops and removes the containers
make stop     # stops the containers without removing them
make start    # restarts previously stopped containers
make clean    # down + prune dangling Docker resources
make fclean   # clean + wipe the persistent data folders
make re       # fclean + all
```

Once the stack is up, the site is reachable at `https://elikavak.42.fr`
(self-signed certificate, browser warning expected).

See [USER_DOC.md](USER_DOC.md) and [DEV_DOC.md](DEV_DOC.md) for detailed
usage and development documentation.

## Project description

### Docker usage and project layout

```
.
├── Makefile                    # builds/starts/stops the stack via docker compose
├── secrets/                    # local-only credential files (gitignored)
└── srcs/
    ├── .env                    # non-sensitive configuration (domain, DB names, users)
    ├── docker-compose.yml      # services, network, volumes, secrets wiring
    └── requirements/
        ├── mariadb/            # Dockerfile + my.cnf + init script
        ├── wordpress/          # Dockerfile + php-fpm pool conf + install script
        └── nginx/              # Dockerfile + vhost conf + TLS cert generation script
```

Each service's Dockerfile is built from `debian:bookworm-slim` (the
penultimate stable Debian release), installs only what that service needs,
and hands off to a small shell script that finishes runtime configuration
(waiting for dependencies, generating certificates, creating the database,
installing WordPress) before `exec`-ing the real foreground process
(`mariadbd`, `php-fpm8.2 -F`, `nginx -g "daemon off;"`) as PID 1 — no
`tail -f`, `sleep infinity`, or similar hacks.

### Design choices and trade-offs

**Virtual Machine vs Docker** — The VM provides an isolated, disposable
machine with its own kernel, used here purely as the required host for
Docker. Docker containers, by contrast, share the host kernel and only
isolate the process/filesystem/network namespace, which makes them far
lighter and faster to start than a full VM. In this project the VM is the
outer boundary (one kernel, one IP, one `/etc/hosts` entry), while Docker
is the tool used *inside* it to run three independent, reproducible
services without giving each of them a full guest OS.

**Secrets vs Environment Variables** — Environment variables (`.env`) are
used for configuration that is not sensitive (domain name, database name,
usernames) and that is convenient to read directly in `docker-compose.yml`
and in the containers. They are, however, visible in `docker inspect`,
process listings, and image layers if baked in carelessly. Docker secrets
are used instead for passwords: they are mounted as read-only files under
`/run/secrets/<name>` only inside the containers that declare them, never
appear in `docker inspect`, and are never written into an image layer or a
Dockerfile, which is why every password in this project (root DB password,
DB user password, WordPress admin/user passwords) goes through `secrets/`
rather than `.env`.

**Docker Network vs Host Network** — `network: host` would make containers
share the host's network stack directly, exposing every listening port on
the VM and removing the isolation between services (and is explicitly
forbidden by the subject). This project instead defines a dedicated bridge
network (`inception`) so that containers can resolve and reach each other
by service name (`mariadb`, `wordpress`, `nginx`) while staying isolated
from the host network. Only NGINX publishes a port to the host (443), which
matches the requirement that NGINX be the sole entry point into the
infrastructure.

**Docker Volumes vs Bind Mounts** — A bind mount ties a container path
directly to an arbitrary host path with no lifecycle management by Docker.
Named volumes are managed by Docker itself (`docker volume ls/inspect/rm`)
and are the recommended way to persist stateful data such as a database or
a WordPress installation, independently of the container's lifecycle. The
subject requires named volumes for both persistent stores while also
requiring their data to live under `/home/elikavak/data` on the host; this
project reconciles both constraints by declaring named volumes
(`mariadb_data`, `wordpress_data`) with the `local` driver and
`driver_opts` pointing at that host path, so they remain real Docker
volumes (trackable and manageable through the Docker CLI) while their data
is stored exactly where the subject requires.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker secrets in Compose (non-Swarm)](https://docs.docker.com/compose/how-tos/use-secrets/)
- [MariaDB Server documentation](https://mariadb.com/kb/en/documentation/)
- [WP-CLI documentation](https://wp-cli.org/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [PHP-FPM configuration reference](https://www.php.net/manual/en/install.fpm.configuration.php)

### AI usage
