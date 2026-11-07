#!/usr/bin/env python3
"""
AliveLock - Yerel macOS Cocoa (.app) Paketi ve Kısayol Kurucusu
Swift AppKit ile derlenen %100 yerel Cocoa uygulamasını .app paketine yerleştirir.
Full-HD neon kilit ikonunu ve animasyon görsellerini entegre eder.
"""

import os
import stat
import shutil
import subprocess
from pathlib import Path

APP_NAME = "AliveLock"
BUNDLE_ID = "com.alivelock.app"
PROJECT_DIR = Path(__file__).resolve().parent.parent
BUILD_DIR = PROJECT_DIR / "build"
NATIVE_BIN = BUILD_DIR / "AliveLock"
SWIFT_SOURCE = PROJECT_DIR / "src" / "ui_swift" / "MacGuardApp.swift"

USER_HOME = Path.home()
APPLICATIONS_DIR = USER_HOME / "Applications"
DESKTOP_DIR = USER_HOME / "Desktop"

APP_ICON = PROJECT_DIR / "assets" / "AppIcon.icns"
LOCK_ARTWORK = PROJECT_DIR / "assets" / "LockArtwork.png"


def compile_native_binary():
    """Swift AppKit yerel ikili dosyasını derler."""
    print("[1/4] Yerel macOS (Swift AppKit) ikili dosyası derleniyor...")
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    cache_dir = PROJECT_DIR / "scratch" / "modulecache"
    cache_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        "swiftc",
        "-O",
        "-module-cache-path", str(cache_dir),
        "-o", str(NATIVE_BIN),
        str(SWIFT_SOURCE)
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Swift derleme hatası: {res.stderr}")
    print("      ✅ AliveLock başarıyla derlendi.")


def build_app_bundle(target_path: Path):
    """Hedef yola .app paketini kurar."""
    contents_dir = target_path / "Contents"
    macos_dir = contents_dir / "MacOS"
    resources_dir = contents_dir / "Resources"

    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)

    # Info.plist
    info_plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>{BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>{APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>4.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Yetkisiz erişim girişimlerini fotoğraflamak ve güvenliği sağlamak için kamera erişimi gereklidir.</string>
</dict>
</plist>
"""
    with open(contents_dir / "Info.plist", "w", encoding="utf-8") as f:
        f.write(info_plist)

    # Yerel binary kopyala
    dest_bin = macos_dir / APP_NAME
    shutil.copyfile(NATIVE_BIN, dest_bin)
    dest_bin.chmod(dest_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    # İkon ve Tüm Görsel Varlıkları (Assets) kopyala
    assets_dir = PROJECT_DIR / "assets"
    if assets_dir.exists():
        for asset_file in assets_dir.glob("*.*"):
            if asset_file.is_file():
                shutil.copyfile(asset_file, resources_dir / asset_file.name)
    print("      🎨 Tüm görsel varlıklar (assets) uygulama paketine kopyalandı.")

    # Kamera ve Ağ yetki dosyası (Entitlements) oluştur
    entitlements_path = BUILD_DIR / "entitlements.plist"
    entitlements_content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
"""
    with open(entitlements_path, "w", encoding="utf-8") as f:
        f.write(entitlements_content)

    # Paket imzala (TCC Kamera izninin her seferinde tekrar sorulmasını engeller)
    print("      🔏 Uygulama paketi yetkilerle mühürleniyor (codesign)...")
    sign_cmd = [
        "codesign",
        "--force",
        "--deep",
        "--sign", "-",
        "--entitlements", str(entitlements_path),
        "--identifier", BUNDLE_ID,
        str(target_path)
    ]
    res = subprocess.run(sign_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"      ⚠️  Codesign uyarısı: {res.stderr}")
    else:
        print(f"      ✅ Uygulama kimliği ({BUNDLE_ID}) ve kamera yetkileri başarıyla mühürlendi.")


def main():
    print("=" * 60)
    print("🚀 AliveLock - Full HD Neon Cocoa (.app) Kurucusu")
    print("=" * 60)

    # 0. Çalışan önceki AliveLock örneklerini sonlandır
    subprocess.run(["pkill", "-9", "-f", "AliveLock"], capture_output=True)

    # 1. Derle
    compile_native_binary()

    # 2. Master .app paketini ~/Applications klasörüne kur
    APPLICATIONS_DIR.mkdir(parents=True, exist_ok=True)
    master_app = APPLICATIONS_DIR / f"{APP_NAME}.app"
    if master_app.exists():
        shutil.rmtree(master_app)
    print(f"[2/3] Master .app paketi kuruluyor:\n      {master_app}")
    build_app_bundle(master_app)
    subprocess.run(["touch", str(master_app)], capture_output=True)

    # 3. Masaüstü ve proje dizinindeki mükerrer kopyaları temizle (Spotlight'ta tek uygulama kalması için)
    print("[3/3] Mükerrer kopyalar temizleniyor...")
    for old_path in [
        PROJECT_DIR / f"{APP_NAME}.app",
        PROJECT_DIR / "alivelock.app",
        DESKTOP_DIR / f"{APP_NAME}.app",
        DESKTOP_DIR / "alivelock.app"
    ]:
        if old_path.exists():
            try:
                if old_path.is_dir():
                    shutil.rmtree(old_path)
                else:
                    old_path.unlink()
                print(f"      🗑️  Temizlendi: {old_path}")
            except Exception as e:
                print(f"      ℹ️  Temizlenemedi ({old_path}): {e}")

    # LaunchServices kaydını güncelle
    lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if Path(lsreg).exists():
        subprocess.run([lsreg, "-f", str(master_app)], capture_output=True)

    print("\n🎉 Kurulum Tamamlandı! AliveLock tekil master uygulama olarak ~/Applications dizinine kuruldu.")


if __name__ == "__main__":
    main()
