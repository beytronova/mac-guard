# 🛡️ Mac Guard: macOS Açılış ve Güvenlik Yöneticisi

Mac Guard, macOS işletim sistemi için geliştirilmiş minimalist, şık ve arka planda sessizce çalışan bir oturum ve güvenlik yönetim uygulamasıdır.

Mac açıldığında veya manuel olarak tetiklendiğinde minimalist bir arayüz açarak kullanıcıya iki seçenek sunar:
1. **👤 Yönetici (Admin):** Touch ID veya macOS yönetici parolası doğrulaması isteyerek WhatsApp, Fotoğraflar ve diğer gizlenmiş tüm uygulamaları anında görünür ve aktif hale getirir.
2. **👥 Misafir:** WhatsApp, Fotoğraflar ve kişisel kritik uygulamaları sistem düzeyinde (`System Events` ve AppleScript) gizler/kapatır ve arka plandaki koruma bekçisi (watcher) sayesinde oturum boyunca bu uygulamaların açılmasını engeller.

---

## 📁 Proje Mimarisi

```text
mac-guard/
├── config.json                 # Kilitlenecek uygulamalar ve çalışma ayarları
├── main.py                     # Ana giriş noktası (Arayüz, Arka Plan Servisi ve CLI)
├── requirements.txt           # Opsiyonel bağımlılıklar (Temel sistem 0 ek paketle çalışır)
├── src/
│   ├── core/
│   │   ├── auth_manager.py     # macOS Touch ID / Yönetici Parolası Yetkilendirmesi
│   │   ├── process_manager.py  # AppleScript & System Events süreç kontrolcüsü
│   │   └── security_guard.py   # Arka plan denetçisi (Watcher daemon) ve IPC soketi
│   ├── ui/
│   │   ├── app_window.py       # Minimalist koyu tema, SF Pro stili macOS arayüzü
│   │   └── notification.py     # macOS yerel bildirim banner'ı sistemi
│   └── utils/
│       ├── config.py           # Yapılandırma yükleyici ve yöneticisi
│       └── macos_perms.py      # macOS Otomasyon & Erişilebilirlik izin denetleyici
└── scripts/
    ├── install_login_item.py   # Açılışta otomatik çalışma (LaunchAgent) kurucusu
    ├── uninstall_login_item.py # Açılış servisinden kaldırma betiği
    └── trigger_shortcut.sh     # Option + Command + K için kısayol tetikleyici
```

---

## ⚡ Hızlı Başlangıç

Standart Python 3 ile harici paket kurulumuna ihtiyaç duymadan doğrudan çalıştırabilirsiniz:

```bash
cd ~/dev/projects/mac-guard

# Uygulamayı arayüz ile başlat
python3 main.py
```

### Klavye Kısayolları (Arayüz Açıkken):
- **`1`** tuşu: Yönetici modunu seçer -> Touch ID tetiklenir.
- **`2`** tuşu: Misafir modunu seçer -> Uygulamalar anında kilitlenir.
- **`ESC`** tuşu: Pencereyi arka plana gizler (arka plan koruması devam eder).

---

## 🔐 1. macOS Güvenlik & İzin Ayarları (Çok Önemli)

macOS'in diğer uygulamaları (`WhatsApp`, `Photos`, `System Events`) kontrol edebilmesi için uygulamanın izin alması gerekir:

1. **İzinleri Kontrol Etmek İçin:**
   ```bash
   python3 main.py --check-perms
   ```
2. **Gerekli İzinler:**
   - **Sistem Ayarları (System Settings) > Gizlilik ve Güvenlik (Privacy & Security)**
     - **Otomasyon (Automation):** Terminal / Python için `System Events` onay kutusunu işaretleyin.
     - **Erişilebilirlik (Accessibility):** Terminal / Python uygulamasına izin verin.

---

## 🚀 2. Mac Açıldığında Otomatik İlk Sırada Çalışma (Login Item)

Uygulamanın Mac her açıldığında ve kullanıcı oturum açtığında otomatik olarak ilk sırada açılması için `LaunchAgent` altyapısı hazırlanmıştır:

### Otomatik Açılış Servisini Kurmak İçin:
```bash
python3 scripts/install_login_item.py
```
Bu komut, `~/Library/LaunchAgents/com.alivelock.app.plist` dosyasını otomatik oluşturup `launchctl` ile sisteme kaydeder. Mac açıldığında uygulama arka planda başlar ve ekranın ortasına minimalist seçim penceresini getirir.

### Açılış Servisini Kaldırmak İçin:
```bash
python3 scripts/uninstall_login_item.py
```

---

## ⌨️ 3. Klavye Kısayolu ile Tetikleme (`Option + Command + K`)

İstediğiniz zaman klavyeden `Option + Command + K` basarak bu pencereyi anında ekrana getirebilirsiniz.

### macOS Kestirmeler (Shortcuts) ile 1 Dakikada Kurulum:
1. Mac'te **Kestirmeler (Shortcuts)** uygulamasını açın.
2. Sağ üstten **`+` (Yeni Kestirme)** butonuna tıklayın.
3. Arama kutusuna **"Kabuk Betiğini Çalıştır" (Run Shell Script)** yazıp ekleyin.
4. Komut alanına şu satırı yapıştırın:
   ```bash
   ~/dev/projects/mac-guard/scripts/trigger_shortcut.sh
   ```
5. Sağ panelden kestirme detaylarına tıklayın:
   - **"Hızlı Eylem Olarak Kullan" (Use as Quick Action)** seçeneğini işaretleyin.
   - **Klavye Kısayolu:** kutusuna tıklayıp klavyenizden `⌥ ⌘ K` (**Option + Command + K**) tuşlarına basın.

Artık Mac'in neresinde olursanız olun `⌥ ⌘ K` bastığınızda Mac Guard penceresi anında ekrana gelecektir!

---

## ⚙️ 4. Yapılandırma (`config.json`)

Kilitlenecek yeni uygulamalar eklemek veya ayarları değiştirmek için `config.json` dosyasını düzenleyebilirsiniz:

```json
{
  "target_apps": [
    {
      "process_name": "WhatsApp",
      "bundle_id": "net.whatsapp.WhatsApp",
      "display_name": "WhatsApp"
    },
    {
      "process_name": "Photos",
      "bundle_id": "com.apple.Photos",
      "display_name": "Fotoğraflar"
    },
    {
      "process_name": "Telegram",
      "bundle_id": "ru.keepcoder.Telegram",
      "display_name": "Telegram"
    }
  ],
  "current_mode": "Yonetici",
  "block_on_launch_in_guest": true,
  "check_interval_seconds": 1.5,
  "show_notifications": true,
  "guest_action": "hide"
}
```

- `guest_action`: `"hide"` (gizle) veya `"quit"` (uygulamayı tamamen sonlandır).
- `check_interval_seconds`: Misafir modunda arka planda kontrol sıklığı (saniye).

---

## 🛠️ CLI (Terminal) Komutları

```bash
# Sadece arka plan servisi olarak çalıştır (Pencere gizli bekler)
python3 main.py --daemon

# Çalışan servisin penceresini ekrana getir
python3 main.py --toggle

# Komut satırından anında Misafir moduna geçir (Uygulamaları gizler)
python3 main.py --set-mode Misafir

# Komut satırından Yönetici moduna geçir (Uygulamaları açar)
python3 main.py --set-mode Yonetici

# İzin durumunu sorgula
python3 main.py --check-perms
```

