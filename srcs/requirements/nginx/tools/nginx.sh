#!/bin/bash
set -e

SSL_DIR=/etc/nginx/ssl
CERT_FILE="${SSL_DIR}/inception.crt"
KEY_FILE="${SSL_DIR}/inception.key"

mkdir -p "${SSL_DIR}"

if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
	echo "[nginx.sh] TLS sertifikasi olusturuluyor..."
	openssl req -x509 -nodes \
		-days 365 \
		-newkey rsa:2048 \
		-keyout "${KEY_FILE}" \
		-out "${CERT_FILE}" \
		-subj "/C=TR/ST=Istanbul/O=42/CN=${DOMAIN_NAME}"
fi

echo "[nginx.sh] NGINX baslatiliyor..."
exec nginx -g "daemon off;"
