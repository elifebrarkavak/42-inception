# Docker ve Docker Compose — Konu Anlatımı

> Sıfırdan başlayan bir anlatım. Her kavram önce "hangi problemi çözüyor" sorusuyla açılıyor,
> sonra nasıl çalıştığı, en sonda Inception projesinde nereye denk geldiği. Savunmaya
> hazırlanırken [SAVUNMA_NOTLARI.md](SAVUNMA_NOTLARI.md) ile birlikte kullan.

---

## İçindekiler

1. [Docker hangi problemi çözüyor](#1-docker-hangi-problemi-çözüyor)
2. [Docker'ın altındaki kernel teknolojileri](#2-dockerın-altındaki-kernel-teknolojileri)
3. [Mimari: CLI, daemon, registry](#3-mimari-cli-daemon-registry)
4. [Image, katman ve container](#4-image-katman-ve-container)
5. [Dockerfile](#5-dockerfile)
6. [Build süreci ve cache](#6-build-süreci-ve-cache)
7. [Container yaşam döngüsü](#7-container-yaşam-döngüsü)
8. [Process modeli: PID 1, ENTRYPOINT, sinyaller](#8-process-modeli-pid-1-entrypoint-sinyaller)
9. [Veri: volume ve bind mount](#9-veri-volume-ve-bind-mount)
10. [Ağ](#10-ağ)
11. [Docker Compose nedir](#11-docker-compose-nedir)
12. [Compose dosyası anatomisi](#12-compose-dosyası-anatomisi)
13. [Değişkenler: .env, environment, secrets](#13-değişkenler-env-environment-secrets)
14. [Compose komutları](#14-compose-komutları)
15. [Hepsi bir arada: Inception](#15-hepsi-bir-arada-inception)
16. [Sık yapılan hatalar](#16-sık-yapılan-hatalar)
17. [Komut sözlüğü](#17-komut-sözlüğü)

---

## 1. Docker hangi problemi çözüyor

### Problem 1 — "Benim makinemde çalışıyordu"

Bir uygulama çalışmak için sadece kendi kodundan ibaret değildir. Arkasında bir sürü varsayım
vardır: PHP 8.2 kurulu, şu extension'lar aktif, şu sistem kütüphanesi şu sürümde, şu dizin şu
izinlerle var, şu env değişkeni tanımlı.

Bu varsayımların hepsi **işletim sisteminde** yaşar, kodun içinde değil. Kodu başka bir makineye
kopyaladığında varsayımlar gelmez. Sonuç: geliştiricide çalışan, sunucuda çalışmayan uygulama.

Docker'ın cevabı: **uygulamayı bağımlılıklarıyla birlikte paketle.** Paketin adı *image*.
Image'ın içinde uygulama, kütüphaneler, konfigürasyon, hatta bir mini işletim sistemi dosya
ağacı var. Bu paketi çalıştıran her makinede aynı ortam oluşur.

### Problem 2 — İzolasyon

Aynı sunucuda iki uygulama çalıştırmak istiyorsun. Biri PHP 7.4, diğeri PHP 8.2 istiyor. Ya da
ikisi de 80 portunu istiyor. Ya da biri diğerinin dosyalarını okuyabiliyor.

Klasik çözüm: her uygulamaya bir sanal makine. Ama bu, üç daemon çalıştırmak için üç kernel boot
etmek demek — gigabyte'larca RAM, dakikalarca boot süresi.

Docker'ın cevabı: **kernel'i paylaş, gerisini ayır.** Container'lar aynı kernel üzerinde çalışır
ama birbirlerinin process'lerini, dosya sistemini, ağını göremezler.

### Problem 3 — Tekrar üretilebilirlik

Sunucuyu kuran kişi ayrılırsa, kurulumun nasıl yapıldığını kimse bilmez. Docker'da kurulum
adımları `Dockerfile` denen bir metin dosyasındadır — Git'te versiyonlanır, okunur, tekrar
çalıştırılır.

### Peki Docker bir sanal makine mi?

**Hayır.** Bu ayrımı netleştirmek en kritik nokta:

```
Sanal makine                          Container
─────────────                         ─────────
┌───────────┐ ┌───────────┐           ┌───────────┐ ┌───────────┐
│  App A    │ │  App B    │           │  App A    │ │  App B    │
├───────────┤ ├───────────┤           ├───────────┤ ├───────────┤
│ Kütüphane │ │ Kütüphane │           │ Kütüphane │ │ Kütüphane │
├───────────┤ ├───────────┤           └───────────┘ └───────────┘
│ KERNEL A  │ │ KERNEL B  │  ← her VM         ↓            ↓
├───────────┴─┴───────────┤    kendi     ┌─────────────────────┐
│      Hypervisor         │    kernel'i  │   Docker Engine     │
├─────────────────────────┤              ├─────────────────────┤
│      Host kernel        │              │   TEK Host kernel   │
├─────────────────────────┤              ├─────────────────────┤
│      Donanım            │              │      Donanım        │
└─────────────────────────┘              └─────────────────────┘
```

| | Sanal makine | Container |
| --- | --- | --- |
| Sanallaştırılan | **Donanım** (CPU, RAM, disk, NIC taklit edilir) | **İşletim sistemi** (kernel paylaşılır) |
| Kernel | Her VM kendi kernel'ini boot eder | Hepsi host kernel'ini kullanır |
| Başlama süresi | Onlarca saniye — gerçek bir boot | Milisaniye — sadece process başlıyor |
| Bellek | Gigabyte, peşinen ayrılır | Megabyte, sadece kullanılan kadar |
| İzolasyon | Çok güçlü (donanım sınırı) | Daha zayıf (kernel sınırı) |
| Taşınabilirlik | Devasa image dosyası | Küçük image + Git'teki tarif |

**Container aslında nedir?** İzole edilmiş, sınırlandırılmış ve kendi dosya sistemi görünümü
verilmiş **bir process**. Başka bir şey değil. Host'ta `ps aux` çalıştırırsan container'daki
NGINX'i normal bir process olarak görürsün.

Bunun bir sonucu var: **container kernel'i host'unkidir.** Windows üzerinde Linux container
çalıştırırsan arka planda bir Linux VM vardır — Docker Desktop bunu senin için kurar.

---

## 2. Docker'ın altındaki kernel teknolojileri

Docker sihir yapmaz; Linux kernel'inin üç özelliğini birleştirir.

### 2.1 Namespace — "ne görüyorsun"

Namespace, bir process'in sistemin hangi kısmını görebileceğini sınırlar. Kernel'de birden fazla
namespace türü var:

| Namespace | İzole ettiği şey | Container'daki sonucu |
| --------- | ---------------- | --------------------- |
| `pid` | Process tablosu | Container kendi process'lerini görür, host'unkileri görmez. İlk process **PID 1** olur |
| `net` | Ağ arayüzleri, route tablosu, portlar | Container'ın kendi IP'si ve kendi port alanı olur |
| `mnt` | Mount noktaları | Container kendi dosya sistemi ağacını görür |
| `uts` | Hostname, domain adı | Container'ın kendi hostname'i olur |
| `ipc` | Paylaşımlı bellek, semafor | Process'ler arası iletişim izole olur |
| `user` | UID/GID eşleme | Container içinde root, host'ta yetkisiz kullanıcı olabilir |
| `cgroup` | cgroup hiyerarşisi görünümü | Container kendi limitlerini görür |

**Somut örnek:** İki container aynı anda 80 portunu dinleyebilir. Çünkü her biri kendi `net`
namespace'inde ve orada 80 portu boştur. Çakışma ancak host'a publish ederken olur.

### 2.2 cgroup — "ne kadar kullanabilirsin"

Control group, bir process grubunun kaynak kullanımını sınırlar ve ölçer: CPU payı, RAM tavanı,
disk I/O bant genişliği, process sayısı.

```bash
docker run --memory=512m --cpus=1.5 my-image
```

Namespace *görünürlüğü*, cgroup *tüketimi* kısıtlar. İkisi birlikte izolasyonu oluşturur.

### 2.3 Union filesystem — katmanları birleştirmek

Modern Docker `overlay2` kullanır. Fikir şu: birden fazla dizini üst üste bindirip tek bir
dizinmiş gibi göstermek.

```
merged/  (container'ın gördüğü)     ← görünen tek dosya sistemi
  ↑
upperdir/ (yazılabilir katman)      ← container'ın yaptığı değişiklikler
  ↑
lowerdir/ (image katmanları)        ← salt okunur, paylaşımlı
```

**Copy-on-write (CoW):** Container salt okunur bir katmandaki dosyayı değiştirmek isterse, dosya
önce yazılabilir katmana **kopyalanır**, değişiklik orada yapılır. Alt katman hiç değişmez.

Bunun iki büyük sonucu var:

1. **Aynı image'dan 10 container** çalıştırırsan 10 kopya disk kaplamaz. Salt okunur katmanlar
   paylaşılır, her container'ın sadece kendi yazılabilir katmanı ayrıdır.
2. **Container silinince yazılabilir katman da silinir.** Kalıcı olması gereken veri buraya
   yazılmamalı — *volume* konusunun bütün sebebi bu.

---

## 3. Mimari: CLI, daemon, registry

`docker` komutu yazdığında iş yapan şey o komut değil.

```
   docker CLI            dockerd                 containerd            runc
  (senin yazdığın)  →  (Docker daemon)   →   (container runtime)  →  (process başlatıcı)
        │                    │                                            │
        │  REST API          │  image build, network, volume yönetimi     │
        └────────────────────┘                                    kernel'e namespace
                             │                                    ve cgroup kurar
                             ↓
                        Registry (Docker Hub vb.)
```

- **docker CLI** — senin arayüzün. Komutu bir REST çağrısına çevirip daemon'a yollar.
- **dockerd (daemon)** — asıl iş burada: image build eder, network ve volume yönetir,
  container'ların yaşam döngüsünü tutar. Root yetkisiyle çalışır.
- **containerd / runc** — container'ı fiilen başlatan alt katman. `runc` namespace ve cgroup'ları
  kurup process'i çalıştırır.
- **Registry** — image deposu. Docker Hub varsayılan olanıdır.

> **Inception notu:** Kullanıcın `docker` grubunda değilse her komut `sudo` ister — çünkü CLI,
> daemon'un root'a ait soketiyle konuşur.

> **Inception kuralı:** Registry'den **hazır image çekmek yasak** (Alpine/Debian hariç).
> `wordpress`, `mariadb`, `nginx` image'larını kendin build edeceksin.

---

## 4. Image, katman ve container

### Image nedir

Bir image üç şeyden oluşur:

1. **Katmanlar** — her biri bir tar arşivi, dosya sistemi farkını içerir.
2. **Config** — çalıştırma metadata'sı: `CMD`, `ENTRYPOINT`, `ENV`, `WORKDIR`, `EXPOSE`, `USER`.
3. **Manifest** — hangi katmanlar hangi sırada, hangi config.

Image **içerik adresli**dir: her katmanın bir SHA256 digest'i vardır. İçerik aynıysa digest de
aynıdır — bu yüzden aynı katman iki farklı image'da paylaşılabilir.

### Tag ve digest

```
debian:bookworm
└─────┘ └──────┘
  repo    tag
```

Tag **hareketli bir etikettir**. `debian:bookworm` bugün bir digest'i, güvenlik güncellemesinden
sonra başka bir digest'i gösterebilir. `latest` ise bunun en uç hâli: hiçbir sürüm garantisi
vermez, sadece "tag belirtilmezse bu" anlamına gelir — "en son sürüm" demek bile değildir.

> **Inception kuralı:** `latest` yasak. `FROM debian:bookworm` gibi açık bir tag zorunlu.

### Container nedir

Container = image + üstüne eklenmiş yazılabilir katman + namespace'ler içinde çalışan process.

| Image | Container |
| ----- | --------- |
| Salt okunur | Yazılabilir katmanı var |
| Diskte durur, çalışmaz | Çalışan bir process |
| `docker build` üretir | `docker run` üretir |
| Sınıf (class) | Nesne (instance) |
| Paylaşılabilir | Tekildir |

Bir image'dan istediğin kadar container üretebilirsin; hepsi aynı salt okunur katmanları
paylaşır.

### Katmanları görmek

```bash
docker history nginx
```

Her satır bir katman ve onu üreten komut. **Bu komut şunu da gösterir:** Dockerfile'a yazdığın
her şey — şifreler dahil — burada okunabilir. `ENV DB_PASSWORD=1234` yazarsan, o şifre image'ı
eline geçiren herkes tarafından görülebilir.

---

## 5. Dockerfile

Image'ın tarifi. Her satır bir direktif, çoğu yeni bir katman üretir.

### 5.1 `FROM` — temel image

```dockerfile
FROM debian:bookworm
```

Her Dockerfile bununla başlar. Üzerine inşa edeceğin taban.

`FROM scratch` tamamen boş bir temeldir — statik derlenmiş tek binary'ler için.

> **Inception:** Alpine veya Debian'ın **penultimate stable** (sondan bir önceki kararlı) sürümü
> zorunlu. Debian 13 *trixie* stable olduğu için penultimate Debian 12 *bookworm*.

### 5.2 `RUN` — build sırasında komut çalıştır

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends nginx \
    && rm -rf /var/lib/apt/lists/*
```

**Neden hepsi tek `RUN`'da?** Katmanlar değişmezdir. Ayrı `RUN`'larda yazarsan:

```dockerfile
RUN apt-get update                    # katman 1: apt listeleri yazıldı
RUN apt-get install -y nginx          # katman 2: nginx kuruldu
RUN rm -rf /var/lib/apt/lists/*       # katman 3: listeler "silindi"
```

Katman 3 silme işlemini kaydeder ama **katman 1 hâlâ dosyaları içerir**. Image küçülmez, sadece
görünmez olur. Aynısı şifreler için de geçerli: bir katmanda yazıp diğerinde silmek onu yok
etmez.

`--no-install-recommends` önerilen ama gereksiz paketleri atlar; image'ı belirgin şekilde
küçültür.

### 5.3 `COPY` ve `ADD` — dosya taşı

```dockerfile
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY tools/setup.sh /usr/local/bin/
```

`COPY` yereldeki dosyayı image'a kopyalar. `ADD` bunun üstüne URL indirme ve otomatik tar açma
yapar — **öngörülemez olduğu için `COPY` tercih edilir**.

Kaynak yolu **build context**'e görelidir (bkz. §6).

### 5.4 `ENV` ve `ARG` — değişkenler

```dockerfile
ARG PHP_VERSION=8.2          # sadece build sırasında
ENV PATH=/usr/local/bin:$PATH  # build + runtime
```

| | `ARG` | `ENV` |
| --- | --- | --- |
| Ne zaman geçerli | Sadece build | Build **ve** container çalışırken |
| Container içinden görülür mü | Hayır | **Evet** |
| Nereden verilir | `docker build --build-arg` | Dockerfile veya `docker run -e` |

> **İkisi de şifre için uygun değil.** `ENV` container environment'ında ve `docker inspect`'te
> görünür. `ARG` build geçmişinde kalır. Şifre için *secret* kullanılır (§13).

### 5.5 `WORKDIR`, `USER`, `EXPOSE`

```dockerfile
WORKDIR /var/www/html    # sonraki komutların çalışma dizini (yoksa oluşturur)
USER www-data            # bundan sonrası bu kullanıcıyla
EXPOSE 9000              # "bu container 9000'i dinler" — sadece belge
```

**`EXPOSE` portu açmaz.** Sadece dokümantasyondur. Portu host'a açan şey `docker run -p` veya
compose'daki `ports:`.

### 5.6 `CMD` ve `ENTRYPOINT` — container ne çalıştıracak

En çok karıştırılan ikili.

- **`ENTRYPOINT`** — container'ın *ne olduğu*. Kolay ezilmez.
- **`CMD`** — *varsayılan argümanlar*. `docker run image <komut>` ile ezilir.

```dockerfile
ENTRYPOINT ["setup.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

Çalışacak komut: `setup.sh nginx -g "daemon off;"`. Yani `CMD`, `ENTRYPOINT`'e **argüman olarak**
geçer. `setup.sh` içinde `exec "$@"` yazarsan bu argümanlar çalıştırılır.

**Exec form ve shell form — kritik fark:**

| Yazım | Nasıl çalışır |
| ----- | ------------- |
| `CMD ["nginx", "-g", "daemon off;"]` (exec form, JSON) | Doğrudan çalıştırılır. Process **PID 1** olur |
| `CMD nginx -g "daemon off;"` (shell form) | `/bin/sh -c "..."` içine sarılır. **PID 1 shell olur** |

Shell form'da sinyaller uygulamaya ulaşmaz (bkz. §8). **Her zaman exec form kullan.**

Kombinasyon tablosu:

| Dockerfile | `docker run image` çalıştırır | `docker run image ls` çalıştırır |
| ---------- | ----------------------------- | -------------------------------- |
| `CMD ["a"]` | `a` | `ls` |
| `ENTRYPOINT ["a"]` | `a` | `a ls` |
| `ENTRYPOINT ["a"]` + `CMD ["b"]` | `a b` | `a ls` |

### 5.7 `VOLUME`, `HEALTHCHECK`, `STOPSIGNAL`

```dockerfile
VOLUME /var/lib/mysql        # bu yol için anonim volume oluştur
HEALTHCHECK --interval=30s CMD curl -f http://localhost/ || exit 1
STOPSIGNAL SIGQUIT           # docker stop'un yollayacağı sinyali değiştir
```

`VOLUME` direktifi **anonim** volume üretir — adı olmayan, takip etmesi zor. Inception'da
volume'leri compose'da adlandırarak tanımlamak çok daha doğru.

### 5.8 `.dockerignore`

`.gitignore` gibi çalışır ama build context için. Buraya yazdıkların daemon'a hiç gönderilmez.

```
.git
secrets/
*.md
```

Hem build'i hızlandırır hem de hassas dosyaların yanlışlıkla image'a girmesini engeller.

---

## 6. Build süreci ve cache

```bash
docker build -t nginx:v1 .
```

Sondaki `.` **build context**'tir: o dizindeki her şey daemon'a gönderilir. `COPY` sadece bu
context içinden kopyalayabilir — `COPY ../başka/yer` çalışmaz.

> Context'i dar tut. Kök dizini context yapmak, `.git` dahil her şeyi daemon'a yollamak demektir.
> Inception'da her servisin context'i kendi `srcs/requirements/<servis>/` dizinidir.

### Cache nasıl çalışır

Docker her direktif için "bu adımı daha önce aynı girdiyle çalıştırdım mı" diye bakar. Evet ise
katmanı yeniden kullanır.

Cache **şu durumlarda geçersizleşir**:

- Direktifin metni değiştiyse.
- `COPY`/`ADD` için: kopyalanan dosyaların içeriği değiştiyse.
- **Bir adım geçersizleştiyse, ondan sonraki tüm adımlar da geçersizleşir.**

Son kural yazım sırasını belirler: **az değişen üstte, çok değişen altta.**

```dockerfile
FROM debian:bookworm

# Nadiren değişir → cache'te kalsın, en üstte
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

# Sık değişir → en altta
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
```

Konfigürasyonu değiştirdiğinde sadece son satır yeniden çalışır, paket kurulumu cache'ten gelir.
Tersini yazsaydın her config değişikliğinde paketler baştan kurulurdu.

Cache'i bilerek atlamak:

```bash
docker build --no-cache -t nginx:v1 .
```

---

## 7. Container yaşam döngüsü

```
          docker create          docker start
 image ──────────────────→ created ──────────→ running
                                                 │  │
                                    docker pause │  │ docker stop
                                                 ↓  ↓
                                              paused  exited
                                                       │
                                            docker rm  ↓
                                                   (silindi)
```

`docker run` = `create` + `start`.

Temel komutlar:

```bash
docker run -d --name web nginx:v1     # arka planda başlat
docker ps                              # çalışanlar
docker ps -a                           # hepsi (exited dahil)
docker logs -f web                     # logları takip et
docker exec -it web bash               # çalışan container'da shell aç
docker stop web                        # SIGTERM, 10s bekle, SIGKILL
docker rm web                          # sil
docker inspect web                     # tüm metadata (JSON)
```

**`run` ile `exec` farkı:** `run` **yeni** container yaratır. `exec` **zaten çalışan**
container'da ek bir process başlatır. Debug için `exec` kullanılır.

### Container ne zaman ölür

**PID 1 çıktığında.** Başka bir kural yok. Container "ayakta kalmaz", içindeki ana process
çalıştığı sürece yaşar.

Bu yüzden servisleri **ön planda** çalıştırmak zorundasın:

| Servis | Yanlış | Doğru | Neden |
| ------ | ------ | ----- | ----- |
| NGINX | `nginx` | `nginx -g "daemon off;"` | Varsayılanda fork edip arka plana geçer, parent çıkar |
| PHP-FPM | `php-fpm8.2` | `php-fpm8.2 -F` | `-F` = foreground |
| MariaDB | `mysqld_safe` | `mariadbd` | `mysqld_safe` bir sarmalayıcı script |

### Restart politikaları

```yaml
restart: unless-stopped
```

| Değer | Davranış |
| ----- | -------- |
| `no` | Varsayılan. Yeniden başlatma yok |
| `on-failure[:n]` | Sadece sıfırdan farklı çıkış kodunda, en fazla n kez |
| `always` | Her durumda; daemon yeniden başlarsa da |
| `unless-stopped` | `always` gibi, ama elle durdurulmuşsa daemon restart'ında başlatmaz |

> **Inception:** Container'ların çökme durumunda yeniden başlaması zorunlu.

---

## 8. Process modeli: PID 1, ENTRYPOINT, sinyaller

Bu bölüm Inception'ın en çok soru gelen kısmı.

### PID 1 neden özel

Linux'ta PID 1 geleneksel olarak `init`tir ve kernel ona **özel davranır**:

> Kernel, PID 1 için varsayılan sinyal handler'larını kurmaz. PID 1 bir sinyal için **açıkça**
> handler tanımlamamışsa, o sinyal sessizce yok sayılır.

Normal bir process `SIGTERM` alınca varsayılan davranışla ölür. PID 1 ölmez — hiçbir şey olmaz.

### Bunun container'da sonucu

`docker stop` şunu yapar:

1. PID 1'e `SIGTERM` gönderir.
2. 10 saniye bekler.
3. Hâlâ yaşıyorsa `SIGKILL` gönderir (bu sinyal yok sayılamaz).

PID 1 sinyali işlemeyen bir shell script'se, her `docker stop` 10 saniye sürer ve process
**sert** öldürülür. MariaDB için bu, açık transaction'lar ve flush edilmemiş buffer'lar demektir
— yani **bozuk veritabanı**.

### Çözüm: `exec`

```bash
#!/bin/sh
# kurulum işleri...
exec "$@"
```

`exec` **yeni process başlatmaz**. Mevcut process'in bellek görüntüsünü verilen komutla
**değiştirir**. PID aynı kalır. Yani shell PID 1'di, artık NGINX PID 1.

```
exec YOK:                          exec VAR:
  PID 1: sh setup.sh                 PID 1: nginx    ← sinyali doğrudan alır
    └─ PID 7: nginx                  (shell yok oldu)
       ↑ sinyal buraya ulaşmaz
```

Doğrulama:

```bash
docker exec nginx ps -eo pid,comm
```

PID 1'de daemon görünmeli, `sh` veya `bash` değil.

### `tail -f` neden yasak

Container'ı ayakta tutmak için `tail -f /dev/null` yazmak yaygın bir hiledir. Sonuçları:

- PID 1 servisle alakasız → **servis çökse bile container ayakta kalır**, restart policy
  tetiklenmez. Container "healthy" görünür, site ölüdür.
- `docker stop` servisi düzgün kapatmaz.
- Servisin logları `docker logs`'a düşmez.

Bu bir çözüm değil, semptomu gizlemektir. Subject ve eval açıkça yasaklıyor: `tail -f`,
`sleep infinity`, `while true`, `bash`.

### Bekleme döngüsü nasıl yazılır

WordPress, MariaDB hazır olmadan bağlanamaz. Ama `while true` yasak. Doğrusu **sınırlı** bir
döngü:

```bash
i=0
while [ $i -lt 30 ]; do
    if mariadb -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$PASS" -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 1
done
[ $i -lt 30 ] || { echo "MariaDB'ye 30 saniyede ulaşılamadı" >&2; exit 1; }
```

Sonsuz değil, başarısız olursa **gürültülü şekilde** hata verip çıkıyor. Sessizce asılı kalan
bir container'dan çok daha iyi.

### Idempotency

Entrypoint hem **boş** volume'de hem de **dolu** volume'de çalışabilmeli. `make re`
container'ları siler ama volume'ler kalır — ikinci açılışta kurulum tekrar çalışırsa her şey
bozulur.

```bash
if [ -f /var/www/html/wp-config.php ]; then
    echo "WordPress zaten kurulu, kurulum atlanıyor."
else
    # kurulum...
fi
exec "$@"
```

---

## 9. Veri: volume ve bind mount

### Problem

Container'ın yazılabilir katmanı container ile birlikte silinir. Veritabanını oraya yazarsan ilk
`docker rm`'de her şey gider.

Docker'ın üç çözümü var:

| Tür | Nerede durur | Kullanım |
| --- | ------------ | -------- |
| **Named volume** | `/var/lib/docker/volumes/<ad>/_data` | Kalıcı servis verisi |
| **Bind mount** | Belirttiğin herhangi bir host yolu | Geliştirmede canlı kaynak kodu |
| **tmpfs** | RAM (diske hiç yazılmaz) | Geçici sırlar, cache |

### Named volume

```bash
docker volume create db_data
docker run -v db_data:/var/lib/mysql mariadb:v1
```

- Docker yönetir, adı ve yaşam döngüsü vardır.
- `docker volume ls`, `inspect`, `rm` ile yönetilir.
- İlk mount'ta image'daki dizin içeriğiyle **doldurulur** ve izinler image'dan gelir.
- Compose dosyası her makinede çalışır — host yolu bilgisi gerekmez.

### Bind mount

```bash
docker run -v /home/user/site:/var/www/html nginx:v1
```

- Sadece bir host yolu. Docker yönetmez.
- Host'taki izinler geçerli olur → klasik "permission denied".
- Mount edilen dizin image'daki içeriği **gizler** (doldurmaz, üstünü örter).
- O makineye bağlıdır; yol yoksa patlar.

### Karşılaştırma

| | Named volume | Bind mount |
| --- | --- | --- |
| Yöneten | Docker | Sen |
| `docker volume ls`'te | Görünür | Görünmez |
| İzinler | Image'dan alınır | Host'tan gelir |
| Taşınabilirlik | Yüksek | Makineye bağlı |
| İlk mount davranışı | Image içeriğiyle dolar | Image içeriğini gizler |
| Tipik kullanım | Üretimde kalıcı veri | Geliştirmede canlı kod |

### Inception'ın özel durumu

Subject iki şeyi **aynı anda** istiyor:

1. Named volume zorunlu, bind mount yasak.
2. Veri `/home/elikavak/data` altında olacak.

Bunlar çelişmiyor — named volume'ün `local` driver'ına nereye yazacağı söylenebilir:

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
compose ona adıyla referans verir. `driver_opts` sadece "byte'ları şurada tut" der.

> **İki tuzak:**
>
> 1. Host dizini **önceden var olmalı**. `local` driver onu oluşturmaz. Bu yüzden Makefile'da
>    `mkdir -p` var.
> 2. `docker volume inspect` çıktısında `Mountpoint` alanı hâlâ
>    `/var/lib/docker/volumes/...` gösterir. Aradığın yol **`Options.device`** alanındadır.

---

## 10. Ağ

### Network sürücüleri

| Sürücü | Ne yapar |
| ------ | -------- |
| `bridge` | Varsayılan. Host üzerinde sanal switch; her container kendi IP'sini alır |
| `host` | Container host'un ağ namespace'ini paylaşır — **izolasyon yok** |
| `none` | Ağ yok |
| `overlay` | Birden fazla host'taki container'ları birleştirir (Swarm) |
| `macvlan` | Container'a fiziksel ağda gerçek bir MAC adresi verir |

### Bridge nasıl çalışır

```
      Host
 ┌──────────────────────────────────┐
 │  eth0 (192.168.1.10)             │
 │    │                             │
 │  ┌─┴──────────────┐              │
 │  │  br-xxxx       │ ← sanal switch
 │  └─┬────┬────┬────┘              │
 │  veth veth veth                  │
 │    │    │    │                   │
 │  nginx  wp  mariadb              │
 │  .0.2  .0.3  .0.4                │
 └──────────────────────────────────┘
```

Her container `veth` çifti ile bridge'e bağlanır ve özel bir alt ağdan IP alır.

### Varsayılan bridge vs kullanıcı tanımlı bridge

**Kritik fark:** Kullanıcı tanımlı bir network'te Docker `127.0.0.11` adresinde **gömülü bir DNS
sunucusu** çalıştırır. Container'lar birbirini **isimle** bulur.

| | Varsayılan `bridge` | Kullanıcı tanımlı bridge |
| --- | --- | --- |
| DNS ile servis keşfi | **Yok** | **Var** — container/servis adıyla |
| İzolasyon | Tüm container'lar aynı ağda | Sadece o network'tekiler görüşür |
| Eski çözüm | `--link` (deprecated) | Gerek yok |

Bu yüzden `wp-config.php` içinde IP değil, `mariadb` yazıyoruz. Container yeniden başlayıp IP'si
değişse bile isim çözümlenmeye devam eder.

```bash
docker exec wordpress getent hosts mariadb
```

### `--link` neden ölü

Eski mekanizma: hedef container'ın IP'sini `/etc/hosts`'a ve bilgilerini env değişkenlerine
**container başlarken bir kez** enjekte ederdi. Tek yönlüydü ve hedef container yeniden başlayıp
IP değiştirdiğinde bozulurdu. Kullanıcı tanımlı network aynı işi DNS ile dinamik olarak yapıyor.

> **Inception:** `--link`, `links:` ve `network_mode: host` **yasak**. Eval sadece compose'a
> değil, Makefile ve tüm script'lere de bakıyor.

### `host` network neden tehlikeli

Container host'un ağ namespace'ini paylaşır:

- İzolasyon tamamen kalkar — MariaDB'nin 3306'sı anında makinenin arayüzünde açılır.
- Servis keşfi kaybolur, her şey `127.0.0.1` olur.
- İki servis aynı portu isteyemez.
- Inception'ın "tek giriş noktası 443" iddiası çöker.

### `ports` vs `expose`

```yaml
nginx:
  ports:
    - "443:443"     # host:container → DIŞARIDAN erişilebilir
wordpress:
  expose:
    - "9000"        # sadece network içinden
```

| | `ports` | `expose` |
| --- | --- | --- |
| Host'tan erişim | **Evet** | Hayır |
| Network içinden erişim | Evet | Evet |
| Ne yapar | Host portunu NAT'lar | Sadece metadata |

> **Inception:** `ports` yalnızca `nginx`'te ve yalnızca `443`. Diğer iki servis `expose`
> kullanır — bu yüzden MariaDB ve PHP-FPM host'tan erişilemez. Kanıt:
> `sudo ss -tlnp | grep -E ':(443|3306|9000)'` → sadece 443 çıkmalı.

---

## 11. Docker Compose nedir

### Problem

Üç container'ı elle çalıştırmayı dene:

```bash
docker network create inception
docker volume create db_data
docker run -d --name mariadb --network inception -v db_data:/var/lib/mysql \
  -e MYSQL_DATABASE=wordpress --restart unless-stopped mariadb:v1
docker run -d --name wordpress --network inception -v wp_data:/var/www/html \
  -e MYSQL_HOST=mariadb --restart unless-stopped wordpress:v1
docker run -d --name nginx --network inception -v wp_data:/var/www/html \
  -p 443:443 --restart unless-stopped nginx:v1
```

Sorunlar: bu komutlar hiçbir yerde kayıtlı değil (terminal geçmişinde), sıra elle yönetiliyor,
bir flag'i unutmak sessiz hatalara yol açıyor, altı ay sonra kimse hatırlamıyor.

### Çözüm

Aynı şeyi **bildirimsel** bir dosyaya yaz:

```yaml
services:
  mariadb:
    build: ./requirements/mariadb
    image: mariadb
    networks: [inception]
    volumes:
      - mariadb_data:/var/lib/mysql
    restart: unless-stopped
```

Sonra:

```bash
docker compose up -d
```

Compose bir **orkestrasyon** aracıdır: network'ü yaratır, volume'leri hazırlar, image'ları build
eder, container'ları doğru sırayla başlatır, hepsini tek grup olarak yönetir.

### "Compose ile image farklı mı olur?" — eval sorusu

**Hayır. Image birebir aynıdır.** Aynı Dockerfile, aynı katmanlar, aynı digest. Fark image'da
değil, yönetiminde:

| | `docker build` + `docker run` | `docker compose` |
| --- | --- | --- |
| Tanım nerede | Terminal geçmişi, flag'ler | Git'te versiyonlanan YAML |
| Network | Elle yarat, elle bağla | Otomatik, proje adı önekiyle |
| Volume | Elle `-v` | `volumes:` bloğunda |
| Sıra | Elle | `depends_on` |
| Yaşam döngüsü | Tek tek | Tüm stack birlikte |

Compose bir **image formatı değil**, bir yönetim katmanıdır.

### Proje adı ve önekler

Compose oluşturduğu kaynaklara **proje adı** öneki ekler:

```
srcs_inception          ← network
srcs_wordpress_data     ← volume
srcs-wordpress-1        ← container
```

Proje adı varsayılan olarak compose dosyasının bulunduğu dizinden gelir — Inception'da `srcs`.
`-p` bayrağı veya `COMPOSE_PROJECT_NAME` ile değiştirilebilir. Bu önek, aynı makinedeki farklı
projelerin çakışmasını engeller.

---

## 12. Compose dosyası anatomisi

Compose v2'de **`version:` anahtarı kullanılmaz** — obsolete olduğu için uyarı verir.

```yaml
services:          # container'lar
networks:          # ağlar
volumes:           # kalıcı depolama
secrets:           # gizli dosyalar
```

### Servis anahtarları

```yaml
services:
  wordpress:
    build:
      context: ./requirements/wordpress   # Dockerfile'ın bulunduğu dizin
      dockerfile: Dockerfile
    image: wordpress                      # build sonrası verilecek isim
    container_name: wordpress
    depends_on:
      - mariadb
    networks:
      - inception
    volumes:
      - wordpress_data:/var/www/html
    environment:
      - MYSQL_HOST=${MYSQL_HOST}
    env_file:
      - .env
    secrets:
      - db_password
    expose:
      - "9000"
    restart: unless-stopped
```

| Anahtar | Ne yapar |
| ------- | -------- |
| `build` | Image'ı bu context'ten build et |
| `image` | Build edilen image'a bu adı ver (veya bu image'ı çek) |
| `container_name` | Container'a sabit isim ver (önek almaz) |
| `depends_on` | Başlangıç **sırası** — hazır olmayı garanti etmez |
| `networks` | Hangi ağ(lar)a bağlansın |
| `volumes` | `<volume_adı>:<container_yolu>` |
| `environment` | Container **içine** env değişkeni koy |
| `env_file` | Env değişkenlerini dosyadan oku |
| `secrets` | Hangi secret'lar `/run/secrets/` altına mount edilsin |
| `ports` | Host'a port aç |
| `expose` | Sadece network içinde açık (metadata) |
| `restart` | Yeniden başlatma politikası |
| `command` | Dockerfile'daki `CMD`'yi ez |
| `entrypoint` | Dockerfile'daki `ENTRYPOINT`'i ez |
| `healthcheck` | Sağlık kontrolü tanımla |

> **`image:` neden önemli?** Inception'da **image adı servis adıyla aynı olmak zorunda**.
> `build` ile birlikte `image: wordpress` yazınca compose image'ı build edip o adla etiketler.

### `depends_on` yanılgısı

```yaml
depends_on:
  - mariadb
```

Bu sadece **container başlama sırasını** garanti eder. MariaDB container'ı ayaktayken servisin
kendisi henüz bağlantı kabul etmiyor olabilir — `mariadbd` başlıyor, tabloları açıyor, port
dinlemeye başlıyor; bu birkaç saniye sürer.

İki çözüm:

1. **Uygulama tarafında bekleme** (Inception'da bu) — entrypoint'te sınırlı deneme döngüsü.
2. **Healthcheck + condition:**

```yaml
depends_on:
  mariadb:
    condition: service_healthy
```

Bunun için `mariadb` servisinde bir `healthcheck` tanımlı olmalı.

### Network ve volume blokları

```yaml
networks:
  inception:
    driver: bridge

volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/elikavak/data/wordpress
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/elikavak/data/mariadb
```

> **Inception:** `networks` satırının compose dosyasında **bulunması zorunlu**. Compose'un örtük
> varsayılan ağına güvenmek yeterli değil — eval bu satırı arıyor.

---

## 13. Değişkenler: .env, environment, secrets

Burada üç farklı mekanizma var ve karıştırılmaları çok yaygın.

### 13.1 `.env` — compose dosyasında yerine koyma

Compose, proje dizinindeki `.env` dosyasını **otomatik okur** ve compose dosyasındaki
`${DEĞİŞKEN}` ifadelerini onunla değiştirir.

```ini
# srcs/.env
DOMAIN_NAME=elikavak.42.fr
MYSQL_DATABASE=wordpress
```

```yaml
environment:
  - MYSQL_DATABASE=${MYSQL_DATABASE}
```

**Bu, değişkeni container'a koymaz.** Sadece compose dosyasının metnini işler.

### 13.2 `environment` / `env_file` — container'ın içine koymak

```yaml
environment:
  - MYSQL_DATABASE=${MYSQL_DATABASE}   # .env'den okuyup container'a ver
env_file:
  - .env                                # tüm dosyayı container'a ver
```

Fark netleştirmek gerekirse:

| Mekanizma | Nereyi etkiler |
| --------- | -------------- |
| `.env` dosyası | **Compose dosyasının kendisini** — `${VAR}` yerine koyma |
| `environment:` | **Container'ın içini** — process'in environment'ı |
| `env_file:` | **Container'ın içini** — dosyadaki her satır |

### 13.3 Secrets

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt

services:
  mariadb:
    secrets:
      - db_password
```

Container içinde dosya olarak görünür:

```bash
cat /run/secrets/db_password
```

Entrypoint'te okunuşu:

```bash
DB_PASS=$(cat /run/secrets/db_password)
```

### Neden env değil secret

| | Environment variable | Secret |
| --- | --- | --- |
| `docker inspect` | **Değer görünür** | Sadece mount noktası |
| `/proc/<pid>/environ` | **Görünür** | Görünmez |
| Image katmanı | `ENV` ile kalıcı olarak gömülür | Asla girmez |
| Log/crash dump | Environment'ı döken araçlarla sızar | Zor |
| Alt process'lere miras | **Evet** — çalıştırdığın her komut görür | Hayır |

Son satır önemli: env değişkenleri **tüm çocuk process'lere miras kalır**. Container'da
çalıştırdığın herhangi bir araç şifreyi görebilir.

**Dürüst sınır:** Compose (Swarm değil) modunda secret'lar host'ta düz bir dosyadır; güvenlikleri
o dosyanın izinlerine bağlıdır. Garanti ettikleri: image katmanında değil, `docker inspect`'te
değil, process environment'ında değil.

### Ayrım kuralı

> *"Bu string herkese açık olsa zarar görür müyüm?"*

- **Hayır** → `.env` (domain, DB adı, kullanıcı adları, site başlığı, yollar)
- **Evet** → `secrets/` (DB root şifresi, DB kullanıcı şifresi, WP hesap şifreleri)

İkisi de `.gitignore`'da. Repoda sadece `.example` şablonları durur.

---

## 14. Compose komutları

```bash
docker compose up -d                # oluştur ve arka planda başlat
docker compose up -d --build        # önce image'ları yeniden build et
docker compose down                 # container ve network'ü kaldır (volume KALIR)
docker compose down -v              # volume'leri de sil
docker compose down --rmi all       # image'ları da sil
docker compose ps                   # durum
docker compose logs -f              # tüm loglar
docker compose logs -f wordpress    # tek servis
docker compose exec wordpress bash  # çalışan servise gir
docker compose build --no-cache     # cache'siz build
docker compose restart nginx        # tek servisi yeniden başlat
docker compose config               # değişkenler yerine konmuş hâlini göster
```

Compose dosyası başka dizindeyse:

```bash
docker compose -f srcs/docker-compose.yml ps
```

> `docker compose config` çok işe yarar: `${VAR}` ifadelerinin gerçekte neye çözüldüğünü gösterir.
> "Değişken boş kalmış" hatalarını saniyeler içinde bulur.

### `down` neyi siler

| Komut | Container | Network | Volume | Image |
| ----- | --------- | ------- | ------ | ----- |
| `down` | Silinir | Silinir | **Kalır** | Kalır |
| `down -v` | Silinir | Silinir | **Silinir** | Kalır |
| `down --rmi all` | Silinir | Silinir | Kalır | Silinir |
| `down -v --rmi all` | Silinir | Silinir | Silinir | Silinir |

---

## 15. Hepsi bir arada: Inception

### İstek yolu

```
Tarayıcı
   │ HTTPS 443
   ↓
┌─────────┐  FastCGI 9000  ┌────────────┐  MySQL 3306  ┌──────────┐
│  nginx  │ ─────────────→ │ wordpress  │ ───────────→ │ mariadb  │
│ TLS +   │                │ php-fpm    │              │          │
│ proxy   │                │            │              │          │
└────┬────┘                └─────┬──────┘              └────┬─────┘
     │  statik dosyalar          │ upload                   │
     └──────────┐    ┌───────────┘                          │
                ↓    ↓                                      ↓
      ┌──────────────────────┐              ┌──────────────────────┐
      │   wordpress_data     │              │    mariadb_data      │
      │ /home/elikavak/data/ │              │ /home/elikavak/data/ │
      │      wordpress       │              │       mariadb        │
      └──────────────────────┘              └──────────────────────┘
```

### Her kavramın projedeki karşılığı

| Kavram | Inception'daki karşılığı |
| ------ | ------------------------ |
| Image | 3 adet, hepsi `FROM debian:bookworm`, elle yazılmış Dockerfile |
| Tag | Açık tag zorunlu, `latest` yasak |
| Image adı | Servis adıyla aynı: `nginx`, `wordpress`, `mariadb` |
| Katman | `apt-get install` + `rm -rf /var/lib/apt/lists/*` aynı `RUN`'da |
| PID 1 | `nginx -g "daemon off;"`, `php-fpm8.2 -F`, `mariadbd` |
| `exec "$@"` | Üç entrypoint script'inin de son satırı |
| Bridge network | `inception` — servisler birbirini isimle bulur |
| `ports` | Sadece `nginx`, sadece `443` |
| `expose` | `wordpress:9000`, `mariadb:3306` — host'a kapalı |
| Named volume | `wordpress_data`, `mariadb_data` — `driver_opts` ile host yoluna bağlı |
| Secret | `db_password`, `db_root_password`, `credentials` |
| `.env` | Domain, DB adı, kullanıcı adları — credential yok |
| Restart | `unless-stopped` |

### Neden bu mimari

**Neden üç ayrı container?** Her servis bağımsız güncellenebilir, bağımsız yeniden başlatılabilir,
bağımsız loglanır. Bir servis çökerse diğerleri ayakta kalır. Bu "her container tek servis"
ilkesinin pratik karşılığı.

**Neden NGINX ayrı?** TLS terminasyonu ve statik dosya servisi web sunucusunun işidir. PHP-FPM
HTTP bile konuşmaz — FastCGI konuşur. İkisi farklı sorumluluklardır.

**Neden `fastcgi_pass`, `proxy_pass` değil?** `proxy_pass` HTTP konuşur, php-fpm HTTP anlamaz.
Yanlış direktif = bozuk yanıt.

**Neden TCP 9000, Unix socket değil?** Unix socket bir dosya sistemi nesnesidir ve container'ın
kendi `mnt` namespace'inde yaşar. Başka container'daki NGINX ona erişemez. Bu yüzden `www.conf`
içinde `listen = 0.0.0.0:9000` — Debian'ın varsayılanı socket'tir, değiştirilmezse `502`.

**Neden `bind-address = 0.0.0.0`?** Debian'ın MariaDB varsayılanı `127.0.0.1`, yani sadece kendi
container'ından erişilebilir. WordPress container'ının bağlanabilmesi için değiştirilmeli.

**Neden volume paylaşımlı?** `wordpress_data` iki container tarafından mount edilir: WordPress
PHP'yi çalıştırıp upload yazar, NGINX aynı dosyalardan statik içeriği okur. İkisi de aynı Debian
tabanından geldiği için `www-data` uid/gid'i (33) aynıdır — biri Alpine'a geçerse izinler bozulur.

---

## 16. Sık yapılan hatalar

| Hata | Belirti | Sebep ve çözüm |
| ---- | ------- | -------------- |
| Container hemen `exited` oluyor | `docker ps -a` → Exited (0) | PID 1 çıktı. Daemon ön planda değil: `daemon off`, `-F` bayrakları eksik |
| `docker stop` 10 saniye sürüyor | Bekleme, sonra sert ölüm | Entrypoint'te `exec` yok, PID 1 shell |
| `502 Bad Gateway` | NGINX ayakta, sayfa açılmıyor | `fastcgi_pass` hedefi ile `www.conf`'taki `listen` uyuşmuyor; ya da socket kullanılmış |
| "Error establishing a database connection" | WordPress açılmıyor | MariaDB hazır değil (bekleme döngüsü yok), veya `bind-address` `127.0.0.1` kalmış, veya şifre uyuşmuyor |
| Config değişikliği etkisiz | Eski davranış sürüyor | Config image'a build zamanında kopyalanıyor. `docker compose up -d --build` gerekli |
| Volume mount hatası | Başlangıçta patlıyor | `driver_opts` hedef dizini host'ta yok. `mkdir -p` gerekli |
| `docker inspect`'te şifre görünüyor | — | `ENV` ile şifre verilmiş. Secret'a taşı |
| Image gereksiz büyük | Yüzlerce MB | `apt` listeleri silinmemiş veya ayrı `RUN`'da silinmiş |
| Cache hiç çalışmıyor | Her build baştan | `COPY . .` en üstte. Az değişeni üste, çok değişeni alta al |
| Volume'de eski veri | `make re` sonrası eski ayarlar | Doğru davranış — volume kalıcı. Sıfırlamak için `down -v` |
| `wp-config.php` güncellenmiyor | Config değişti, WP eskisini kullanıyor | Dosya **volume'de**, image'da değil. `wp config set` ile güncelle veya `fclean` |
| Port çakışması | `port is already allocated` | `sudo ss -tlnp \| grep :443` ile bulup durdur |

---

## 17. Komut sözlüğü

### Image

```bash
docker build -t ad:tag .           # build
docker images                      # listele
docker history ad:tag              # katmanlar (şifre sızıntısı kontrolü)
docker rmi ad:tag                  # sil
docker image prune -a              # kullanılmayanları temizle
```

### Container

```bash
docker run -d --name x ad:tag      # başlat
docker ps / docker ps -a           # listele
docker logs -f x                   # loglar
docker exec -it x bash             # içine gir
docker exec x ps -eo pid,comm      # PID 1 kontrolü
docker stop x / docker rm x        # durdur / sil
docker inspect x                   # metadata
docker stats                       # canlı kaynak kullanımı
```

### Volume

```bash
docker volume ls
docker volume inspect ad           # Options.device'a bak
docker volume rm ad
docker volume prune
```

### Network

```bash
docker network ls
docker network inspect ad          # bağlı container'lar ve IP'ler
docker exec x getent hosts mariadb # DNS testi
```

### Compose

```bash
docker compose -f srcs/docker-compose.yml up -d --build
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml config    # değişkenleri çözülmüş hâli
```

### Tam temizlik (değerlendiricinin çalıştırdığı)

```bash
docker stop $(docker ps -qa); docker rm $(docker ps -qa); docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q); docker network rm $(docker network ls -q) 2>/dev/null
```
