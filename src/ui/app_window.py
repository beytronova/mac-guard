import tkinter as tk
from tkinter import ttk, messagebox
import threading
import subprocess
import os
from typing import Callable, Optional
from src.utils.config import ConfigManager
from src.core.process_manager import ProcessManager
from src.core.auth_manager import AuthManager
from src.ui.notification import send_macos_notification


class SecurityManagerApp:
    """
    Şık, minimalist macOS Açılış ve Güvenlik Yöneticisi Arayüzü.
    Koyu tema, modern kartlar ve pürüzsüz geçişlerle tasarlanmıştır.
    """

    BG_COLOR = "#16171b"
    CARD_BG = "#21232b"
    CARD_HOVER = "#2a2d37"
    TEXT_MAIN = "#f3f4f6"
    TEXT_MUTED = "#9ca3af"
    ACCENT_ADMIN = "#10b981"     # Yeşil (Güvenli / Yönetici)
    ACCENT_GUEST = "#f59e0b"     # Kehribar Sarısı (Kısıtlı / Misafir)
    BORDER_COLOR = "#323644"

    # macOS uyumlu evrensel fontlar
    FONT_FAMILY = "Helvetica Neue"
    FONT_TITLE = ("Helvetica Neue", 20, "bold")
    FONT_SUBTITLE = ("Helvetica Neue", 12)
    FONT_CARD_TITLE = ("Helvetica Neue", 15, "bold")
    FONT_CARD_SUB = ("Helvetica Neue", 11, "bold")
    FONT_CARD_DESC = ("Helvetica Neue", 11)
    FONT_BADGE = ("Helvetica Neue", 10)
    FONT_FOOTER = ("Helvetica Neue", 11)

    def __init__(self, root: tk.Tk, config_manager: ConfigManager, on_mode_change: Optional[Callable[[str], None]] = None):
        self.root = root
        self.config = config_manager
        self.on_mode_change = on_mode_change

        self._setup_window()
        self._build_ui()
        self._bind_events()
        self.update_mode_indicator()

    def _setup_window(self):
        """Pencere boyutları ve macOS pencere özelliklerini yapılandırır."""
        self.root.title("Mac Guard - Güvenlik Yöneticisi")
        self.root.configure(bg=self.BG_COLOR)
        self.root.resizable(False, False)

        # Boyut ve Ekranda Ortala
        w, h = 540, 480
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        x = (screen_w - w) // 2
        y = (screen_h - h) // 2 - 40
        self.root.geometry(f"{w}x{h}+{x}+{y}")
        self.root.update_idletasks()

    def _build_ui(self):
        """Modern ve minimalist arayüz bileşenlerini oluşturur."""
        # Ana Konteyner
        main_frame = tk.Frame(self.root, bg=self.BG_COLOR, padx=30, pady=25)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Üst Başlık ve İkon
        header_frame = tk.Frame(main_frame, bg=self.BG_COLOR)
        header_frame.pack(fill=tk.X, pady=(0, 15))

        title_lbl = tk.Label(
            header_frame,
            text="🛡️  Açılış & Güvenlik Yöneticisi",
            font=self.FONT_TITLE,
            fg=self.TEXT_MAIN,
            bg=self.BG_COLOR
        )
        title_lbl.pack(anchor="w")

        subtitle_lbl = tk.Label(
            header_frame,
            text="Lütfen bu oturum için kullanılacak çalışma modunu seçin.",
            font=self.FONT_SUBTITLE,
            fg=self.TEXT_MUTED,
            bg=self.BG_COLOR
        )
        subtitle_lbl.pack(anchor="w", pady=(4, 0))

        # Mevcut Durum Rozeti (Pill Badge)
        self.status_badge_frame = tk.Frame(header_frame, bg="#272a34", padx=10, pady=4)
        self.status_badge_frame.pack(anchor="w", pady=(10, 0))

        self.status_dot = tk.Label(self.status_badge_frame, text="●", font=self.FONT_BADGE, bg="#272a34", fg=self.ACCENT_ADMIN)
        self.status_dot.pack(side=tk.LEFT, padx=(0, 6))

        self.status_text = tk.Label(
            self.status_badge_frame,
            text=f"Aktif Mod: {self.config.current_mode}",
            font=self.FONT_CARD_SUB,
            fg=self.TEXT_MAIN,
            bg="#272a34"
        )
        self.status_text.pack(side=tk.LEFT)

        # Seçenek Kartları Konteyneri
        cards_frame = tk.Frame(main_frame, bg=self.BG_COLOR)
        cards_frame.pack(fill=tk.BOTH, expand=True, pady=10)

        # KART 1: YÖNETİCİ (ADMIN)
        self.admin_card = self._create_mode_card(
            parent=cards_frame,
            title="Yönetici (Admin)",
            subtitle="Tam Yetki • Touch ID veya Şifre Doğrulaması",
            description="Tüm kilitli uygulamaları (WhatsApp, Fotoğraflar vb.) serbest bırakır ve görünür yapar.",
            accent_color=self.ACCENT_ADMIN,
            icon="👤",
            badge_text="[Kısayol: 1]",
            command=self._handle_admin_mode
        )
        self.admin_card.pack(fill=tk.X, pady=(0, 14))

        # KART 2: MİSAFİR
        self.guest_card = self._create_mode_card(
            parent=cards_frame,
            title="Misafir Modu",
            subtitle="Korumalı Alan • Kritik Uygulamalar Kilitli",
            description="WhatsApp ve Fotoğraflar gibi kişisel uygulamaları sistem düzeyinde anında gizler ve engeller.",
            accent_color=self.ACCENT_GUEST,
            icon="👥",
            badge_text="[Kısayol: 2]",
            command=self._handle_guest_mode
        )
        self.guest_card.pack(fill=tk.X)

        # Alt Bilgi ve Durum İletisi Çubuğu
        self.footer_lbl = tk.Label(
            main_frame,
            text="ESC: Pencereyi Kapat / Gizle • Arka plan koruması aktiftir.",
            font=self.FONT_FOOTER,
            fg="#6b7280",
            bg=self.BG_COLOR
        )
        self.footer_lbl.pack(side=tk.BOTTOM, pady=(10, 0))

        self.feedback_lbl = tk.Label(
            main_frame,
            text="",
            font=("Helvetica Neue", 11, "italic"),
            fg=self.ACCENT_ADMIN,
            bg=self.BG_COLOR
        )
        self.feedback_lbl.pack(side=tk.BOTTOM, pady=(4, 0))

    def _create_mode_card(self, parent, title: str, subtitle: str, description: str,
                          accent_color: str, icon: str, badge_text: str, command: Callable):
        """Tıklanabilir, modern kenarlıklı ve hover animasyonlu kart bileşeni."""
        card = tk.Frame(
            parent,
            bg=self.CARD_BG,
            highlightbackground=self.BORDER_COLOR,
            highlightthickness=1,
            padx=16,
            pady=14,
            cursor="pointinghand"
        )

        top_row = tk.Frame(card, bg=self.CARD_BG)
        top_row.pack(fill=tk.X)

        # İkon ve Başlık
        lbl_icon = tk.Label(top_row, text=icon, font=(self.FONT_FAMILY, 18), bg=self.CARD_BG, fg=accent_color)
        lbl_icon.pack(side=tk.LEFT, padx=(0, 10))

        lbl_title = tk.Label(top_row, text=title, font=self.FONT_CARD_TITLE, bg=self.CARD_BG, fg=self.TEXT_MAIN)
        lbl_title.pack(side=tk.LEFT)

        lbl_badge = tk.Label(top_row, text=badge_text, font=self.FONT_BADGE, bg=self.CARD_BG, fg=self.TEXT_MUTED)
        lbl_badge.pack(side=tk.RIGHT)

        # Alt Başlık
        lbl_sub = tk.Label(card, text=subtitle, font=self.FONT_CARD_SUB, bg=self.CARD_BG, fg=accent_color)
        lbl_sub.pack(anchor="w", pady=(4, 2))

        # Açıklama
        lbl_desc = tk.Label(card, text=description, font=self.FONT_CARD_DESC, bg=self.CARD_BG, fg=self.TEXT_MUTED, wraplength=470, justify="left")
        lbl_desc.pack(anchor="w")

        # Tıklama ve Hover bağlamaları
        widgets = [card, top_row, lbl_icon, lbl_title, lbl_badge, lbl_sub, lbl_desc]

        def on_enter(e):
            card.configure(bg=self.CARD_HOVER, highlightbackground=accent_color)
            for w in widgets:
                if w != card and hasattr(w, "configure"):
                    w.configure(bg=self.CARD_HOVER)

        def on_leave(e):
            card.configure(bg=self.CARD_BG, highlightbackground=self.BORDER_COLOR)
            for w in widgets:
                if w != card and hasattr(w, "configure"):
                    w.configure(bg=self.CARD_BG)

        for w in widgets:
            w.bind("<Enter>", on_enter)
            w.bind("<Leave>", on_leave)
            w.bind("<Button-1>", lambda e, cmd=command: cmd())

        return card

    def _bind_events(self):
        """Klavye kısayolları ve odak yönetimi."""
        self.root.bind("<Escape>", lambda e: self.hide_window())
        self.root.bind("1", lambda e: self._handle_admin_mode())
        self.root.bind("2", lambda e: self._handle_guest_mode())

    def update_mode_indicator(self):
        """Arayüzdeki mod rozetini ve renkleri günceller."""
        mode = self.config.current_mode
        if mode != "Misafir":
            self.status_dot.configure(fg=self.ACCENT_ADMIN)
            self.status_text.configure(text="Aktif Mod: Yönetici (Tam Erişim)")
        else:
            self.status_dot.configure(fg=self.ACCENT_GUEST)
            self.status_text.configure(text="Aktif Mod: Misafir (Korumalı)")

    def _set_feedback(self, text: str, is_error: bool = False):
        """Geri bildirim etiketini günceller."""
        self.feedback_lbl.configure(
            text=text,
            fg="#ef4444" if is_error else self.ACCENT_ADMIN
        )

    def _handle_admin_mode(self):
        """Yönetici moduna geçiş: Touch ID / Şifre kontrolü gerektirir."""
        self._set_feedback("Touch ID / Yönetici doğrulaması bekleniyor...")

        def auth_thread():
            # macOS Touch ID veya Parola İletişim Kutusu
            success, msg = AuthManager.verify_admin_touch_id(
                prompt_message="Yönetici Moduna geçmek ve kilitleri kaldırmak için kimliğinizi doğrulayın:"
            )

            if success:
                self.config.current_mode = "Yonetici"
                # Uygulamaları görünür ve aktif yap (WhatsApp, Photos vb.)
                ProcessManager.restore_all_apps(self.config.target_apps)

                self.root.after(0, lambda: self._on_admin_success())
            else:
                self.root.after(0, lambda: self._set_feedback(f"❌ {msg}", is_error=True))

        threading.Thread(target=auth_thread, daemon=True).start()

    def _on_admin_success(self):
        self.update_mode_indicator()
        self._set_feedback("✅ Kimlik doğrulandı! Tüm kilitler kaldırıldı.")
        if self.config.show_notifications:
            send_macos_notification("Yönetici modu aktif. Tüm uygulamalar serbest.", title="Mac Guard")
        if self.on_mode_change:
            self.on_mode_change("Yonetici")

        # 1.2 saniye sonra pencereyi arka plana gizle
        self.root.after(1200, self.hide_window)

    def _handle_guest_mode(self):
        """Misafir moduna geçiş: Korumayı anında devreye sokar."""
        self.config.current_mode = "Misafir"
        action = self.config.guest_action

        # WhatsApp ve Photos'u gizle / kapat
        ProcessManager.apply_guest_restrictions(self.config.target_apps, action=action)

        self.update_mode_indicator()
        self._set_feedback("🔒 Misafir modu etkinleştirildi. Kişisel uygulamalar gizlendi.")
        if self.config.show_notifications:
            send_macos_notification("Misafir modu aktif. WhatsApp ve Fotoğraflar kilitlendi.", title="Mac Guard")

        if self.on_mode_change:
            self.on_mode_change("Misafir")

        # 1.2 saniye sonra pencereyi arka plana gizle
        self.root.after(1200, self.hide_window)

    def show_window(self):
        """Pencereyi ekrana getirir ve odağı alır."""
        self.root.deiconify()
        self.root.lift()
        self.root.attributes("-topmost", True)
        self.root.update_idletasks()
        self.root.update()
        self.root.after(200, lambda: self.root.attributes("-topmost", False))
        self.root.focus_force()
        self.update_mode_indicator()
        self._set_feedback("")

        # macOS pencere odağını en öne al
        try:
            subprocess.run([
                "/usr/bin/osascript", "-e",
                f'tell application "System Events" to set frontmost of the first process whose unix id is {os.getpid()} to true'
            ], capture_output=True)
        except Exception:
            pass

    def hide_window(self):
        """Pencereyi gizler (arka planda çalışmaya devam eder)."""
        self.root.withdraw()

