#!/bin/bash
set -e

DATADIR=/var/lib/mysql
SOCKET=/run/mysqld/mysqld.sock

DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

mkdir -p /run/mysqld "$DATADIR"
chown -R mysql:mysql /run/mysqld "$DATADIR"

if [ ! -d "$DATADIR/mysql" ]; then
	echo "[mariadb.sh] No existing database found, initializing..."

	mariadb-install-db \
		--user=mysql \
		--datadir="$DATADIR" \
		--auth-root-authentication-method=normal \
		> /dev/null

	echo "[mariadb.sh] Starting temporary server to apply initial setup..."
	mariadbd --user=mysql --datadir="$DATADIR" --socket="$SOCKET" --skip-networking &
	TMP_PID=$!

	for i in $(seq 1 30); do
		if mariadb-admin --socket="$SOCKET" ping > /dev/null 2>&1; then
			break
		fi
		sleep 1
	done

	mariadb --socket="$SOCKET" -u root <<-EOSQL
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
		CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
		CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
		GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
		FLUSH PRIVILEGES;
	EOSQL

	echo "[mariadb.sh] Stopping temporary server..."
	mariadb-admin --socket="$SOCKET" -u root -p"${DB_ROOT_PASSWORD}" shutdown
	wait "$TMP_PID"
else
	echo "[mariadb.sh] Existing database found, skipping initialization."
fi

echo "[mariadb.sh] Starting MariaDB in foreground..."
exec mariadbd --user=mysql --datadir="$DATADIR" --socket="$SOCKET"
