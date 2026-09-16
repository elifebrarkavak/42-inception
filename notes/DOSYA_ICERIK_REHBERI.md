# Inception Dosya İçerik Rehberi

Bu belge, Inception subject v5.3 kapsamında hangi dosyanın hangi görevi üstleneceğini açıklar.

Servislerin bağımlılık sırası:

`MariaDB → WordPress/PHP-FPM → NGINX → Docker Compose`

> Not: Subject; `50-server.cnf`, `mariadb.sh` veya `www.conf` gibi yapılandırma ve betik dosyalarının isimlerini zorunlu tutmaz. Bu belgede kullanılan isimler önerilen proje düzenidir.

## Proje kökü

### `Makefile`

Docker altyapısını yönetmelidir:

- Gerekli veri klasörlerini hazırlamalıdır.
- Docker image'larını oluşturmalıdır.
- `srcs/docker-compose.yml` dosyasını çalıştırmalıdır.
- Projeyi başlatma, durdurma, yeniden oluşturma ve temizleme hedefleri içermelidir.
- Önerilen hedefler: `all`, `build`, `up`, `down`, `start`, `stop`, `logs`, `clean`, `fclean` ve `re`.

### `README.md`

İngilizce yazılmalı ve şunları içermelidir:

- İlk satırda italik 42 curriculum açıklaması.
- Projenin amacı ve kısa açıklaması.
- Kurulum ve çalıştırma talimatları.
- Kullanılan kaynaklar.
- Yapay zekânın hangi görevlerde kullanıldığı.
- Projenin ana tasarım tercihleri.
- Virtual Machine ve Docker karşılaştırması.
- Secrets ve environment variables karşılaştırması.
- Docker Network ve host network karşılaştırması.
- Docker volumes ve bind mounts karşılaştırması.

### `USER_DOC.md`

Son kullanıcı ve sistem yöneticisi için şunları açıklamalıdır:

- Stack tarafından sağlanan servisler.
- Projenin nasıl başlatılıp durdurulacağı.
- WordPress sitesine nasıl erişileceği.
- WordPress yönetim paneline nasıl girileceği.
- Kimlik bilgilerinin nerede bulunduğu ve nasıl yönetileceği.
- Servislerin çalışıp çalışmadığının nasıl kontrol edileceği.
- Temel hata çözme adımları.

### `DEV_DOC.md`

Geliştirici için şunları açıklamalıdır:

- Gerekli programlar ve ön koşullar.
- Ortamın sıfırdan hazırlanması.
- `.env` ve secret dosyalarının hazırlanması.
- Makefile ve Docker Compose ile build ve başlatma işlemleri.
- Container, network ve volume yönetimi.
- Proje verilerinin host üzerinde nerede saklandığı.
- Verilerin container yeniden oluşturulduğunda nasıl kalıcı kaldığı.
- Projenin genel mimarisi.

### `DOSYA_YAZMA_SIRASI.md`

Dosyaların hangi sırada hazırlanacağını anlatan geliştirme rehberidir. Projenin çalışmasına doğrudan katılmaz.

### `DOSYA_ICERIK_REHBERI.md`

Hangi dosyanın hangi görevi üstleneceğini açıklayan bu rehberdir. Projenin çalışmasına doğrudan katılmaz.

## `secrets/`

Bu klasörde gerçek şifreler bulunmalıdır. Secret dosyaları Git'e gönderilmemelidir.

### `secrets/db_root_password.txt`

- Yalnızca MariaDB root şifresini içermelidir.
- Tek satır olmalıdır.

### `secrets/db_password.txt`

- WordPress'in kullanacağı MariaDB kullanıcısının şifresini içermelidir.
- Tek satır olmalıdır.

### `secrets/credentials.txt`

- WordPress yönetici şifresini içermelidir.
- Normal WordPress kullanıcı şifresini içermelidir.
- Dosya formatı, `wordpress.sh` betiğinin okuyacağı formatla aynı olmalıdır.

Örnek anahtarlar:

```text
WORDPRESS_ADMIN_PASSWORD=...
WORDPRESS_USER_PASSWORD=...
```

Gerçek şifreler Dockerfile, `.env` veya `docker-compose.yml` içine yazılmamalıdır.

## `srcs/.env`

Şifre olmayan ortak değişkenleri içermelidir. Önerilen değişkenler:

```text
LOGIN=...
DOMAIN_NAME=....42.fr
MYSQL_DATABASE=...
MYSQL_USER=...
WORDPRESS_TITLE=...
WORDPRESS_ADMIN_USER=...
WORDPRESS_ADMIN_EMAIL=...
WORDPRESS_USER=...
WORDPRESS_USER_EMAIL=...
DATA_PATH=/home/.../data
```

Kurallar:

- `DOMAIN_NAME`, kendi 42 login'in kullanılarak `login.42.fr` biçiminde olmalıdır.
- WordPress yönetici kullanıcı adı `admin` veya `administrator` kelimelerini içeremez.
- Şifreler `.env` içinde bulunmamalıdır.

## `srcs/docker-compose.yml`

Bütün servisleri birbirine bağlamalıdır:

- `mariadb`, `wordpress` ve `nginx` servislerini tanımlamalıdır.
- Her servis için projedeki ilgili Dockerfile'ı build etmelidir.
- Her Docker image'ının adı ilgili servisle aynı olmalıdır.
- `.env` değişkenlerini servislere aktarmalıdır.
- Secret dosyalarını ilgili container'lara bağlamalıdır.
- MariaDB named volume'ünü `/var/lib/mysql` konumuna bağlamalıdır.
- WordPress named volume'ünü `/var/www/html` konumuna bağlamalıdır.
- İki kalıcı storage'ı Docker named volume olarak tanımlamalıdır.
- Named volume verilerinin host üzerinde `/home/<login>/data` altında tutulmasını sağlamalıdır.
- Servisler için ortak bir Docker network tanımlamalıdır.
- Container'lara yeniden başlatma politikası vermelidir.
- Yalnızca NGINX için `443:443` portunu host'a açmalıdır.
- WordPress ve MariaDB portlarını host'a açmamalıdır.
- Servis bağımlılıklarını tanımlamalıdır.
- `network_mode: host`, `links` veya `--link` kullanmamalıdır.

## MariaDB

### `srcs/requirements/mariadb/conf/50-server.cnf`

MariaDB sunucu ayarlarını içermelidir:

- Port `3306`.
- Container ağına uygun dinleme adresi.
- Veritabanı veri klasörü olarak `/var/lib/mysql`.
- Socket ve PID dosyası konumları.
- Karakter seti ve collation ayarları.
- WordPress container'ından gelen bağlantıları kabul edecek ağ ayarları.

### `srcs/requirements/mariadb/tools/mariadb.sh`

MariaDB başlangıç betiği olmalıdır:

- İlk çalıştırmada veri klasörünü hazırlamalıdır.
- `/run/secrets/` altındaki root ve kullanıcı şifrelerini okumalıdır.
- `.env` üzerinden veritabanı ve kullanıcı adını almalıdır.
- WordPress veritabanını oluşturmalıdır.
- WordPress veritabanı kullanıcısını oluşturmalıdır.
- Kullanıcıya yalnızca gerekli veritabanı yetkilerini vermelidir.
- Container yeniden başladığında mevcut veritabanını yeniden oluşturmamalıdır.
- Hazırlık bittikten sonra MariaDB'yi foreground'da `exec` ile çalıştırmalıdır.
- `tail -f`, `sleep infinity`, `while true` veya benzeri sonsuz döngü çözümleri içermemelidir.

### `srcs/requirements/mariadb/Dockerfile`

MariaDB image'ını oluşturmalıdır:

- Alpine veya Debian'ın sondan bir önceki kararlı sürümünü açık bir sürüm etiketiyle kullanmalıdır.
- `latest` etiketi kullanmamalıdır.
- MariaDB paketlerini kurmalıdır.
- `50-server.cnf` dosyasını image içine kopyalamalıdır.
- `mariadb.sh` betiğini kopyalayıp çalıştırılabilir yapmalıdır.
- Başlangıç komutunu tanımlamalıdır.
- Şifre içermemelidir.
- Hazır MariaDB image'ı kullanmamalıdır.

### `srcs/requirements/mariadb/.dockerignore`

MariaDB build işleminde gerekmeyen öğeleri dışlamalıdır:

- Git dosyaları.
- Editör ve geçici dosyalar.
- Log dosyaları.
- Secret dosyaları.

Dockerfile'ın kopyalayacağı `conf/` ve `tools/` klasörlerini dışlamamalıdır.

## WordPress ve PHP-FPM

### `srcs/requirements/wordpress/conf/www.conf`

PHP-FPM pool ayarlarını içermelidir:

- PHP-FPM'in `9000` portundan dinlemesi.
- NGINX'in Docker ağı üzerinden bağlanabilmesi.
- PHP-FPM'in çalışacağı kullanıcı ve grup.
- Worker ve process ayarları.
- Logların container çıktısına yönlendirilmesi.
- PHP-FPM'in foreground kullanımına uygun ayarlar.

### `srcs/requirements/wordpress/tools/wordpress.sh`

WordPress başlangıç betiği olmalıdır:

- MariaDB hazır olana kadar kontrollü şekilde beklemelidir.
- WordPress dosyaları yoksa indirmelidir.
- `wp-config.php` dosyasını oluşturmalıdır.
- Veritabanı bilgilerini `.env` ve secrets üzerinden almalıdır.
- WordPress kurulmamışsa kurulumu gerçekleştirmelidir.
- Bir yönetici hesabı oluşturmalıdır.
- İkinci bir normal kullanıcı oluşturmalıdır.
- Yönetici kullanıcı adında `admin` veya `administrator` bulunmadığını doğrulamalıdır.
- Container yeniden başladığında kurulumu tekrarlamamalıdır.
- Son işlem olarak PHP-FPM'i foreground'da `exec` ile çalıştırmalıdır.

### `srcs/requirements/wordpress/Dockerfile`

WordPress image'ını oluşturmalıdır:

- Alpine veya Debian'ın uygun sürümünü açık bir sürüm etiketiyle kullanmalıdır.
- PHP-FPM ve gerekli PHP eklentilerini kurmalıdır.
- MariaDB bağlantısı için PHP MySQL eklentisini kurmalıdır.
- Gerekirse WP-CLI kurmalıdır.
- `www.conf` ve `wordpress.sh` dosyalarını image içine kopyalamalıdır.
- WordPress çalışma klasörünü `/var/www/html` olarak ayarlamalıdır.
- PHP-FPM'i başlangıç betiği aracılığıyla foreground'da çalıştırmalıdır.
- NGINX içermemelidir.
- Şifre içermemelidir.
- Hazır WordPress image'ı kullanmamalıdır.

### `srcs/requirements/wordpress/.dockerignore`

WordPress build işleminde gerekmeyen öğeleri dışlamalıdır:

- Git dosyaları.
- Editör ve geçici dosyalar.
- Log dosyaları.
- Yerel WordPress çalışma dosyaları.
- Secret dosyaları.

Dockerfile'ın kopyalayacağı `conf/` ve `tools/` klasörlerini dışlamamalıdır.

## NGINX ve TLS

### `srcs/requirements/nginx/conf/nginx.conf`

Web sunucusu ayarlarını içermelidir:

- Yalnızca `443` portundan dinlemelidir.
- `server_name` olarak `login.42.fr` domain'ini kullanmalıdır.
- Yalnızca TLS 1.2 ve TLS 1.3 protokollerine izin vermelidir.
- Sertifika ve özel anahtar konumlarını tanımlamalıdır.
- WordPress kök klasörünü `/var/www/html` olarak kullanmalıdır.
- Statik dosyaları doğrudan sunmalıdır.
- PHP isteklerini `wordpress:9000` adresine FastCGI ile göndermelidir.
- Gerekli FastCGI parametrelerini tanımlamalıdır.
- Hassas ve gizli dosyalara erişimi engellemelidir.
- Port `80` için server bloğu içermemelidir.

### `srcs/requirements/nginx/tools/generate-certificate.sh`

Bu isteğe bağlı betik TLS sertifikasını hazırlayabilir:

- OpenSSL ile self-signed sertifika üretmelidir.
- Sertifika ve private key klasörlerini hazırlamalıdır.
- Sertifika mevcutsa gereksiz yere tekrar üretmemelidir.

Sertifika doğrudan Dockerfile içinde oluşturuluyorsa bu betiğe ihtiyaç olmayabilir.

### `srcs/requirements/nginx/Dockerfile`

NGINX image'ını oluşturmalıdır:

- Alpine veya Debian'ın uygun sürümünü açık bir sürüm etiketiyle kullanmalıdır.
- NGINX ve OpenSSL kurmalıdır.
- `nginx.conf` dosyasını image içine kopyalamalıdır.
- TLS sertifikasını oluşturmalı veya sertifika hazırlama betiğini kopyalamalıdır.
- Yalnızca `443` portu için hazırlanmalıdır.
- NGINX'i foreground'da çalıştırmalıdır.
- WordPress veya PHP-FPM içermemelidir.
- Şifre içermemelidir.
- Hazır NGINX image'ı kullanmamalıdır.

### `srcs/requirements/nginx/.dockerignore`

NGINX build işleminde gerekmeyen öğeleri dışlamalıdır:

- Git dosyaları.
- Editör ve geçici dosyalar.
- Log dosyaları.
- Yerel private key ve sertifikalar.
- Secret dosyaları.

Dockerfile'ın kopyalayacağı `conf/` ve `tools/` klasörlerini dışlamamalıdır.

## `srcs/requirements/tools/`

Ortak hazırlık betikleri için kullanılabilir.

Örneğin `setup.sh` adlı bir betik:

- `/home/<login>/data` klasörünü oluşturabilir.
- MariaDB veri klasörünü oluşturabilir.
- WordPress veri klasörünü oluşturabilir.
- Gerekli sahiplik ve izinleri ayarlayabilir.
- Makefile tarafından çağrılabilir.

Ortak bir betiğe ihtiyaç yoksa bu klasör boş bırakılabilir.

## `srcs/requirements/bonus/`

Yalnızca zorunlu bölüm tamamen çalıştıktan sonra kullanılmalıdır. Her bonus servis kendi klasöründe, kendi Dockerfile'ı ile yer almalıdır.

Örnek:

```text
bonus/
└── redis/
    ├── Dockerfile
    ├── conf/
    └── tools/
```

Redis, FTP, Adminer, statik site veya başka bir ek servis ayrı bir container içinde çalışmalıdır.

## Genel kurallar

- Her servis ayrı bir container içinde çalışmalıdır.
- Her servis için ayrı bir Dockerfile bulunmalıdır.
- Hazır NGINX, WordPress veya MariaDB image'ları kullanılmamalıdır.
- Base image olarak yalnızca uygun Alpine veya Debian sürümü kullanılmalıdır.
- `latest` etiketi kullanılmamalıdır.
- Şifreler Dockerfile, `.env`, Compose dosyası veya Git deposunda açık şekilde bulunmamalıdır.
- Container'lar `tail -f`, `sleep infinity`, `while true` veya benzeri yöntemlerle açık tutulmamalıdır.
- Ana servis PID 1 olarak foreground'da çalışmalıdır.
- Yalnızca NGINX host'a açılmalı ve yalnızca `443` portunu kullanmalıdır.
- İki kalıcı storage Docker named volume olmalıdır; servislerde doğrudan bind mount kullanılmamalıdır.
- `.sh` dosyaları Linux uyumluluğu için LF satır sonlarıyla kaydedilmelidir.
- Yazılan her komut değerlendirmeden önce anlaşılmalı ve test edilmelidir.

