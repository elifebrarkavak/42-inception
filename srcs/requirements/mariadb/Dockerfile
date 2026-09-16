FROM debian:bookworm-slim

RUN apt-get update && \
	apt-get install -y --no-install-recommends \
		mariadb-server \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/mariadb.sh /usr/local/bin/mariadb.sh
RUN chmod +x /usr/local/bin/mariadb.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/mariadb.sh"]
