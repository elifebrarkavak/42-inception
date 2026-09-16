#!/bin/bash
set -e

WP_PATH=/var/www/html

DB_PASSWORD=$(cat /run/secrets/db_password)
WORDPRESS_ADMIN_PASSWORD=$(grep '^WORDPRESS_ADMIN_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)
WORDPRESS_USER_PASSWORD=$(grep '^WORDPRESS_USER_PASSWORD=' /run/secrets/credentials | cut -d '=' -f2-)

ADMIN_USER_LOWER=$(echo "${WORDPRESS_ADMIN_USER}" | tr '[:upper:]' '[:lower:]')
case "${ADMIN_USER_LOWER}" in
	*admin*)
		echo "[wordpress.sh] WORDPRESS_ADMIN_USER 'admin' veya 'administrator' iceremez." >&2
		exit 1
		;;
esac

echo "[wordpress.sh] MariaDB bekleniyor..."
until mysqladmin ping -h "mariadb" -u "${MYSQL_USER}" -p"${DB_PASSWORD}" --silent > /dev/null 2>&1; do
	sleep 2
done
echo "[wordpress.sh] MariaDB hazir."

if [ ! -f "${WP_PATH}/wp-load.php" ]; then
	echo "[wordpress.sh] WordPress dosyalari indiriliyor..."
	wp core download --path="${WP_PATH}" --allow-root
fi

if [ ! -f "${WP_PATH}/wp-config.php" ]; then
	echo "[wordpress.sh] wp-config.php olusturuluyor..."
	wp config create \
		--path="${WP_PATH}" \
		--dbname="${MYSQL_DATABASE}" \
		--dbuser="${MYSQL_USER}" \
		--dbpass="${DB_PASSWORD}" \
		--dbhost="mariadb:3306" \
		--allow-root
fi

if ! wp core is-installed --path="${WP_PATH}" --allow-root > /dev/null 2>&1; then
	echo "[wordpress.sh] WordPress kuruluyor..."
	wp core install \
		--path="${WP_PATH}" \
		--url="https://${DOMAIN_NAME}" \
		--title="${WORDPRESS_TITLE}" \
		--admin_user="${WORDPRESS_ADMIN_USER}" \
		--admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
		--admin_email="${WORDPRESS_ADMIN_EMAIL}" \
		--skip-email \
		--allow-root

	echo "[wordpress.sh] Ikinci kullanici olusturuluyor..."
	wp user create "${WORDPRESS_USER}" "${WORDPRESS_USER_EMAIL}" \
		--path="${WP_PATH}" \
		--role=author \
		--user_pass="${WORDPRESS_USER_PASSWORD}" \
		--allow-root
else
	echo "[wordpress.sh] WordPress zaten kurulu, kurulum atlaniyor."
fi

chown -R www-data:www-data "${WP_PATH}"

echo "[wordpress.sh] PHP-FPM baslatiliyor..."
exec php-fpm8.2 -F
