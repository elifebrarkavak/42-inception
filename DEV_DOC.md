# Developer Documentation

This document explains how to set up, build, and work on the Inception
project as a developer: environment setup, build/launch commands, container
and volume management, and where project data lives.

## 1. Setting up the environment from scratch

### Prerequisites

- A Debian (or Alpine) virtual machine.
- Docker Engine and the Docker Compose plugin (`docker compose version`
  should work).
- `make`.
- An `/etc/hosts` entry (or local DNS) resolving `elikavak.42.fr` to the
  VM's own IP address.

### Configuration files

| File                        | Purpose                                                        |
|------------------------------|------------------------------------------------------------------|
| `srcs/.env`                 | Non-sensitive configuration: domain, DB name/user, WP title, admin/user names & emails. Read by `docker-compose.yml` and injected into containers. |
| `srcs/docker-compose.yml`   | Defines the three services, the `inception` network, the two named volumes, and the Docker secrets wiring. |
| `srcs/requirements/<service>/Dockerfile` | One per service (`mariadb`, `wordpress`, `nginx`), each built from `debian:bookworm`. |
| `srcs/requirements/<service>/conf/`      | Service configuration copied into the image (MariaDB `50-server.cnf`, PHP-FPM `www.conf`, NGINX `nginx.conf`). |
| `srcs/requirements/<service>/tools/`     | Entrypoint shell scripts that finish runtime setup and then `exec` the real foreground process. |

### Secrets

Before the first build, create the `secrets/` folder at the project root
(sibling of `srcs/`, not inside it) with:

```
secrets/
├── db_root_password.txt     # single line, MariaDB root password
├── db_password.txt          # single line, WordPress DB user password
└── credentials.txt          # WORDPRESS_ADMIN_PASSWORD=...
                              # WORDPRESS_USER_PASSWORD=...
```

These files are referenced by `srcs/docker-compose.yml` under the top-level
`secrets:` key and mounted read-only at `/run/secrets/<name>` inside the
containers that declare them (`mariadb.sh`, `wordpress.sh` read them from
there). They are excluded from git via `.gitignore` (`secrets/*.txt`) and
must never be committed.

## 2. Building and launching the project

Everything is driven by the root `Makefile`, which wraps `docker compose
-f srcs/docker-compose.yml --env-file srcs/.env`:

```sh
make          # build (if needed) and start all services, detached
make build    # build the images only
make up       # (re)create and start the containers
make down     # stop and remove the containers (volumes kept)
make stop     # stop the containers, keep them for a later `make start`
make start    # restart previously stopped containers
make clean    # down + docker system prune -af
make fclean   # clean + remove the host data folders under $(DATA_PATH)
make re       # fclean + all (full rebuild from a clean state)
```

`make` (and `make build`/`make up`) first run the `data` target, which
creates `$(DATA_PATH)/mariadb` and `$(DATA_PATH)/wordpress` on the host —
these directories must exist before Docker can attach the named volumes to
them.

`DATA_PATH` is read directly from `srcs/.env` (`DATA_PATH=/home/elikavak/data`)
so the Makefile and the compose file always agree on the same value.

## 3. Managing containers and volumes

Common `docker`/`docker compose` commands used during development (run from
`srcs/`, or add `-f srcs/docker-compose.yml` from the project root):

```sh
docker compose -f srcs/docker-compose.yml ps          # container status
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml exec wordpress bash
docker compose -f srcs/docker-compose.yml exec mariadb bash

docker volume ls                                        # list named volumes
docker volume inspect srcs_mariadb_data                 # host path, driver, etc.
docker network inspect srcs_inception                    # containers on the network
```

Rebuilding a single service after editing its Dockerfile or scripts:

```sh
docker compose -f srcs/docker-compose.yml build wordpress
docker compose -f srcs/docker-compose.yml up -d wordpress
```

## 4. Where project data is stored and how it persists

Two Docker **named volumes** are declared in `srcs/docker-compose.yml`:

- `mariadb_data` → mounted at `/var/lib/mysql` in the `mariadb` container.
- `wordpress_data` → mounted at `/var/www/html` in both the `wordpress` and
  `nginx` containers (so NGINX can serve the WordPress files and PHP-FPM
  can write to them).

Both volumes use the `local` driver with `driver_opts` (`type: none`,
`o: bind`, `device: ${DATA_PATH}/...`) pointing at:

- `/home/elikavak/data/mariadb`
- `/home/elikavak/data/wordpress`

This keeps them true Docker-managed named volumes (visible via
`docker volume ls/inspect`, independent of any single container's
lifecycle) while satisfying the requirement that their data physically live
under `/home/elikavak/data` on the host.

Because the data lives in named volumes rather than inside the containers,
`make down` / `make stop` / rebuilding an image never loses data — only
`make fclean` (or manually removing the volumes/host folders) does, since
it explicitly deletes the `$(DATA_PATH)` directories.
