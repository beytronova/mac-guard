#!/usr/bin/env python3
"""
alivelock Açılışta Otomatik Başlatma (LaunchAgent) Kurucusu.
Kullanıcı oturum açtığında alivelock'ın tekil servis olarak çalışması için
~/Library/LaunchAgents/com.alivelock.app.plist dosyasını ekler ve etkinleştirir.
"""

import os
import sys
import subprocess
from pathlib import Path

LABEL = "com.alivelock.app"
OLD_LABEL = "com.alivelock.launcher"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
PLIST_PATH = LAUNCH_AGENTS_DIR / f"{LABEL}.plist"
OLD_PLIST_PATH = LAUNCH_AGENTS_DIR / f"{OLD_LABEL}.plist"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
APP_BUNDLE = Path.home() / "Applications" / "AliveLock.app"
APP_EXEC = APP_BUNDLE / "Contents" / "MacOS" / "AliveLock"

PLIST_TEMPLATE = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>{APP_BUNDLE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/alivelock.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/alivelock.stderr.log</string>
</dict>
</plist>
"""


def install_login_agent():
    print("=" * 60)
    print("🚀 alivelock - Otomatik Açılış (LaunchAgent) Kurulumu")
    print("=" * 60)

    try:
        LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)

        # Eski servisi durdur ve sil
        if OLD_PLIST_PATH.exists():
            print("[1/4] Eski servis durduruluyor...")
            subprocess.run(["launchctl", "unload", str(OLD_PLIST_PATH)], capture_output=True)
            try:
                OLD_PLIST_PATH.unlink()
            except Exception:
                pass

        if PLIST_PATH.exists():
            print("[2/4] Mevcut alivelock servisi durduruluyor...")
            subprocess.run(["launchctl", "unload", str(PLIST_PATH)], capture_output=True)

        print(f"[3/4] Plist dosyası oluşturuluyor: {PLIST_PATH}")
        with open(PLIST_PATH, "w", encoding="utf-8") as f:
            f.write(PLIST_TEMPLATE)

        print(f"[4/5] LaunchAgent macOS oturumuna kaydediliyor...")
        res = subprocess.run(["launchctl", "load", "-w", str(PLIST_PATH)], capture_output=True, text=True)

        print(f"[5/5] macOS Sistem Ayarları -> Giriş Öğeleri (Login Items) kaydediliyor...")
        applescript = f'''
        tell application "System Events"
            delete (every login item whose name is "AliveLock")
            make login item at end with properties {{path:"{APP_BUNDLE}", name:"AliveLock", hidden:false}}
        end tell
        '''
        subprocess.run(["osascript", "-e", applescript], capture_output=True)

        if res.returncode == 0:
            print("\n✅ Kurulum Başarıyla Tamamlandı!")
            print("   - Mac açıldığında AliveLock otomatik olarak başlayacaktır.")
            print("   - Hem LaunchAgent hem de macOS Giriş Öğeleri (Login Items) yapılandırıldı.")
            print("   - Loglar /tmp/alivelock.stdout.log dosyasında tutulacaktır.")
        else:
            print(f"\n⚠️  Uyarı: Servis yazıldı ancak launchctl çıktısı: {res.stderr.strip()}")

    except Exception as e:
        print(f"\n❌ Kurulum sırasında hata: {e}")


if __name__ == "__main__":
    install_login_agent()
