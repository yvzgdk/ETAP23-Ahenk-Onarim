#!/usr/bin/env bash
# Pardus ETAP 23 - Ahenk yeniden kurulum yardimcisi
# Paket yapilandirmasini yedekler, Ahenk paketini kaldirip yeniden kurar,
# sonra ETA Kayit uygulamasini acmayi dener.
# Lider sunucusundaki eski/duplike cihaz kaydini SILMEZ.
set -u

TITLE="ETAP 23 - Ahenk Yeniden Kurulum"
BACKUP_ROOT="$HOME/ETAP-Ahenk-Yedekleri"
LOG_ROOT="$HOME/ETAP-Ahenk-Raporlari"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
LOG="$LOG_ROOT/ahenk-yeniden-kurulum-$STAMP.log"

mkdir -p "$BACKUP_ROOT" "$LOG_ROOT"
touch "$LOG"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "Bu betigi Etap Yetkili masaustu oturumunda normal kullanici olarak calistirin; root olarak calistirmayin." | tee -a "$LOG"
  exit 1
fi

if ! command -v zenity >/dev/null 2>&1; then
  echo "Bu betik grafik onay pencereleri icin zenity gerektirir."
  echo "Terminalden once su komutla calistirin: sudo apt update && sudo apt install zenity"
  exit 1
fi

info() { zenity --info --title="$TITLE" --width=560 --text="$1"; }
warn() { zenity --warning --title="$TITLE" --width=560 --text="$1"; }
err()  { zenity --error --title="$TITLE" --width=560 --text="$1"; }

{
  echo "ETAP 23 Ahenk yeniden kurulum raporu"
  echo "Baslangic: $(date)"
  echo "Bilgisayar: $(hostname 2>/dev/null || true)"
  echo "Kullanici: $USER"
  echo "Isletim sistemi:"
  cat /etc/os-release 2>&1
  echo
  echo "Baslangic paket durumu:"
  dpkg-query -W -f='${binary:Package} ${Version} ${Status}\n' ahenk 2>&1 || true
  echo
  echo "Baslangic servisleri:"
  systemctl list-units --all --type=service --no-pager 2>&1 | grep -i ahenk || true
} >> "$LOG" 2>&1

if ! zenity --question --title="$TITLE" --width=560 \
  --text="Bu islem, bu tahtadaki Ahenk paketini kaldirip mevcut APT depolarindan yeniden kurmayi dener.\n\nOnce /etc/ahenk ve /var/lib/ahenk klasorleri varsa yedeklenecek.\n\nUYARI: Bu islem Lider sunucusundaki eski/duplike cihaz kaydini silmez ve tahtanin aktif olacagini garanti etmez. Sonrasinda ETA Kayit ile tahtayi dogru okul/sinif bilgileriyle kaydetmek gerekir.\n\nDevam edilsin mi?"; then
  info "Islem iptal edildi. Sistemde degisiklik yapilmadi."
  exit 0
fi

# Create local backups before any package operation.
mkdir -p "$BACKUP_DIR"
for p in /etc/ahenk /var/lib/ahenk /var/log/ahenk; do
  if [ -e "$p" ]; then
    sudo tar -czf "$BACKUP_DIR/$(echo "$p" | sed 's#/#_#g').tar.gz" "$p" >> "$LOG" 2>&1
    echo "Yedeklenen: $p" >> "$LOG"
  fi
done
echo "Yedek dizini: $BACKUP_DIR" >> "$LOG"

# Stop service(s) only if a matching service exists.
mapfile -t SERVICES < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk 'tolower($1) ~ /ahenk/ {print $1}')
for svc in "${SERVICES[@]:-}"; do
  [ -n "$svc" ] || continue
  sudo systemctl stop "$svc" >> "$LOG" 2>&1 || true
done

# Remove only the ahenk package; don't autoremove dependencies or delete directories manually.
if dpkg-query -W -f='${Status}' ahenk 2>/dev/null | grep -q 'install ok installed'; then
  if ! sudo apt-get purge -y ahenk >> "$LOG" 2>&1; then
    err "Ahenk paketi kaldirilamadi. Rapor: $LOG"
    exit 1
  fi
else
  echo "ahenk paketi kurulu gorunmuyor; kaldirma adimi atlandi." >> "$LOG"
fi

if ! sudo apt-get update >> "$LOG" 2>&1; then
  err "Paket listesi guncellenemedi. Internet/depo baglantisini kontrol edin.\nRapor: $LOG"
  exit 1
fi

if ! sudo apt-get install -y ahenk >> "$LOG" 2>&1; then
  err "Ahenk yeniden kurulamadi. Depo veya paket hatasi olabilir.\nRapor: $LOG"
  exit 1
fi

{
  echo
  echo "Kurulum sonrasi paket:"
  dpkg-query -W -f='${binary:Package} ${Version} ${Status}\n' ahenk 2>&1 || true
  echo
  echo "Kurulum sonrasi servisler:"
  systemctl list-units --all --type=service --no-pager 2>&1 | grep -i ahenk || true
  echo
  echo "Bitis: $(date)"
} >> "$LOG" 2>&1

# Launch the ETAP registration app if discoverable. Do not invent a registration or server identity.
if command -v eta-kayit >/dev/null 2>&1; then
  REG_CMD="eta-kayit"
elif command -v eta-kayıt >/dev/null 2>&1; then
  REG_CMD="eta-kayıt"
else
  REG_CMD=""
fi

if [ -n "$REG_CMD" ]; then
  if zenity --question --title="$TITLE" --width=560 \
    --text="Ahenk yeniden kuruldu.\n\nSimdi ETA Kayit uygulamasini acip tahtayi dogru okul ve sinif bilgileriyle yeniden kaydetmeyi denemek ister misiniz?"; then
    nohup "$REG_CMD" >/dev/null 2>&1 &
  fi
else
  echo "ETA Kayit komutu PATH icinde bulunamadi. Uygulama menusunden 'ETA Kayit' aratin." >> "$LOG"
  warn "Ahenk yeniden kuruldu ancak ETA Kayit komutu otomatik bulunamadi.\nPardus menusunden 'ETA Kayit' uygulamasini acin ve tahtayi dogru okul/sinif bilgileriyle kaydedin.\n\nRapor: $LOG"
fi

info "Islem tamamlandi.\n\nRapor:\n$LOG\n\nYedek:\n$BACKUP_DIR\n\nSon adim: ETA Kayit uygulamasinda tahtayi kaydedin. Lider panelinde eski klon kaydi hala pasif veya cakismali gorunuyorsa, sunucu tarafinda eski kaydin kontrol edilmesi gerekebilir."
