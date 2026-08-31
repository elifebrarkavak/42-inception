# Developer documentation

This document is for anyone who wants to **build, modify or debug** the Inception stack. It
covers setting up the environment from scratch, how the build works, how to manage containers
and volumes, and where the data lives. For simply running and using the site, see
[USER_DOC.md](USER_DOC.md).

---

## 1. Prerequisites

The whole project runs **inside a virtual machine**, as the subject requires. On that VM:

| Requirement | Minimum | Check |
| ----------- | ------- | ----- |
| Linux (Debian or Ubuntu recommended) | — | `uname -a` |
| Docker Engine | 20.10 | `docker --version` |
| Docker Compose plugin (v2) | 2.0 | `docker compose version` |
| GNU Make | 4.x | `make --version` |
| Git, OpenSSL, curl | — | `git --version`, `openssl version` |
| Free disk space | ~3 GB | `df -h /var/lib/docker` |

Your user must be in the `docker` group, otherwise every command needs `sudo`:

```bash
sudo usermod -aG docker $USER
```

Log out and back in for the group change to apply.

> Note the version pinning constraint that runs through the whole project: images are built
> `FROM debian:bookworm`. Debian 13 *trixie* is the current stable release, so bookworm is the
> **penultimate stable** version required by the subject. The `latest` tag is forbidden
> everywhere. If Debian promotes a new stable release, this pin has to be re-evaluated.

---

## 2. Repository layout

```text
.
├── Makefile                       # single entry point: build, run, clean
├── README.md                      # project overview and design rationale
├── USER_DOC.md                    # user / operator documentation
├── DEV_DOC.md                     # this file
├── .gitignore                     # excludes .env and secrets/*.txt
├── secrets/                       # credentials — NOT in Git
│   ├── credentials.txt            # WordPress account passwords
│   ├── db_password.txt            # WordPress database user password
│   ├── db_root_password.txt       # MariaDB root password
│   └── *.example                  # committed templates
└── srcs/
    ├── .env                       # non-secret configuration — NOT in Git
    ├── .env.example               # committed template
    ├── docker-compose.yml         # services, network, volumes, secrets
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/50-server.cnf         # bind address, skip-networking off
        │   └── tools/init-db.sh           # entrypoint: init, create DB + user
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/nginx.conf            # TLS 1.2/1.3, FastCGI to wordpress:9000
        │   └── tools/gen-cert.sh          # self-signed certificate, build time
        └── wordpress/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/www.conf              # PHP-FPM pool, listens on 0.0.0.0:9000
            └── tools/setup-wordpress.sh   # entrypoint: WP-CLI install, users
```

The layout mirrors the structure the subject prescribes: everything needed to configure the
project is under `srcs/`, the `Makefile` is at the root, and each service owns its own
directory with a `Dockerfile`, a `conf/` and a `tools/`.

---

## 3. Setting up from scratch

### 3.1 Clone

```bash
git clone <repository-url> inception && cd inception
```

### 3.2 Resolve the domain

```bash
echo "127.0.0.1 elikavak.42.fr" | sudo tee -a /etc/hosts
```

### 3.3 Create the configuration

```bash
cp srcs/.env.example srcs/.env
```

`srcs/.env` contains only non-sensitive values. Compose reads it automatically because it sits
next to `docker-compose.yml`:

```ini
# Domain and paths
DOMAIN_NAME=elikavak.42.fr
DATA_PATH=/home/elikavak/data

# Database
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
MYSQL_HOST=mariadb

# WordPress site
WP_TITLE=Inception
WP_URL=https://elikavak.42.fr

# WordPress accounts (passwords live in secrets/, never here)
WP_ADMIN_USER=elikavak
WP_ADMIN_EMAIL=elikavak@student.42.fr
WP_USER=redactor
WP_USER_EMAIL=redactor@student.42.fr
```

> `WP_ADMIN_USER` must not contain `admin`, `Admin`, `administrator` or `Administrator`. The
> subject rejects the project otherwise.

### 3.4 Create the secrets

```bash
printf '%s' 'your-db-root-password' > secrets/db_root_password.txt
```

```bash
printf '%s' 'your-db-user-password' > secrets/db_password.txt
```

```bash
printf 'WP_ADMIN_PASSWORD=your-admin-password\nWP_USER_PASSWORD=your-user-password\n' > secrets/credentials.txt
```

```bash
chmod 600 secrets/*.txt
```

`printf` rather than `echo`: a trailing newline becomes part of the password. Entrypoint scripts
read these files with `$(cat /run/secrets/<name>)`, which strips trailing newlines — but the
value written into MariaDB at initialisation may not be stripped the same way, so it is simpler
never to write the newline in the first place.

### 3.5 Verify nothing secret is tracked

Before the first commit, and before every push:

```bash
git status --porcelain --ignored | grep -E '(\.env|secrets/)'
```

Every match must be marked `!!` (ignored), never `A`, `M` or `??`. `.gitignore` contains:

```gitignore
srcs/.env
secrets/*.txt
!secrets/*.example
```

If a credential was ever committed, rewriting history is the only fix — and the subject fails
the project for credentials found in the repository. Check before you push, not after.

### 3.6 Build and start

```bash
make
```

---

## 4. How the build works

### 4.1 The Makefile

The `Makefile` is the only supported entry point. It never contains business logic; it wraps
`docker compose` and prepares the host.

| Target | Underlying command | Notes |
| ------ | ------------------ | ----- |
| `all` | `dirs` then `up` | Default target. |
| `dirs` | `mkdir -p $(DATA_PATH)/{wordpress,mariadb}` | **Required before `up`.** The named volumes are bound to these paths; if they do not exist, Compose fails to mount. |
| `build` | `docker compose -f srcs/docker-compose.yml build` | |
| `up` | `docker compose ... up -d --build` | |
| `down` | `docker compose ... down` | Containers removed, volumes kept. |
| `stop` / `start` | `docker compose ... stop` / `start` | |
| `logs` | `docker compose ... logs -f` | |
| `ps` | `docker compose ... ps` | |
| `clean` | `down --rmi all` | Images removed, volumes kept. |
| `fclean` | `down -v --rmi all` then `rm -rf $(DATA_PATH)/*` | **Destroys all data.** |
| `re` | `fclean`-free rebuild: `down` then `up --build` | Data kept. |

All targets are declared `.PHONY` — they produce no file of that name, and without it a
directory called `build` would silently make the target a no-op.

### 4.2 The Compose file

`srcs/docker-compose.yml` declares three services, one network, two volumes, three secrets.

The parts that matter for the subject:

- **`image:` matches the service name.** `image: nginx`, `image: wordpress`, `image: mariadb` —
  the subject requires each image to be named after its service. Combined with `build:`, Compose
  builds the image and tags it with that name.
- **No `version:` key.** It is obsolete in Compose v2 and produces a warning.
- **`networks:` is declared explicitly.** The subject requires the network line to be present;
  relying on Compose's implicit default network would not satisfy it.
- **Only `nginx` has `ports:`.** The other two use `expose:`, which documents the port and makes
  it reachable on the network without publishing it to the host.
- **`restart: unless-stopped`** on all three.
- **`depends_on:`** orders startup — `nginx` after `wordpress`, `wordpress` after `mariadb`.
  Note that this only orders *container start*, not *service readiness*: MariaDB accepting
  connections is handled by a wait loop in the WordPress entrypoint, not by Compose.

### 4.3 The images

All three are `FROM debian:bookworm`, install their package from the Debian repositories, copy
their configuration, and end with a foreground process.

| Service | Package | Final process (PID 1) |
| ------- | ------- | --------------------- |
| `nginx` | `nginx`, `openssl` | `nginx -g "daemon off;"` |
| `wordpress` | `php8.2-fpm`, `php8.2-mysql`, `curl` + WP-CLI | `php-fpm8.2 -F` |
| `mariadb` | `mariadb-server` | `mariadbd` |

Each Dockerfile follows the same shape:

```dockerfile
FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends <packages> \
    && rm -rf /var/lib/apt/lists/*

COPY conf/<file> <destination>
COPY tools/<script>.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/<script>.sh

EXPOSE <port>
ENTRYPOINT ["<script>.sh"]
CMD ["<daemon>", "<foreground-flag>"]
```

Three details are deliberate and worth being able to defend:

1. **`rm -rf /var/lib/apt/lists/*` in the same `RUN`.** A separate `RUN` would not shrink the
   image: the previous layer already contains the files, and layers are immutable.
2. **`ENTRYPOINT` in exec form, daemon in `CMD`.** The entrypoint script does setup and then
   runs `exec "$@"`, replacing itself with the `CMD`. The daemon therefore becomes PID 1 and
   receives `SIGTERM` from `docker stop` directly. Shell form (`ENTRYPOINT script.sh`) would
   wrap it in `/bin/sh -c`, which does not forward signals — the container would take the full
   10-second timeout and then be `SIGKILL`ed.
3. **No password anywhere.** No `ENV PASSWORD=`, no `ARG`. Layers are permanent and inspectable
   with `docker history`; a password baked into one is a password published.

### 4.4 The entrypoints

Every entrypoint is **idempotent**: it must be safe to run on an empty volume *and* on a volume
that already contains data, because containers are recreated on every `make re` while the
volumes persist.

**`mariadb/tools/init-db.sh`**

1. If `/var/lib/mysql/mysql` exists, the database is already initialised — skip to step 5.
2. Run `mariadb-install-db` to create the system tables.
3. Start a temporary server bound to a local socket only.
4. Create the database and the WordPress user, set the root password, drop the anonymous users
   — reading the passwords from `/run/secrets/`.
5. Shut the temporary server down cleanly and `exec "$@"` to start the real one.

**`wordpress/tools/setup-wordpress.sh`**

1. Wait for `mariadb:3306` to accept connections. This is a **bounded** loop — a fixed number of
   attempts with a `sleep` between them, then exit with an error. It is not `while true`, which
   the subject forbids, and failing loudly is better than hanging forever.
2. If `wp-config.php` exists, WordPress is installed — skip to step 5.
3. `wp core download`, then `wp config create` with the values from the environment and the
   secrets.
4. `wp core install`, then `wp user create` for the second, non-administrator account.
5. Fix ownership to `www-data`, then `exec "$@"`.

**`nginx/tools/gen-cert.sh`** — generates the self-signed certificate for `$DOMAIN_NAME` if it
is not already present, then `exec "$@"`.

### 4.5 Service configuration

- **`nginx/conf/nginx.conf`** — one `server` block listening on `443 ssl`, with
  `ssl_protocols TLSv1.2 TLSv1.3;`, root `/var/www/html`, `index index.php`, and a
  `location ~ \.php$` block forwarding to `fastcgi_pass wordpress:9000;`. No `listen 80`.
- **`wordpress/conf/www.conf`** — the PHP-FPM pool must listen on `listen = 0.0.0.0:9000`, not
  on the default Unix socket. A socket exists only inside its own container's filesystem, so
  NGINX in a *different* container could never reach it.
- **`mariadb/conf/50-server.cnf`** — `bind-address = 0.0.0.0` so the server accepts connections
  from the Docker network. Debian's default binds to `127.0.0.1`, which would make the database
  unreachable from the `wordpress` container.

---

## 5. Managing containers and volumes

Compose commands need the file path, since it is not in the repository root. Set a shell alias
for convenience:

```bash
alias dc='docker compose -f srcs/docker-compose.yml'
```

### Containers

```bash
docker compose -f srcs/docker-compose.yml ps
```

```bash
docker compose -f srcs/docker-compose.yml logs -f wordpress
```

Open a shell inside a running container:

```bash
docker exec -it wordpress bash
```

Rebuild and restart a single service without touching the others:

```bash
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate nginx
```

Confirm the daemon really is PID 1:

```bash
docker exec nginx ps -eo pid,comm
```

The output must show the daemon at PID 1, not a shell.

### Network

```bash
docker network inspect srcs_inception
```

Compose prefixes the network with the project name, which defaults to the directory containing
the Compose file — hence `srcs_`. Verify DNS resolution between containers:

```bash
docker exec wordpress getent hosts mariadb
```

Verify the isolation the subject requires — nothing but 443 on the host:

```bash
sudo ss -tlnp | grep -E ':(443|3306|9000)'
```

Only `443` should appear.

### Volumes

```bash
docker volume ls
```

```bash
docker volume inspect srcs_wordpress_data
```

The `Mountpoint` in the output confirms the volume is backed by `/home/elikavak/data/wordpress`
rather than by Docker's internal directory.

Removing volumes requires the containers to be gone first:

```bash
docker compose -f srcs/docker-compose.yml down -v
```

### Database

```bash
docker exec -it mariadb mariadb -u root -p
```

Back up and restore:

```bash
docker exec mariadb mariadb-dump -u root -p"$(cat secrets/db_root_password.txt)" wordpress > backup.sql
```

```bash
docker exec -i mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" wordpress < backup.sql
```

> Passing a password on a command line makes it visible in the host's process list. It is
> acceptable for a one-off local backup; do not put it in a script that others run.

### WP-CLI

```bash
docker exec -it wordpress wp --allow-root --path=/var/www/html user list
```

`--allow-root` is needed because the container's shell is root. WP-CLI refuses to run as root
without it, as a safety measure against accidentally writing root-owned files into the volume.

---

## 6. Where the data lives, and how it persists

### The two volumes

| Volume | Mounted at | Host path | Owner |
| ------ | ---------- | --------- | ----- |
| `mariadb_data` | `/var/lib/mysql` | `/home/elikavak/data/mariadb` | `mariadb` only |
| `wordpress_data` | `/var/www/html` | `/home/elikavak/data/wordpress` | `wordpress` (read/write), `nginx` (read) |

Both are declared as **named volumes**, as the subject requires — bind mounts are not allowed
for these two stores. The subject *also* requires the data to sit in `/home/elikavak/data`. Both
constraints are met by giving the named volume a `local` driver pointed at a host directory:

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/elikavak/data/wordpress
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/elikavak/data/mariadb
```

This is a genuine Docker-managed named volume: it has a name and a lifecycle, it appears in
`docker volume ls`, and Compose refers to it by name. `driver_opts` only tells the local driver
where to keep the bytes.

The host directories **must exist before `docker compose up`** — the local driver does not
create them. That is exactly what `make dirs` is for.

### What survives what

| Action | Containers | Images | Volumes | Host data |
| ------ | ---------- | ------ | ------- | --------- |
| `make down` | Removed | Kept | Kept | **Kept** |
| `make re` | Rebuilt | Rebuilt | Kept | **Kept** |
| `make clean` | Removed | Removed | Kept | **Kept** |
| `make fclean` | Removed | Removed | Removed | **Deleted** |

The practical consequence: `make re` is safe to run at any time. `make fclean` is the only
destructive command, and it is the one to use when testing that a first-run installation works
from nothing — which is worth doing before the defense, since an evaluator will start from an
empty machine.

### Shared ownership of the WordPress volume

`wordpress_data` is mounted by two containers, and this is the most common source of subtle
bugs in this project. WordPress writes uploads as `www-data`; NGINX reads them as `www-data`.
Both Debian images use the same `www-data` uid/gid (`33`), so the ownership is consistent — but
only because both are built from the same base. Changing the base image of one service without
the other would break file access in ways that look like random 403 and 404 errors.

The WordPress entrypoint therefore ends its install step with:

```bash
chown -R www-data:www-data /var/www/html
```

---

## 7. Debugging checklist

Work down this list; it is ordered by how often each cause is the real one.

1. **Read the logs first.** `make logs`, or per service. Almost every failure names itself.
2. **A container restart-loops.** Its PID 1 exited. Run the image interactively to see why:
   ```bash
   docker run --rm -it --entrypoint bash wordpress
   ```
3. **`502 Bad Gateway`.** NGINX cannot reach PHP-FPM. Check that `www.conf` has
   `listen = 0.0.0.0:9000` and not a Unix socket, and that `fastcgi_pass` points at
   `wordpress:9000`.
4. **"Error establishing a database connection".** Either MariaDB is not ready yet, or the
   credentials do not match. Secrets are consumed at *initialisation*: editing a secret file
   after the first successful start changes nothing in the running system, and the mismatch
   surfaces here. `make fclean && make` resets it, at the cost of all data.
5. **A configuration change has no effect.** Configuration is copied into the image at build
   time, not mounted. `make re`.
6. **`port is already allocated`.** `sudo ss -tlnp | grep :443`.
7. **Volume mount fails at startup.** The host directory does not exist. `make dirs`, or check
   that `DATA_PATH` in `.env` matches your actual username.
8. **Permission denied on uploads.** Ownership drift on `wordpress_data`:
   ```bash
   docker exec wordpress chown -R www-data:www-data /var/www/html
   ```

---

## 8. Self-review before the defense

Each line is a requirement taken directly from the subject.

**Structure**

- [ ] `Makefile` at the root; all configuration under `srcs/`.
- [ ] One `Dockerfile` per service, under `srcs/requirements/<service>/`.
- [ ] `README.md`, `USER_DOC.md` and `DEV_DOC.md` present at the root, in Markdown.
- [ ] `README.md` starts with the italicised attribution line, and is written in English.

**Images and containers**

- [ ] Every image is built from `debian:bookworm`; nothing is pulled from Docker Hub except the
      base image.
- [ ] No `latest` tag anywhere.
- [ ] Each image is named after its service.
- [ ] One service per container.
- [ ] No `tail -f`, `sleep infinity`, `while true` or `bash` as a container command, in a
      `CMD`, an `ENTRYPOINT`, or inside an entrypoint script.
- [ ] The real daemon is PID 1 in each container — verify with `docker exec <svc> ps -eo pid,comm`.
- [ ] `restart:` is set on all three services.

**Network**

- [ ] `networks:` is declared explicitly in `docker-compose.yml`.
- [ ] No `network_mode: host`, no `links:`, no `--link`.
- [ ] Only `nginx` publishes a port, and only `443`.
- [ ] NGINX accepts TLSv1.2 and TLSv1.3, and refuses everything below.
- [ ] `elikavak.42.fr` resolves to the local address.

**Volumes**

- [ ] Two named volumes, one for the database and one for the site files.
- [ ] No bind mount is used for those two stores.
- [ ] Both are backed by `/home/elikavak/data`.
- [ ] Data survives `make down` followed by `make`.

**Secrets**

- [ ] No password in any Dockerfile.
- [ ] Environment variables are used, and `srcs/.env` exists.
- [ ] Credentials are in Docker secrets, read from `/run/secrets/`.
- [ ] `git log -p | grep -i -E 'password|secret'` finds nothing real, in the whole history.
- [ ] `srcs/.env` and `secrets/*.txt` are ignored by Git.

**WordPress**

- [ ] Two users exist, one administrator and one not.
- [ ] The administrator's username contains no form of `admin`.
- [ ] `wp-admin` is reachable and login works for both accounts.

**End to end**

- [ ] `make fclean && make` produces a working site from a completely empty machine.
