# User Documentation

This document explains, from an end-user / administrator point of view, how
to use the Inception stack: what it provides, how to start and stop it, how
to reach the site and its admin panel, where credentials live, and how to
verify that everything is healthy.

## 1. What services this stack provides

The project runs three containers on a private Docker network
(`inception`):

| Container   | Role                                          | Reachable from host? |
|-------------|-----------------------------------------------|-----------------------|
| `nginx`     | HTTPS reverse proxy / web server (TLS 1.2/1.3)| Yes, port `443` only  |
| `wordpress` | WordPress site + PHP-FPM                      | No (internal only)    |
| `mariadb`   | MySQL-compatible database for WordPress       | No (internal only)    |

`nginx` is the **only** entry point into the infrastructure. All traffic to
the WordPress site and its admin panel goes through it over HTTPS.

## 2. Starting and stopping the project

All commands are run from the project root (where the `Makefile` is).

```sh
make          # first-time setup / (re)build images and start all containers
make start    # resume containers that were stopped with `make stop`
make stop     # stop the containers without deleting them
make down     # stop and remove the containers (data volumes are kept)
```

To fully reset the project (containers, images, and stored data):

```sh
make fclean
make          # rebuild from scratch
```

## 3. Accessing the website and the administration panel

- **Website:** `https://elikavak.42.fr`
- **Admin panel:** `https://elikavak.42.fr/wp-admin`

The domain must resolve to the virtual machine's own IP address (an entry
in `/etc/hosts` is normally used for this — see `README.md`). The
certificate served by NGINX is self-signed, so browsers will show a
security warning on first visit; this is expected for this project and can
be safely bypassed ("Advanced" → "Proceed").

Two WordPress accounts are created automatically the first time the stack
starts:

- An **administrator** account (username from `WORDPRESS_ADMIN_USER` in
  `srcs/.env`) — full access, including `/wp-admin`.
- A regular **author** account (username from `WORDPRESS_USER` in
  `srcs/.env`) — can write and manage its own posts, no admin access.

## 4. Locating and managing credentials

Non-sensitive configuration (domain name, database name, usernames,
site title) lives in `srcs/.env` and can be read directly.

All passwords live in the `secrets/` folder at the project root and are
**never** committed to git:

| File                             | Contains                                   |
|-----------------------------------|---------------------------------------------|
| `secrets/db_root_password.txt`    | MariaDB root password                       |
| `secrets/db_password.txt`         | Password for the WordPress database user    |
| `secrets/credentials.txt`         | `WORDPRESS_ADMIN_PASSWORD=...` and `WORDPRESS_USER_PASSWORD=...` |

To change a password, edit the relevant file in `secrets/` and recreate the
containers so the new value is picked up:

```sh
make down
make
```

Note: passwords are only applied at first install. If WordPress or the
database has already been initialized, changing a secret file will not
retroactively change the live password — the corresponding change also
needs to be made through `wp-cli`/the admin panel, or the stack needs to be
reset with `make fclean` for a clean re-install.

## 5. Checking that the services are running correctly

Check that all three containers are up and marked healthy/running:

```sh
docker ps
```

You should see `nginx`, `wordpress`, and `mariadb`, all with status `Up`.

Check the logs of a specific service if something looks wrong:

```sh
docker logs nginx
docker logs wordpress
docker logs mariadb
```

Finally, confirm the site itself responds:

```sh
curl -vk https://elikavak.42.fr
```

A successful TLS handshake followed by an HTML response indicates that
NGINX, PHP-FPM/WordPress, and MariaDB are all working together correctly.
