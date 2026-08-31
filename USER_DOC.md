# User documentation

This document is for anyone who wants to **run and use** the Inception stack: an end user
visiting the website, or an administrator operating it. No knowledge of Docker internals is
required. If you want to modify the project, read [DEV_DOC.md](DEV_DOC.md) instead.

---

## 1. What this stack provides

Starting the project gives you a complete, self-hosted **WordPress website served over
HTTPS**. Three services run behind it, each in its own container:

| Service | What it does for you | How you interact with it |
| ------- | -------------------- | ------------------------ |
| **nginx** | The web server. It is the front door: it handles HTTPS, serves images and stylesheets, and passes everything else to WordPress. | Directly — this is what your browser talks to, at `https://elikavak.42.fr`. |
| **wordpress** | The website itself: WordPress running on PHP-FPM. It builds every page and stores your posts, pages and media. | Indirectly, through the browser and the `/wp-admin` panel. |
| **mariadb** | The database. It stores posts, pages, comments, settings and user accounts. | You normally never touch it. It has no web interface. |

Two things are worth knowing up front:

- **Only NGINX is reachable from outside.** It listens on port `443` (HTTPS) and nothing else
  is published. There is no HTTP on port 80, and the database is not reachable from your
  machine at all. This is intentional.
- **Your data is safe across restarts.** Posts, media and the database live in two storage
  volumes on the host machine, not inside the containers. Stopping or even rebuilding the
  stack does not delete them. Only one command does, and it is documented in section 6.

---

## 2. Before the first start

Three things must be in place. They are done once, not every time.

### 2.1 The domain name must resolve

The site answers to `elikavak.42.fr`, which is a local-only name. Tell the machine where to
find it:

```bash
echo "127.0.0.1 elikavak.42.fr" | sudo tee -a /etc/hosts
```

Check it worked:

```bash
getent hosts elikavak.42.fr
```

You should see `127.0.0.1  elikavak.42.fr`.

### 2.2 The configuration file must exist

```bash
cp srcs/.env.example srcs/.env
```

`srcs/.env` holds non-secret settings: the domain, the database name, the site title, the
usernames. You can edit it, but the defaults work.

### 2.3 The passwords must exist

Passwords are kept in separate files in the `secrets/` directory and are deliberately **not**
part of the repository. Create them with your own values:

```bash
printf '%s' 'choose-a-db-root-password' > secrets/db_root_password.txt
```

```bash
printf '%s' 'choose-a-db-user-password' > secrets/db_password.txt
```

```bash
printf 'WP_ADMIN_PASSWORD=choose-an-admin-password\nWP_USER_PASSWORD=choose-a-user-password\n' > secrets/credentials.txt
```

```bash
chmod 600 secrets/*.txt
```

> **Use `printf`, not `echo`.** `echo` adds a newline at the end of the file, and that newline
> would become part of the password — leaving you unable to log in.

---

## 3. Starting and stopping

All commands are run from the **root of the repository**.

### Start everything

```bash
make
```

The first run takes several minutes: it builds the three images, installs the packages, and
downloads and configures WordPress. Later starts take a few seconds.

The stack is ready when `make ps` shows all three services as `running` (see section 5).

### Stop everything

```bash
make down
```

This stops and removes the containers. **Your website and database are kept.** Run `make`
again and everything comes back exactly as it was.

### Restart after a change

```bash
make re
```

Rebuilds the images from scratch and restarts the stack. Data is kept.

### The full list

| Command | What it does | Data |
| ------- | ------------ | ---- |
| `make` | Build the images and start the stack. | Kept |
| `make down` | Stop and remove the containers. | Kept |
| `make stop` | Pause the containers without removing them. | Kept |
| `make start` | Resume containers stopped with `make stop`. | Kept |
| `make re` | Rebuild everything and restart. | Kept |
| `make logs` | Follow the live logs of all services. | Kept |
| `make ps` | Show the state of the containers. | Kept |
| `make clean` | Remove containers and images, keep the volumes. | Kept |
| `make fclean` | Remove containers, images, volumes **and host data**. | **Destroyed** |

---

## 4. Using the website

### The public site

Open **https://elikavak.42.fr** in a browser.

> **Expected: a certificate warning.** The certificate is self-signed, because `elikavak.42.fr`
> is a local domain that no public certificate authority can vouch for. Click *Advanced* and
> proceed. This is normal for this project and does not mean the connection is unencrypted —
> traffic is still protected by TLSv1.2 or TLSv1.3.

Note that **`http://` will not work** and this is by design: port 80 is not published, and
port `443` is the only entry point into the infrastructure.

### The administration panel

Open **https://elikavak.42.fr/wp-admin** and sign in.

Two accounts exist, created automatically on first start:

| Account | Role | What it can do |
| ------- | ---- | -------------- |
| `elikavak` | Administrator | Everything: themes, plugins, settings, users, content. |
| `redactor` | Author | Write, edit and publish its own posts. Cannot change site settings. |

The administrator username deliberately contains no form of the word *admin* — the subject
forbids it, and it is also a real hardening measure, since `admin` is the first name every
brute-force script tries.

---

## 5. Checking that everything works

### Are the containers running?

```bash
make ps
```

All three services should show state `running` (or `Up`). A service stuck in `restarting` is
crash-looping — see section 7.

### Is the site answering over HTTPS?

```bash
curl -kI https://elikavak.42.fr
```

`HTTP/1.1 200 OK` means NGINX is up and WordPress is responding. The `-k` flag tells `curl` to
accept the self-signed certificate.

### Is TLS correctly restricted?

TLSv1.2 and TLSv1.3 must be accepted:

```bash
openssl s_client -connect elikavak.42.fr:443 -tls1_2 </dev/null
```

TLSv1.1 and below must be refused:

```bash
openssl s_client -connect elikavak.42.fr:443 -tls1_1 </dev/null
```

The first should complete a handshake and print certificate details. The second must fail with
a protocol or alert error — that failure is the correct result.

### Is the database reachable by WordPress?

```bash
docker exec -it mariadb mariadb -u root -p -e "SHOW DATABASES;"
```

Enter the root password from `secrets/db_root_password.txt`. You should see the `wordpress`
database in the list.

### Is the data really persistent?

```bash
ls -la /home/elikavak/data/wordpress /home/elikavak/data/mariadb
```

The first directory contains the WordPress files (`wp-config.php`, `wp-content`, …). The second
contains the MariaDB data files. If both have content, persistence is working.

### What are the services saying?

```bash
make logs
```

Press `Ctrl+C` to stop following. For one service only:

```bash
docker compose -f srcs/docker-compose.yml logs -f wordpress
```

---

## 6. Where the credentials live

| Credential | File | Used by |
| ---------- | ---- | ------- |
| MariaDB root password | `secrets/db_root_password.txt` | Database administration only. |
| WordPress database password | `secrets/db_password.txt` | WordPress, to connect to MariaDB. |
| WordPress account passwords | `secrets/credentials.txt` | The two `/wp-admin` accounts. |
| Usernames, domain, database name | `srcs/.env` | Everything. Non-secret. |

Three rules:

1. **Never commit them.** `secrets/*.txt` and `srcs/.env` are listed in `.gitignore`. The
   subject fails any project with credentials in its Git repository, and there is no way to
   remove a password from Git history cleanly once it has been pushed.
2. **Restrict the permissions.** `chmod 600 secrets/*.txt` — readable only by you.
3. **Changing a password is not just editing the file.** The values are read when a service is
   first initialised, so editing the file afterwards does not change the running system:
   - **WordPress account passwords** — change them in `/wp-admin` under *Users*, then update
     `secrets/credentials.txt` so it stays accurate.
   - **Database passwords** — these were written into the database and into `wp-config.php` at
     initialisation. Changing them means either altering the database user by hand, or
     rebuilding from scratch with `make fclean && make` — which **destroys all data**. Choose
     your passwords carefully the first time.

### Destroying everything on purpose

```bash
make fclean
```

This removes the containers, the images, the volumes, and the contents of
`/home/elikavak/data`. The website and the database are gone permanently. It is the right
command when you want a genuinely clean start; it is never the right command when you just want
to stop the stack — use `make down` for that.

---

## 7. Troubleshooting

| Symptom | Likely cause | What to do |
| ------- | ------------ | ---------- |
| The browser cannot find `elikavak.42.fr` | The `/etc/hosts` entry is missing. | Redo section 2.1 and check with `getent hosts elikavak.42.fr`. |
| "Your connection is not private" | Self-signed certificate. | Expected. Click *Advanced* and proceed. |
| `502 Bad Gateway` | NGINX is up but cannot reach PHP-FPM. | The `wordpress` container is still starting or has crashed. Check `docker compose -f srcs/docker-compose.yml logs wordpress`. |
| "Error establishing a database connection" | MariaDB is not ready, or the password does not match. | Check the `mariadb` logs. If you edited a secret file after the first start, the values no longer match — see section 6. |
| A container restarts in a loop | The service crashes at startup. | Read its logs; the last lines before each restart hold the reason. |
| `port is already allocated` | Something else on the host uses port 443. | `sudo ss -tlnp \| grep :443` to find it, then stop it. |
| `make` fails on `/home/elikavak/data` | The directory cannot be created. | Check that the path matches your username, and that you have write access to your home directory. |
| Changes to a config file have no effect | The image still holds the old copy. | Configuration is baked into the images at build time. Run `make re`. |

If a problem is not listed here, start with the logs — they name the failing service and almost
always the reason:

```bash
make logs
```
