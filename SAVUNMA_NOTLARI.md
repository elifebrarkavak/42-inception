## 1. Değerlendirme nasıl ilerliyor

Eval, sırayla ilerleyen ve **her biri "eval burada biter" ile sonlanabilen** bölümlerden
oluşuyor. Sıralamayı bilmek önemli, çünkü ilk bölümlerde takılırsan gerisi hiç açılmıyor.

| # | Bölüm | Ne kontrol ediliyor |
| - | ----- | ------------------- |
| 0 | Preliminaries | Repo doğru mu, öğrenci hazır mı, **git'te credential var mı** |
| 1 | General instructions | `srcs/`, `Makefile`, compose ve Dockerfile yasakları, `make` çalışıyor mu |
| 2 | Activity overview | **Sözlü**: Docker/compose nasıl çalışır, VM farkı, dizin yapısı |
| 3 | README check | İlk satır formatı + Description / Instructions / Resources |
| 4 | Documentation check | `USER_DOC.md` ve `DEV_DOC.md` var mı, boş değil mi |
| 5 | Simple setup | 443'ten erişim, sertifika, WP kurulu (kurulum ekranı **çıkmamalı**) |
| 6 | Docker Basics | Servis başına Dockerfile, kendi image'ları, base image, image adları |
| 7 | Docker Network | compose'da network var mı, `docker network ls`, **sözlü açıklama** |
| 8 | NGINX with SSL/TLS | 80 kapalı, 443 açık, TLS 1.2/1.3 **kanıtlanmalı** |
| 9 | WordPress + php-fpm | Dockerfile'da nginx yok, volume `/home/login/data/`, **yorum ekle**, **sayfa düzenle** |
| 10 | MariaDB | Dockerfile'da nginx yok, volume, **DB'ye nasıl girilir anlat**, DB boş olmamalı |
| 11 | Persistence | **VM reboot** → compose tekrar ayağa → değişiklikler duruyor mu |
| 12 | Configuration modification | Canlı canlı bir servisin portunu değiştir, rebuild et, çalışsın |
| 13 | Bonus | Sadece mandatory kusursuzsa; her bonus +1 puan |

### Değerlendirici işe başlamadan önce her şeyi siliyor

```bash
docker stop $(docker ps -qa); docker rm $(docker ps -qa); docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q); docker network rm $(docker network ls -q) 2>/dev/null
```

**Sonuç:** Projen tamamen boş bir Docker'dan, tek `make` ile ayağa kalkmak zorunda. Savunmadan
önce mutlaka bu komutu kendin çalıştırıp `make` dene. "Bende çalışıyordu" diye bir şey yok —
cache'siz, volume'süz, sıfırdan build edilecek.

Ayrıca repo **boş bir dizine `git clone`** ile çekiliyor. Yani `.gitignore`'ladığın `.env` ve
`secrets/*.txt` klonda olmayacak. Bunları savunma sırasında elle oluşturman gerekecek —
`USER_DOC.md`'deki adımlar tam olarak bunun için var, hazır bir kopyala-yapıştır bloğun olsun.

---

## 2. Anında elenme sebepleri

Bunlar tartışmaya açık değil, doğrudan eval'i bitiriyor:

| Kırmızı çizgi | Nerede yakalanır |
| ------------- | ---------------- |
| Git repo'da şifre / API key / credential (secrets dışında) | Preliminaries → **not 0** |
| Hile (cheat) | Preliminaries → **not -42** |
| `docker-compose.yml` içinde `network: host` veya `links:` | General instructions |
| Herhangi bir script/Makefile içinde `--link` | General instructions |
| `docker-compose.yml` içinde `network(s)` **yok** | General instructions |
| ENTRYPOINT'te `tail -f` veya arka planda çalışan komut | General instructions |
| ENTRYPOINT'te script çalıştırmak dışında `bash`/`sh` (örn. `nginx & bash`) | General instructions |
| Script içinde sonsuz döngü (`sleep infinity`, `tail -f /dev/null`, `tail -f /dev/random`) | General instructions |
| Base image penultimate stable Alpine/Debian değil | General instructions + Docker Basics |
| `FROM` satırı `alpine:X.X.X` veya `debian:XXXXX` formatında değil | Docker Basics |
| Image adı servis adıyla aynı değil | Docker Basics |
| Hazır image kullanılmış (DockerHub'dan wordpress/mariadb/nginx) | Docker Basics |
| `README.md` yok, ilk satır formatı yanlış, veya bir bölüm eksik | README check |
| `USER_DOC.md` veya `DEV_DOC.md` yok / boş | Documentation check |
| `http://login.42.fr` çalışıyor | Simple setup, NGINX |
| WordPress kurulum ekranı çıkıyor | Simple setup |
| `docker volume inspect` çıktısında `/home/login/data/` yok | WordPress / MariaDB |
| Admin kullanıcı adında `admin`/`Admin` geçiyor | WordPress |
| Reboot sonrası veri kaybı | Persistence |
| Canlı konfigürasyon değişikliği yapılamıyor | Configuration modification |

**En sinsi olanı `--link`.** Sadece compose'a değil, `Makefile` ve **tüm script'lere** bakılıyor.

---

## 3. Bilmen gereken konular

### 3.1 Docker temeli

**Docker nedir?** Bir sanallaştırma değil, **process izolasyonu** aracı. Kernel'in iki
özelliğini kullanır:

- **Namespace'ler** — *ne görüyorsun*. `pid` (process tablosu), `net` (ağ arayüzleri), `mnt`
  (dosya sistemi), `uts` (hostname), `ipc`, `user`. Container içindeki process kendini tek
  başına bir sistemde sanır.
- **cgroup'lar** — *ne kadar kullanabilirsin*. CPU, RAM, I/O limitleri.

Üçüncü parça **union filesystem** (overlay2): image katmanlarını üst üste bindirip tek bir
dosya sistemi gibi gösterir.

**Image vs Container:**

| Image | Container |
| ----- | --------- |
| Salt okunur katmanlar + metadata (CMD, ENV, EXPOSE…) | Image + üstüne **yazılabilir katman** + çalışan process |
| Disk üzerinde durur, çalışmaz | Namespace'ler içinde çalışan bir process |
| `docker build` üretir | `docker run` üretir |
| Sınıf (class) gibi | Nesne (instance) gibi |

**Katmanlar:** Her `RUN`, `COPY`, `ADD` yeni bir katman üretir. Katmanlar **değişmez**. Bu
yüzden:
- Bir katmanda dosya yazıp sonraki katmanda silmek image'ı küçültmez — dosya hâlâ alt katmanda
  durur. `apt-get update && apt-get install && rm -rf /var/lib/apt/lists/*` **aynı `RUN`'da**
  olmalı.
- Bir katmana yazılan şifre kalıcıdır ve `docker history` ile okunabilir. Bu yüzden
  Dockerfile'da şifre yasak.

### 3.2 docker compose

**Ne yapar?** Birden fazla container'ın tanımını tek bir YAML'de toplar: hangi image, hangi
network, hangi volume, hangi env, hangi sırada. `docker run` ile onlarca flag yazmak yerine
bildirimsel (declarative) bir dosya.

**"Compose ile kullanılan image ile compose'suz image arasındaki fark nedir?" (eval sorusu)**

Cevap şu: **Image'ın kendisinde hiçbir fark yoktur.** Aynı Dockerfile, aynı katmanlar, aynı
binary. Fark image'da değil, **yönetiminde**:

| | `docker build` + `docker run` | `docker compose` |
| --- | --- | --- |
| Tanım nerede | Terminal geçmişinde, flag'lerde | Versiyonlanan bir YAML dosyasında |
| Network | Elle `docker network create` + `--network` | Otomatik oluşturulur, proje adıyla önek alır |
| Volume | Elle `-v` | `volumes:` bloğunda tanımlı |
| Sıra | Elle | `depends_on` |
| Yaşam döngüsü | Container container | Tüm stack birlikte (`up` / `down`) |
| İsimlendirme | Rastgele veya `--name` | `<proje>_<servis>_<n>`, network/volume'de `<proje>_` öneki |

Kısacası compose bir **orkestrasyon** katmanıdır, bir image formatı değil.

### 3.3 PID 1 ve sinyaller — en çok soru gelen konu

Container'ın içindeki ilk process PID 1 olur ve **kernel PID 1'e özel davranır**: PID 1 için
varsayılan sinyal handler'ları kurulmaz. Yani PID 1 `SIGTERM` için açıkça bir handler
tanımlamamışsa, sinyal **hiçbir şey yapmadan yok sayılır**.

Pratik sonuçları:

- `docker stop` önce PID 1'e `SIGTERM` yollar, 10 saniye bekler, sonra `SIGKILL` atar.
- PID 1 sinyali handle etmeyen bir shell script'se → container her durdurulmada 10 saniye
  bekler ve sonra sert öldürülür. Veritabanı için bu **bozuk veri** demektir.
- PID 1 aynı zamanda **zombie reaping** yapmakla yükümlüdür (yetim process'leri toplamak).

Çözüm: gerçek daemon'ı PID 1 yapmak.

```bash
#!/bin/sh
# ... kurulum işleri ...
exec "$@"        # <-- kritik satır
```

`exec` yeni bir process başlatmaz, **mevcut process'i değiştirir**. Shell'in PID'si daemon'a
geçer. `exec` olmadan: shell PID 1 kalır, daemon onun çocuğu olur, sinyal daemon'a hiç ulaşmaz.

Dockerfile tarafı:

```dockerfile
ENTRYPOINT ["setup.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

`ENTRYPOINT` **exec form** (JSON dizisi) olmalı. Shell form (`ENTRYPOINT setup.sh`) komutu
`/bin/sh -c` içine sarar; o shell sinyalleri iletmez.

### 3.4 Daemon'ı ön planda çalıştırmak

Container, PID 1 çıktığı anda ölür. Servisler varsayılan olarak arka plana geçtiği (daemonize
olduğu) için ön plana zorlanmaları gerekir:

| Servis | Komut | Neden |
| ------ | ----- | ----- |
| NGINX | `nginx -g "daemon off;"` | Varsayılanda fork eder, parent çıkar, container ölür |
| PHP-FPM | `php-fpm8.2 -F` | `-F` = foreground (`--nodaemonize`) |
| MariaDB | `mariadbd` | Doğrudan çağrıldığında zaten ön planda. `mysqld_safe` bir sarmalayıcı script'tir, kullanma |

**`tail -f` neden yasak?** Container'ı ayakta tutmak için `tail -f /dev/null` yazmak, PID 1'i
servisle alakasız bir process yapar. O zaman: servis çökerse container ayakta kalır (restart
policy devreye girmez), `docker stop` servisi düzgün kapatmaz, loglar container log'una
düşmez. Yani container "çalışıyor" görünür ama site ölüdür. Bu bir *hack*, çözüm değil.

### 3.5 Docker network

**Bridge network:** Docker host üzerinde sanal bir switch (`docker0` benzeri) oluşturur. Her
container kendi `net` namespace'ini ve kendi IP'sini alır, `veth` çiftiyle bu switch'e
bağlanır.

**Gömülü DNS:** Kullanıcı tanımlı bir bridge network'te Docker `127.0.0.11` adresinde bir DNS
sunucusu çalıştırır. Container'lar birbirini **servis adıyla** bulur: `mariadb` → o an hangi
IP'ye sahipse ona çözülür. IP hardcode etmek gerekmez, container yeniden başlayıp IP değişse
bile çalışır.

> **Önemli ayrım:** Bu otomatik DNS **sadece kullanıcı tanımlı** network'lerde vardır.
> Varsayılan `bridge` network'ünde yoktur — orada eskiden `--link` kullanılırdı.

**`--link` neden ölü:** Tek yönlüydü, container başlangıcında `/etc/hosts` ve environment
variable enjekte ederdi, hedef container yeniden başlayıp IP değiştirdiğinde bozulurdu.
Kullanıcı tanımlı network aynı işi doğru yaptığı için deprecate edildi.

**`network_mode: host` neden yasak:** Container host'un ağ namespace'ini paylaşır. Sonuç:

- İzolasyon yok — MariaDB'nin 3306'sı anında VM'in arayüzünde açılır.
- Servis keşfi yok — her şey `127.0.0.1`.
- Port çakışması — iki servis aynı portu isteyemez.
- Projenin tüm güvenlik iddiası ("tek giriş 443") çöker.

**`ports:` vs `expose:`**

| | `ports: "443:443"` | `expose: 9000` |
| --- | --- | --- |
| Host'tan erişilir mi | **Evet** | Hayır |
| Network'ten erişilir mi | Evet | Evet |
| Ne yapar | Host portunu container portuna NAT'lar | Sadece dokümantasyon/metadata |

Bu projede `ports:` **sadece nginx'te**, sadece 443.

### 3.6 Volume vs bind mount

| | Named volume | Bind mount |
| --- | --- | --- |
| Yöneten | Docker | Sen |
| Tanım | İsmi ve yaşam döngüsü olan bir nesne | Sadece bir host yolu |
| `docker volume ls` | Görünür | Görünmez |
| Taşınabilirlik | Compose dosyası her yerde çalışır | Yol yoksa patlar |
| Tipik kullanım | Kalıcı servis verisi | Geliştirme sırasında canlı kaynak kodu |

**Bu projedeki ikilem:** Subject named volume **zorunlu** kılıyor (bind mount yasak), ama aynı
zamanda verinin `/home/elikavak/data` altında olmasını istiyor. İkisini birden sağlamanın yolu,
named volume'ü `local` driver ile bir host dizinine yönlendirmek:

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/elikavak/data/wordpress
```

Bu **gerçek bir named volume**'dür: adı var, yaşam döngüsü var, `docker volume ls`'te görünür,
compose ona adıyla referans verir. `driver_opts` sadece "byte'ları nerede tut" der.

> **Savunmada tökezleten detay:** `docker volume inspect srcs_wordpress_data` çıktısında
> `Mountpoint` alanı **`/var/lib/docker/volumes/...`** gösterir, `/home/elikavak/data/...`
> değil. Aranan yol `Options.device` alanındadır. Eval "standart çıktı `/home/login/data/`
> içermeli" diyor — JSON'un tamamı basıldığı için şart sağlanır, ama değerlendirici
> `Mountpoint`'e bakıp "yok" derse `Options` bloğunu göstermen gerekir. Bunu önceden bil.

**Host dizini önceden var olmalı.** `local` driver bind hedefini kendisi oluşturmaz. `make`
bunu `mkdir -p` ile hallediyor — bu yüzden `make dirs` hedefi var.

### 3.7 Secrets vs environment variables

| | Environment variable | Docker secret |
| --- | --- | --- |
| Nerede durur | Container environment'ı, compose dosyası, `ENV` ile image metadata'sı | `/run/secrets/<ad>` altında salt okunur dosya |
| `docker inspect` | **Değeri görünür** | Sadece mount noktası görünür |
| `/proc/<pid>/environ` | **Görünür** | Görünmez |
| Image katmanına yazılır mı | `ENV`/`ARG` ile evet — ve katman kalıcıdır | Asla |
| Log/crash dump sızıntısı | Kolay (çoğu araç environment'ı döker) | Zor |

Ayrım kuralı: *"Bu string herkese açık olsa zarar görür müyüm?"*

- `srcs/.env` → domain, DB adı, site başlığı, kullanıcı adları, data yolu.
- `secrets/*.txt` → MariaDB root şifresi, WP DB kullanıcı şifresi, WP hesap şifreleri.

**Dürüst ol:** Compose (Swarm değil) modunda secret'lar host'ta düz bir dosyadır, güvenliği o
dosyanın izinlerine bağlıdır. Garanti ettiği şey şudur: şifre **image katmanında değildir**,
**`docker inspect`'te değildir**, **process environment'ında değildir**. Bu farkı bilmek
savunmada iyi durur.

### 3.8 TLS

- **TLS nedir:** Şifreleme (gizlilik) + bütünlük + sunucu kimlik doğrulama.
- **Handshake:** İstemci desteklediği sürümleri/cipher'ları yollar → sunucu birini seçip
  sertifikasını verir → anahtar değişimi (TLS 1.3'te ECDHE) → simetrik anahtarla şifreli
  iletişim.
- **1.2 vs 1.3:** 1.3 handshake'i 1 RTT'ye indirir, eski/kırık cipher'ları (RC4, 3DES, static
  RSA, CBC-MAC-then-encrypt) tamamen kaldırır.
- **Self-signed:** Sertifikayı bir CA değil, kendisi imzalar. `elikavak.42.fr` yerel bir isim
  olduğundan hiçbir public CA sertifika veremez. Tarayıcı uyarısı **beklenen** davranış ve
  eval'da açıkça kabul ediliyor. Uyarı "şifreleme yok" demek değil — trafik yine TLS ile
  korunuyor, sadece kimliği doğrulayan üçüncü taraf yok.

NGINX tarafı:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Kanıtlama:

```bash
openssl s_client -connect elikavak.42.fr:443 -tls1_2 </dev/null
```

```bash
openssl s_client -connect elikavak.42.fr:443 -tls1_1 </dev/null
```

Birincisi el sıkışmalı, ikincisi **başarısız olmalı** — o başarısızlık doğru sonuçtur.

### 3.9 NGINX ↔ PHP-FPM ↔ MariaDB

**İstek yolu:**

```
Tarayıcı --HTTPS/443--> NGINX --FastCGI/9000--> php-fpm --MySQL/3306--> MariaDB
```

- **Statik dosya** (`.css`, `.jpg`) → NGINX doğrudan volume'den okur, PHP'ye hiç gitmez.
- **`.php`** → NGINX FastCGI ile php-fpm'e devreder.

**Neden `fastcgi_pass`, `proxy_pass` değil?** `proxy_pass` HTTP konuşur. php-fpm HTTP
konuşmaz, **FastCGI** adlı ikili protokolü konuşur. Yanlış direktif = bozuk yanıt.

**Neden TCP 9000, Unix socket değil?** Unix socket bir dosya sistemi nesnesidir ve container'ın
kendi `mnt` namespace'i içinde yaşar. Farklı container'daki NGINX ona erişemez. Bu yüzden
`www.conf` içinde:

```ini
listen = 0.0.0.0:9000
```

Debian'ın varsayılanı socket'tir — değiştirilmezse `502 Bad Gateway` alırsın.

**Aynı şekilde MariaDB:** Debian varsayılanı `bind-address = 127.0.0.1`. Değiştirilmezse
WordPress container'ı DB'ye bağlanamaz. `0.0.0.0` yapılmalı.

**PHP-FPM nedir?** FastCGI Process Manager. PHP yorumlayıcısını kalıcı bir worker havuzu olarak
çalıştırır. Her istekte process başlatmak yerine hazır worker'lar isteği alır — CGI'ye göre çok
daha hızlı.

### 3.10 WordPress ve MariaDB kurulumu

**`wp-config.php`** — WordPress'in DB bağlantı bilgilerini (`DB_NAME`, `DB_USER`,
`DB_PASSWORD`, `DB_HOST`) ve güvenlik anahtarlarını tutan dosya. Entrypoint bunu env
değişkenleri ve secret'lardan üretir.

**WP-CLI** — WordPress'in komut satırı aracı. Kurulumu tarayıcıdaki sihirbaz olmadan yapmayı
sağlar. Bu projede kritik: eval "WordPress kurulum sayfasını **görmemelisin**" diyor, yani
kurulum otomatik tamamlanmış olmalı.

```bash
wp core download
wp config create --dbname=... --dbuser=... --dbpass=... --dbhost=mariadb
wp core install --url=... --title=... --admin_user=... --admin_password=... --admin_email=...
wp user create redactor redactor@... --role=author --user_pass=...
```

**Idempotency** — entrypoint hem boş volume'de hem de dolu volume'de çalışabilmeli. `make re`
container'ları siler ama volume'ler kalır; ikinci açılışta WordPress'i yeniden kurmaya
çalışırsa her şey bozulur. Kontrol basit: `wp-config.php` varsa kurulum adımını atla.

**MariaDB ilk açılış:** `mariadb-install-db` sistem tablolarını oluşturur → geçici sunucu
başlatılır → DB ve kullanıcı yaratılır, root şifresi kurulur, anonim kullanıcılar silinir →
geçici sunucu düzgünce kapatılır → `exec` ile gerçek sunucu başlar. Burada da kontrol:
`/var/lib/mysql/mysql` dizini varsa init'i atla.

**Hazırlık sırası problemi:** `depends_on` sadece **container başlama sırasını** garanti eder,
**servisin hazır olmasını** değil. MariaDB container'ı ayağa kalkmıştır ama henüz bağlantı
kabul etmiyor olabilir. WordPress entrypoint'i bu yüzden bekleme döngüsü içerir — ve bu döngü
**sınırlı** olmalıdır (N deneme sonra hata ile çık), `while true` **değil**.

---

## 4. Gelebilecek sorular ve cevapları

### Docker temelleri

**S: Docker nedir, VM'den farkı ne?**
VM donanımı sanallaştırır — hypervisor CPU, RAM, disk, ağ kartı taklit eder ve her VM kendi
kernel'ini boot eder. Docker işletim sistemini "sanallaştırır" — kernel paylaşılır, izolasyon
namespace ve cgroup ile sağlanır. VM'de boot onlarca saniye ve gigabyte'larca RAM; container'da
milisaniye ve megabyte'lar, çünkü container aslında sadece izole edilmiş bir process. Karşılığı
izolasyonun daha zayıf olması: kernel açığı container sınırını aşabilir, VM'de hipervizör
sınırını aşmak çok daha zordur.

**S: Bu projede neden hem VM hem Docker var?**
İki farklı seviyede iş yapıyorlar. VM, okulun makinesinden **host seviyesinde** izolasyon
sağlıyor — subject zaten her şeyin bir VM içinde olmasını istiyor. Docker ise o VM'in içinde üç
**servisi** birbirinden ayırıyor. NGINX, WordPress ve MariaDB için üç ayrı VM açmak üç kernel ve
gigabyte'larca RAM demekti; sonuçta üç daemon çalıştırıyoruz. Docker aynı ayrımı üç process
maliyetiyle veriyor.

**S: Image ile container arasındaki fark?**
Image salt okunur katmanlar + metadata; diskte durur, çalışmaz. Container bir image'ın üstüne
yazılabilir katman eklenip namespace'ler içinde başlatılmış hâli. Image sınıf, container nesne.

**S: Katman (layer) nedir, neden önemli?**
Her `RUN`/`COPY`/`ADD` yeni bir salt okunur katman üretir. Katmanlar değişmez ve cache'lenir.
İki sonucu var: (1) bir katmanda oluşturup sonraki katmanda sildiğin dosya image'ı küçültmez,
bu yüzden `apt-get install` ve `rm -rf /var/lib/apt/lists/*` aynı `RUN`'da; (2) bir katmana
yazılan şifre `docker history` ile okunabilir, bu yüzden Dockerfile'da şifre yasak.

**S: `docker compose` ile kullanılan image, kullanılmayandan farklı mı?**
Hayır — image birebir aynı. Fark image'da değil, yönetimindedir. Compose network, volume, env,
bağımlılık sırası ve yaşam döngüsünü versiyonlanabilir tek bir dosyada tanımlar; compose'suz
aynı şeyi terminalde onlarca `docker run` flag'iyle elle yaparsın. Compose bir orkestrasyon
katmanı, bir image formatı değil.

**S: `CMD` ile `ENTRYPOINT` farkı?**
`ENTRYPOINT` container'ın "ne olduğunu" belirler ve `docker run`'a verilen argümanlarla kolay
kolay ezilmez. `CMD` varsayılan argümanları verir ve `docker run image <komut>` ile ezilir. Bu
projede `ENTRYPOINT` kurulum script'i, `CMD` daemon: script `exec "$@"` ile `CMD`'yi çalıştırır.

**S: Neden `debian:bookworm`?**
Debian 13 *trixie* şu an stable, dolayısıyla penultimate stable Debian 12 *bookworm*. Subject
tam olarak bunu istiyor. `latest` yasak, ayrıca `latest` kayan bir hedef — bugün build olan
image yarın sessizce değişir.

**S: `.dockerignore` ne işe yarar?**
Build context'e (daemon'a gönderilen dosyalara) girmeyecekleri belirler. Hem build'i hızlandırır
hem de `secrets/` gibi dosyaların yanlışlıkla image'a kopyalanmasını engeller.

### PID 1 ve process yönetimi

**S: PID 1 neden özel?**
Kernel PID 1'e varsayılan sinyal handler'ı kurmaz. PID 1 `SIGTERM` için açık bir handler
tanımlamadıysa sinyal yok sayılır. `docker stop` de tam olarak PID 1'e `SIGTERM` yollar. Ayrıca
PID 1 zombie process'leri toplamakla yükümlüdür.

**S: `exec "$@"` niye yazıyorsun?**
`exec` yeni process başlatmaz, mevcut shell process'ini komutla **değiştirir**. Böylece daemon
PID 1 olur ve `SIGTERM`'i doğrudan alır. `exec` olmasaydı shell PID 1 kalır, daemon onun çocuğu
olurdu, `docker stop` 10 saniye bekleyip `SIGKILL` atardı — MariaDB için bu bozuk veri demek.

**S: `tail -f` neden yasak?**
Container'ı yapay olarak ayakta tutar. PID 1 servisle alakasız bir process olduğu için: servis
çökerse container ayakta kalır ve restart policy tetiklenmez, `docker stop` servisi düzgün
kapatmaz, loglar container log'una düşmez. Container "çalışıyor" görünür ama site ölüdür.

**S: `nginx -g "daemon off;"` niye?**
NGINX varsayılanda fork edip arka plana geçer, parent process çıkar. Container PID 1 çıktığı an
öldüğü için container hemen kapanır. `daemon off` NGINX'i ön planda tutar.

**S: Bir container'da neden tek process?**
Container bir servis sınırıdır. Tek process ile: `docker stop` doğru çalışır, restart policy
gerçekten servisi izler, loglar `docker logs`'a düşer, ölçekleme ve kaynak limiti servis bazında
anlamlıdır. Birden çok process istiyorsan bir init/supervisor gerekir ve bu container'ı bir
mini-VM'e dönüştürür — Docker'ın modeline aykırı.

### Ağ

**S: Docker network'ü basitçe anlat.** *(eval'da açıkça soruluyor)*
Docker host üzerinde sanal bir switch oluşturur. Her container kendi ağ namespace'ini ve kendi
IP'sini alır ve bu switch'e bağlanır. Aynı network'teki container'lar birbirini görür; farklı
network'tekiler göremez. Docker ayrıca `127.0.0.11`'de gömülü bir DNS çalıştırır, böylece
container'lar birbirini **servis adıyla** bulur — `wp-config.php`'de `mariadb` yazar, IP
yazmam.

**S: `network_mode: host` neden yasak?**
Container host'un ağ namespace'ini paylaşır: izolasyon tamamen kalkar, MariaDB'nin 3306'sı
anında VM arayüzünde açılır, servis keşfi kaybolur (her şey `127.0.0.1`), port çakışmaları
başlar. Projenin "tek giriş noktası 443" iddiası çöker.

**S: `--link` neden kullanılmıyor?**
Deprecate edilmiş eski mekanizma. Tek yönlüydü, container başlangıcında `/etc/hosts` girdisi ve
env değişkeni enjekte ederdi, hedef container yeniden başlayıp IP değiştirdiğinde bozulurdu.
Kullanıcı tanımlı network aynı işi DNS ile doğru yapıyor.

**S: `ports` ile `expose` farkı?**
`ports` host portunu container portuna bağlar — dışarıdan erişilebilir olur. `expose` sadece
metadata'dır, portu host'a açmaz. Bu projede `ports` yalnız nginx'te ve yalnız 443; MariaDB ve
php-fpm sadece `expose` kullanır, bu yüzden Docker network dışından erişilemezler.

**S: Container'lar birbirini nasıl buluyor?**
Docker'ın gömülü DNS'i ile, servis adı üzerinden. NGINX `fastcgi_pass wordpress:9000` der,
WordPress `DB_HOST=mariadb` der. Container yeniden başlayıp IP'si değişse bile isim çözümlenir.

**S: 80 portu neden kapalı?**
Subject NGINX'in tek giriş noktası olmasını ve **sadece 443** üzerinden çalışmasını istiyor.
Compose'da 80 publish edilmiyor ve nginx.conf'ta `listen 80` yok. Eval de `http://` ile
erişilememesini kontrol ediyor.

### Volume ve kalıcılık

**S: Named volume ile bind mount farkı?**
Named volume Docker'ın yönettiği, adı ve yaşam döngüsü olan bir nesnedir; `docker volume ls`'te
görünür, taşınabilirdir, izinleri image'dan alır. Bind mount sadece bir host yoludur; o makineye
bağlıdır, Docker tarafından yönetilmez, izin sorunları klasiktir. Named volume kalıcı servis
verisi için, bind mount geliştirme sırasında canlı kaynak kodu için.

**S: Named volume istiyorlar ama veri `/home/login/data`'da olacak — nasıl?**
Named volume'ü `local` driver'ın bind seçenekleriyle tanımlayarak: `type: none`, `o: bind`,
`device: /home/elikavak/data/wordpress`. Sonuç gerçek bir named volume'dür — adı var, yaşam
döngüsü var, compose ona adıyla referans veriyor, `docker volume ls`'te görünüyor. `driver_opts`
sadece byte'ların nerede duracağını söylüyor.

**S: Neden iki volume?**
İki servis iki farklı türde state'e sahip. `mariadb_data` → `/var/lib/mysql`, sadece MariaDB'nin.
`wordpress_data` → `/var/www/html`, **paylaşımlı**: WordPress PHP'yi çalıştırıp upload yazıyor,
NGINX aynı dosyalardan statik içeriği okuyor.

**S: `make down` veriyi siler mi?**
Hayır. `down` container'ları kaldırır, volume'lere dokunmaz. `make re` de veriyi korur. Sadece
`make fclean` volume'leri ve host'taki veriyi siler — ve bunu kasıtlı yapar.

**S: Reboot sonrası veri neden duruyor?** *(eval'ın Persistence adımı)*
Veri container'ın yazılabilir katmanında değil, host üzerindeki `/home/elikavak/data` altında
named volume olarak duruyor. Container'lar yok olup yeniden yaratılsa da volume aynı kalıyor,
yeni container aynı volume'ü mount ediyor.

### Güvenlik ve secrets

**S: Şifreleri nerede tutuyorsun?**
Credential olan her şey `secrets/` altında ayrı dosyalarda, compose'da `secrets:` olarak
tanımlı, container'a `/run/secrets/<ad>` altında mount ediliyor, entrypoint script'leri oradan
okuyor. Credential olmayan konfigürasyon (domain, DB adı, kullanıcı adları, site başlığı)
`srcs/.env` içinde. İkisi de `.gitignore`'da; repoda sadece `.example` şablonları var.

**S: Env variable yerine neden secret?**
Env variable `docker inspect` çıktısında ve `/proc/<pid>/environ` içinde düz metin görünür,
`ENV` ile yazılırsa image katmanına kalıcı olarak gömülür ve environment'ı döken her araçla
loglara sızabilir. Secret ise sadece runtime'da bir dosya olarak var olur; katmana yazılmaz,
`docker inspect`'te görünmez, process environment'ında bulunmaz.

**S: Docker secret'ları gerçekten güvenli mi?**
Swarm dışında tam anlamıyla değil — compose modunda arkalarında host üzerinde düz bir dosya var,
güvenlikleri o dosyanın izinlerine bağlı. Garanti ettikleri şey şu: şifre image katmanında
değil, `docker inspect`'te değil, process environment'ında değil. Bu üçü zaten sızıntıların
büyük kısmını kapatıyor.

**S: Şifreleri neden `echo` yerine `printf` ile yazıyorsun?**
`echo` sonuna newline ekler ve o newline şifrenin parçası olur — sonra giriş yapamazsın.

**S: Admin kullanıcı adı neden `admin` değil?**
Subject yasaklıyor. Ayrıca gerçek bir sertleştirme önlemi: `admin` her brute-force script'inin
denediği ilk kullanıcı adı. Bilinmeyen bir kullanıcı adı saldırganı iki bilinmeyene zorlar.

### TLS

**S: TLS'i nasıl kanıtlarsın?**
`openssl s_client -connect elikavak.42.fr:443 -tls1_2` el sıkışmayı tamamlar ve sertifikayı
basar. `-tls1_1` ile aynı komut başarısız olur — çünkü `nginx.conf` içinde
`ssl_protocols TLSv1.2 TLSv1.3;` yazıyor ve altındaki sürümler kapalı. Tarayıcıda da kilit
simgesine tıklayıp bağlantı detaylarından protokol sürümü görülebilir.

**S: Sertifika neden self-signed?**
`elikavak.42.fr` yerel bir alan adı; hiçbir public CA bunun için sertifika veremez, çünkü alan
adının kontrolü doğrulanamaz. Self-signed sertifika şifrelemeyi sağlar, sadece üçüncü taraf
kimlik doğrulaması yoktur. Tarayıcı uyarısı beklenen davranış ve eval'da da kabul ediliyor.

**S: TLS 1.2 ile 1.3 farkı?**
1.3 handshake'i 1 RTT'ye indirir, eski ve kırılgan cipher'ları (RC4, 3DES, static RSA, CBC
MAC-then-encrypt) tamamen kaldırır, forward secrecy'yi zorunlu kılar.

### Servisler

**S: NGINX ile php-fpm nasıl konuşuyor?**
FastCGI protokolüyle, TCP 9000 üzerinden. `nginx.conf`'ta `location ~ \.php$` bloğunda
`fastcgi_pass wordpress:9000;` var. `proxy_pass` kullanamam çünkü o HTTP konuşur; php-fpm HTTP
değil FastCGI konuşur.

**S: Neden Unix socket değil TCP?**
Unix socket bir dosya sistemi nesnesidir ve container'ın kendi mount namespace'i içinde yaşar.
Başka bir container'daki NGINX ona erişemez. Bu yüzden `www.conf`'ta `listen = 0.0.0.0:9000`.

**S: PHP-FPM nedir?**
FastCGI Process Manager — PHP yorumlayıcısını kalıcı bir worker havuzu olarak çalıştırır. Her
istekte yeni process başlatan klasik CGI'ye göre çok daha hızlıdır ve worker sayısı
yapılandırılabilir.

**S: Veritabanına nasıl girilir?** *(eval'da açıkça soruluyor)*
```bash
docker exec -it mariadb mariadb -u root -p
```
Şifre `secrets/db_root_password.txt` içinde. Sonra `SHOW DATABASES;` ve
`USE wordpress; SHOW TABLES;` ile WordPress tablolarının (`wp_posts`, `wp_users` …) dolu
olduğunu gösterebilirim.

**S: WordPress kurulum ekranı neden çıkmıyor?**
Entrypoint WP-CLI ile `wp core install` çalıştırıp kurulumu ilk açılışta tamamlıyor, ayrıca iki
kullanıcıyı da oluşturuyor. Sihirbaz sadece kurulmamış WordPress'te çıkar.

**S: `depends_on` MariaDB'nin hazır olmasını garanti eder mi?**
Hayır. Sadece container'ların **başlama sırasını** belirler; MariaDB container'ı ayaktayken
henüz bağlantı kabul etmiyor olabilir. Bu yüzden WordPress entrypoint'i DB'ye bağlanabilene
kadar bekleyen sınırlı bir deneme döngüsü içeriyor — sınırlı, çünkü `while true` yasak ve
sessizce asılı kalmaktansa hata verip çıkmak daha doğru.

**S: Bu dizin yapısı neden böyle?** *(eval'da soruluyor)*
Subject'in dayattığı yapı aynı zamanda mantıklı bir yapı: `Makefile` kökte tek giriş noktası,
konfigürasyonun tamamı `srcs/` altında, her servis `srcs/requirements/<servis>/` altında kendi
`Dockerfile`, `conf/` ve `tools/` dizinine sahip. Böylece bir servise dokunmak diğerlerini
etkilemez, her image'ın build context'i kendi dizini kadar dar kalır ve "bu ayar nerede?"
sorusunun cevabı her zaman tek bir yerdir.

### Makefile ve compose

**S: `.PHONY` ne işe yarar?**
Hedefin bir dosya üretmediğini söyler. Olmasaydı, dizinde `clean` adlı bir dosya varsa `make
clean` "zaten güncel" deyip hiçbir şey yapmazdı.

**S: `make re` ile `make fclean` farkı?**
`re` image'ları yeniden build edip stack'i yeniden başlatır, **veriyi korur**. `fclean`
container, image, volume ve host'taki veriyi siler — sıfırdan kurulumu test etmek için.

**S: `restart:` politikaları neler?**
`no`, `on-failure[:n]`, `always`, `unless-stopped`. Bu projede `unless-stopped`: çöken container
otomatik geri gelir, ama debug için bilerek durdurduğum container durdurulmuş kalır.

**S: Compose neden network ve volume adlarına önek ekliyor?**
Proje adı öneki (`srcs_`) çakışmayı önler; aynı makinede iki farklı proje aynı adlı network'e
sahip olabilir. Proje adı varsayılan olarak compose dosyasının bulunduğu dizinden gelir — burada
`srcs`.

---

## 5. "Configuration modification" adımına hazırlık

Eval'ın 12. adımı: değerlendirici **bir servisin konfigürasyonunu canlı olarak değiştirmeni**
istiyor (örnek olarak port veriliyor), sen rebuild edip yeniden başlatıyorsun ve servis
çalışmaya devam etmek zorunda. Yapamazsan eval biter.

Bu adımı önceden **prova et**. En olası üç senaryo:

### Senaryo A — NGINX'in dış portu (443 → 8443)

En muhtemel istek. İki dosya:

1. `srcs/.env` içinde port değişkenini güncelle (bu yüzden portu baştan değişkenleştir).
2. `srcs/nginx/conf/nginx.conf` içindeki `listen 443 ssl;` satırını güncelle.

```bash
make re
```

Test:

```bash
curl -kI https://elikavak.42.fr:8443
```

> **Hazırlık tavsiyesi:** `docker-compose.yml`'de portu `"${NGINX_PORT}:${NGINX_PORT}"` şeklinde
> yaz ve `.env`'e `NGINX_PORT=443` koy. Böylece compose tarafı tek satır değişiklikle hallolur.

### Senaryo B — php-fpm portu (9000 → 9001)

Üç yer, hepsi build zamanı konfigürasyonu:

1. `srcs/requirements/wordpress/conf/www.conf` → `listen = 0.0.0.0:9001`
2. `srcs/requirements/nginx/conf/nginx.conf` → `fastcgi_pass wordpress:9001;`
3. `docker-compose.yml` → `expose: - "9001"`

```bash
make re
```

Buradaki püf nokta: `fastcgi_pass` ile `listen` **aynı** olmak zorunda. Birini unutursan
`502 Bad Gateway` alırsın — hatanın nerede olduğunu bilmek 30 saniye kazandırır.

### Senaryo C — MariaDB portu (3306 → 3307) — **dikkat, tuzak var**

1. `srcs/requirements/mariadb/conf/50-server.cnf` → `port = 3307`
2. `docker-compose.yml` → `expose: - "3307"`
3. **`wp-config.php` içindeki `DB_HOST`** → `mariadb:3307`

Üçüncü madde tuzak: `wp-config.php` **volume'de duruyor**, image'da değil. `make re` onu
yeniden üretmez, çünkü entrypoint "dosya varsa kurulumu atla" mantığıyla çalışıyor. Yani
sadece config dosyalarını değiştirip rebuild etmek yetmez.

İki çözümün var, savunmada birini seçip gerekçesini söyle:

```bash
docker exec wordpress wp --allow-root --path=/var/www/html config set DB_HOST mariadb:3307
```

```bash
docker compose -f srcs/docker-compose.yml restart wordpress
```

veya veriyi feda edip sıfırdan:

```bash
make fclean && make
```

Birincisi hızlı ve veriyi korur; savunmada tercih edilecek olan bu. **Bu senaryoyu mutlaka bir
kez dene** — hazırlıksız yakalanırsan eval burada biter.

---

## 6. Savunma öncesi kontrol listesi

### Bir gün önce

- [ ] Değerlendiricinin purge komutunu çalıştır, sonra `make` → site açılıyor mu?
- [ ] VM'i **gerçekten reboot et**, compose'u tekrar ayağa kaldır, WordPress'te yaptığın
      değişiklik duruyor mu?
- [ ] Repoyu **boş bir dizine** `git clone` et, `.env` ve secret'ları sıfırdan oluşturup `make`
      çalıştır. Klonda `.env` ve `secrets/*.txt` **olmamalı**.
- [ ] Bölüm 5'teki üç senaryonun en az ikisini prova et.
- [ ] `git log -p | grep -iE 'password|secret|api[_-]?key'` → gerçek bir değer çıkmamalı.
- [ ] WordPress'te bir sayfa düzenle ve bir yorum ekle — eval bunları test ediyor.

### Savunma sırasında hazır bulunacak komutlar

```bash
docker compose -f srcs/docker-compose.yml ps
```

```bash
docker exec nginx ps -eo pid,comm
```

```bash
docker volume ls && docker volume inspect srcs_wordpress_data
```

```bash
docker network ls && docker exec wordpress getent hosts mariadb
```

```bash
sudo ss -tlnp | grep -E ':(443|3306|9000)'
```

```bash
openssl s_client -connect elikavak.42.fr:443 -tls1_2 </dev/null
```

```bash
docker exec -it mariadb mariadb -u root -p -e "USE wordpress; SHOW TABLES;"
```

### Sözlü olarak hazır olması gerekenler

Eval'ın "Activity overview" bölümü bunları **açıkça** soruyor:

1. Docker ve docker compose nasıl çalışır → §3.1, §3.2
2. Compose ile / compose'suz image farkı → §3.2 (cevap: image aynı, yönetim farklı)
3. Docker'ın VM'e göre avantajı → §4, ilk soru
4. Bu dizin yapısının mantığı → §4, "Bu dizin yapısı neden böyle?"

Ayrı olarak "Docker Network" bölümünde **network'ün basit bir açıklaması** isteniyor (§3.5) ve
"MariaDB" bölümünde **veritabanına nasıl girildiğini anlatman** isteniyor (§4).

---

## 7. Bonus (referans)

Mandatory kusursuz değilse **hiç değerlendirilmiyor**. Her bonus +1 puan, her biri için ayrı
Dockerfile ve gerekiyorsa ayrı volume şart.

| Bonus | Not |
| ----- | --- |
| Redis cache | WordPress için object cache; bir plugin + Redis container'ı |
| FTP server | WordPress volume'üne bakan bir FTP container'ı |
| Statik site | PHP **hariç** herhangi bir dil |
| Adminer | Web tabanlı DB yönetim arayüzü |
| Serbest seçim servis | Savunmada **neden yararlı olduğunu gerekçelendirmen** gerekiyor |
