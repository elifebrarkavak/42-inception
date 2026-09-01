# Inception Dosyalarını Yazma Sırası

Servislerin bağımlılık sırası:

`MariaDB → WordPress/PHP-FPM → NGINX → Docker Compose`

## 1. Ortak değişkenler ve gizli bilgiler

1. `srcs/.env`
2. `secrets/db_root_password.txt`
3. `secrets/db_password.txt`
4. Gerekli WordPress kullanıcı bilgilerini taşıyan secret dosyaları

Önce domain, veritabanı adı ve kullanıcı adları belirlenmelidir. Şifreler `.env`, Dockerfile veya `docker-compose.yml` içine doğrudan yazılmamalıdır.

## 2. MariaDB

1. `srcs/requirements/mariadb/conf/50-server.cnf`
2. `srcs/requirements/mariadb/tools/mariadb.sh`
3. `srcs/requirements/mariadb/Dockerfile`
4. `srcs/requirements/mariadb/.dockerignore`

WordPress veritabanına bağımlı olduğu için ilk tamamlanması gereken servis MariaDB'dir.

## 3. WordPress ve PHP-FPM

1. `srcs/requirements/wordpress/conf/www.conf`
2. `srcs/requirements/wordpress/tools/wordpress.sh`
3. `srcs/requirements/wordpress/Dockerfile`
4. `srcs/requirements/wordpress/.dockerignore`

WordPress başlangıç betiği, MariaDB'nin hazır olmasını beklemeli ve kurulumu yalnızca gerektiğinde yapmalıdır.

## 4. NGINX ve TLS

1. `srcs/requirements/nginx/conf/nginx.conf`
2. Gerekirse `srcs/requirements/nginx/tools/` altında sertifika hazırlama betiği
3. `srcs/requirements/nginx/Dockerfile`
4. `srcs/requirements/nginx/.dockerignore`

NGINX yalnızca `443` üzerinden TLS bağlantısı kabul etmeli ve istekleri WordPress'in PHP-FPM portuna aktarmalıdır.

## 5. Servisleri birleştirme

1. `srcs/docker-compose.yml`

Bu dosyada üç servis, ortak ağ, iki kalıcı volume, secrets kullanımı, servis bağımlılıkları ve yeniden başlatma politikası tanımlanmalıdır.

## 6. Proje komutları

1. `Makefile`

Projeyi kurma, başlatma, durdurma ve temizleme hedefleri eklenmelidir.

## 7. Dokümantasyon

1. `README.md`
2. `USER_DOC.md`
3. `DEV_DOC.md`

Dokümantasyon, gerçek kurulum ve kullanım adımları kesinleştikten sonra tamamlanmalıdır.

## Her servis için çalışma sırası

`Yapılandırma dosyası → Başlangıç betiği → Dockerfile → Servis testi`

