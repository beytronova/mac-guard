---
name: AliveLockDesignSystem
platform:
  os: [macOS]
  minimumDeployment: "12.0"
  appearance: [dark]
colors:
  background:
    base: "#0D1117"
    overlay: "rgba(11, 14, 20, 0.88)"
  surface:
    lowest: "#0F131D"
    low: "#141926"
    container: "#1A2234"
    high: "#222C42"
    highest: "#2B3854"
    hover: "#1E273A"
  borders:
    subtle: "rgba(255, 255, 255, 0.08)"
    default: "rgba(255, 255, 255, 0.14)"
    strong: "rgba(255, 255, 255, 0.22)"
    focused: "rgba(56, 189, 248, 0.65)"
  text:
    primary: "#F8FAFC"
    secondary: "#94A3B8"
    tertiary: "#64748B"
    disabled: "rgba(255, 255, 255, 0.35)"
  accents:
    cyan: "#38BDF8"       # AliveLock Sky / Shield Blue
    blue: "#0A84FF"       # Apple System Blue
    emerald: "#34D399"    # Authorized / Success Green
    purple: "#A78BFA"     # Apps & Category Violet
    amber: "#FBBF24"      # Vault / Warning Amber
    red: "#F87171"        # Security Breach / Danger Coral Red
typography:
  fontFamily: "SF Pro Display, -apple-system"
  monoFamily: "SF Mono, Menlo, monospace"
  styles:
    title1: { fontSize: 24pt, fontWeight: 700 }
    title2: { fontSize: 18pt, fontWeight: 700 }
    title3: { fontSize: 15pt, fontWeight: 600 }
    body: { fontSize: 13pt, fontWeight: 500 }
    callout: { fontSize: 12pt, fontWeight: 500 }
    subheadline: { fontSize: 11pt, fontWeight: 600 }
    caption: { fontSize: 10pt, fontWeight: 400 }
rounded:
  sm: 8pt
  md: 12pt
  lg: 16pt
  xl: 20pt
  pill: 999pt
  curve: continuous
touchTargets:
  minHeight: 44pt
  minWidth: 44pt
motion:
  springFast: "response: 0.25, dampingFraction: 0.80"
  springStandard: "response: 0.35, dampingFraction: 0.75"
---

# AliveLock macOS UI/UX Tasarım Sistemi & Rationale

Bu doküman, `UI-md` kural setine (`PORTABLE_IOS_DESIGN_RULES.md`, `rules/design_md_spec.md`, `rules/ios_core_hig.md`, `rules/adaptive_m3_ios.md`) tam uyumlu olarak AliveLock masaüstü güvenlik uygulamasının görsel ve etkileşim mimarisini belirler.

---

## 1. Tasarım Felsefesi

1. **Clarity (Netlik & Sıfır Kontrast Hatası):**
   - Koyu temalı buzlu cam pencerelerde AppKit varsayılan gri/siyah buton stilleri tamamen kaldırılmıştır.
   - Tüm buton ve etiketler `attributedTitle` ve semantik renk token'ları ile renklendirilir; metin kontrastı WCAG 4.5:1 eşiğinin üzerindedir (`textPrimary: #F8FAFC`, `textSecondary: #94A3B8`).

2. **Deference (İçerik ve Durum Odaklılık):**
   - Güvenlik durumu (Yönetici / Korunuyor) tek bakışta renk ve ışıltıyla anlaşılır:
     - **Zümrüt Yeşili (#34D399):** Yönetici (Admin) serbest modu.
     - **Siber Gökyüzü Mavisi (#38BDF8):** Koruma ve kilit aktif modu.
     - **İris Moru (#A78BFA):** Kilitli uygulama yönetimi.
     - **Amber / Altın (#FBBF24):** Kasa & fotoğraf güvenlik kayıtları.
     - **Mercan Kırmızı (#F87171):** Hatalı şifre / yetkisiz erişim alarmı.

3. **Depth & Tonal Elevation (M3 + Apple HIG Hibriti):**
   - Ağır siyah yapay gölgeler yerine, `surfaceLowest` -> `surface` -> `surfaceHigh` ton katmanları ve 1px zarif şeffaf sınır çizgileri (`rgba(255, 255, 255, 0.12)`) kullanılır.
   - Pencereler macOS native `.hudWindow` ve `.fullScreenUI` arka plan bulanıklığı ile masaüstü ile derinlik kurar.

4. **Etkileşim Standartları:**
   - Navigasyon butonları, ana işlem butonları ve kartlar dokunma/tıklama geri bildirimine (`mouseEntered` / `mouseExited` hover animasyonu) sahiptir.
   - Tıklanabilir alanlar minimum 40-44pt yükseklik kuralına sadıktır.

