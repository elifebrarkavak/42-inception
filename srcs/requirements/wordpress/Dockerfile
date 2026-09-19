FROM debian:bookworm

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		php8.2-fpm \
		php8.2-cli \
		php8.2-mysqli \
		php8.2-gd \
		php8.2-curl \
		php8.2-mbstring \
		php8.2-xml \
		php8.2-zip \
		php8.2-intl \
		mariadb-client \
		curl \
		ca-certificates \
	&& curl -o /usr/local/bin/wp -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
	&& chmod +x /usr/local/bin/wp \
	&& rm -rf /var/lib/apt/lists/*

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/wordpress.sh /usr/local/bin/wordpress.sh
RUN chmod +x /usr/local/bin/wordpress.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress.sh"]
