#!/bin/bash
set -e

WP_PATH=/var/www/html

DB_PASSWORD=$(cat /run/secrets/db_password)
WORDPRESS_ADMIN_PASSWORD=$(grep '^WORDPRESS_ADMIN_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)
WORDPRESS_USER_PASSWORD=$(grep '^WORDPRESS_USER_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)

if echo "${WORDPRESS_ADMIN_USER}" | grep -qi admin; then
	echo "[wordpress.sh] WORDPRESS_ADMIN_USER 'admin' iceremez." >&2
	exit 1
fi

until mysqladmin ping -h mariadb -u "${MYSQL_USER}" -p"${DB_PASSWORD}" --silent >/dev/null 2>&1; do
	sleep 2
done

[ -f "${WP_PATH}/wp-load.php" ] || wp core download --path="${WP_PATH}" --allow-root

[ -f "${WP_PATH}/wp-config.php" ] || wp config create --path="${WP_PATH}" --dbname="${MYSQL_DATABASE}" \
	--dbuser="${MYSQL_USER}" --dbpass="${DB_PASSWORD}" --dbhost="mariadb:3306" --allow-root

if ! wp core is-installed --path="${WP_PATH}" --allow-root >/dev/null 2>&1; then
	wp core install --path="${WP_PATH}" --url="https://${DOMAIN_NAME}" --title="${WORDPRESS_TITLE}" \
		--admin_user="${WORDPRESS_ADMIN_USER}" --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
		--admin_email="${WORDPRESS_ADMIN_EMAIL}" --skip-email --allow-root

	wp user create "${WORDPRESS_USER}" "${WORDPRESS_USER_EMAIL}" --path="${WP_PATH}" \
		--role=author --user_pass="${WORDPRESS_USER_PASSWORD}" --allow-root
fi

chown -R www-data:www-data "${WP_PATH}"
exec php-fpm8.2 -F
