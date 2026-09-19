FROM debian:bookworm

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		nginx \
		openssl \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -f /etc/nginx/sites-enabled/default

COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY tools/nginx.sh /usr/local/bin/nginx.sh
RUN chmod +x /usr/local/bin/nginx.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/nginx.sh"]
