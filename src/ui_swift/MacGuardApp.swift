import AppKit
import LocalAuthentication
import Foundation
import Carbon
import QuartzCore
import AVFoundation
import OpenDirectory
import UniformTypeIdentifiers

// MARK: - Direct macOS User Password Verification (OpenDirectory)
func verifyUserPassword(_ pass: String) -> Bool {
    guard !pass.isEmpty else { return false }
    do {
        let session = ODSession.default()
        let node = try ODNode(session: session, type: ODNodeType(kODNodeTypeLocalNodes))
        let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        try record.verifyPassword(pass)
        return true
    } catch {
        return false
    }
}

// MARK: - Global HotKey Handler (Command + 7)
func globalHotKeyHandler(nextHandler: EventHandlerCallRef?, theEvent: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        if let appDel = NSApp.delegate as? AppDelegate {
            appDel.lockInstantlyViaHotKey()
        }
    }
    return noErr
}

// MARK: - UI-md Compliant Design System & Color Tokens
struct AliveLockTheme {
    // Surfaces & Backgrounds (Material 3 + Apple HIG Layering)
    static let bgBase = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 0.88)
    static let surfaceLowest = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 0.92)
    static let surfaceLow = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.17, alpha: 0.94)
    static let surface = NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.21, alpha: 0.96)
    static let surfaceHigh = NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.27, alpha: 0.98)
    static let surfaceHighest = NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.34, alpha: 1.0)
    static let surfaceHover = NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.30, alpha: 0.96)

    // Borders & Strokes (Subtle Glassmorphic Outlines)
    static let borderSubtle = NSColor(white: 1.0, alpha: 0.08)
    static let borderDefault = NSColor(white: 1.0, alpha: 0.14)
    static let borderStrong = NSColor(white: 1.0, alpha: 0.22)
    static let borderFocused = NSColor(calibratedRed: 0.22, green: 0.67, blue: 0.96, alpha: 0.65)

    // Typography (WCAG AAA High-Contrast)
    static let textPrimary = NSColor(calibratedWhite: 0.98, alpha: 1.0)
    static let textSecondary = NSColor(calibratedRed: 0.64, green: 0.71, blue: 0.82, alpha: 1.0) // Slate 300
    static let textTertiary = NSColor(calibratedRed: 0.44, green: 0.51, blue: 0.62, alpha: 1.0)  // Slate 500
    static let textDisabled = NSColor(calibratedWhite: 0.35, alpha: 1.0)

    // Accents (Apple HIG Semantics)
    static let accentCyan = NSColor(calibratedRed: 0.22, green: 0.67, blue: 0.96, alpha: 1.0)   // #38BDF8 Sky Cyan
    static let accentBlue = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1.0)   // #0A84FF Apple Blue
    static let accentEmerald = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.53, alpha: 1.0) // #30D158 Apple Green
    static let accentPurple = NSColor(calibratedRed: 0.68, green: 0.49, blue: 0.98, alpha: 1.0) // #A78BFA Violet
    static let accentAmber = NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1.0)  // #FBBF24 Amber
    static let accentRed = NSColor(calibratedRed: 0.97, green: 0.38, blue: 0.38, alpha: 1.0)    // #F87171 Red

    // Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20
    static let radiusPill: CGFloat = 999
}

// MARK: - Target App Model
struct TargetAppConfig {
    let processName: String
    let bundleId: String
    let displayName: String
}

// MARK: - Intruder Camera Capture (Yetkisiz Girişlerde Fotoğraf Çekme & Loglama)
class IntruderCamera: NSObject {
    static let shared = IntruderCamera()
    private let cameraQueue = DispatchQueue(label: "com.alivelock.cameraQueue")
    private var session: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var activeHandler: PhotoCaptureHandler?
    private var lastCaptureTime = Date.distantPast
    var projectDir: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/projects/mac-guard").path

    func ensureCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }
    }

    func captureIntruderPhoto(appName: String) {
        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) > 1.2 else {
            NSLog("[AliveLock] ℹ️ Fotoğraf çekimi atlandı (Son 1.2 sn içinde zaten çekildi).")
            return
        }
        lastCaptureTime = now

        let folder = "\(projectDir)/logs/intruders"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: nil)

        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            self.takePhoto(folder: folder, appName: appName)
        }
    }

    private func takePhoto(folder: String, appName: String) {
        if let existing = self.session {
            if existing.isRunning {
                existing.stopRunning()
            }
            self.session = nil
            self.photoOutput = nil
            self.activeHandler = nil
        }

        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video) ??
              AVCaptureDevice.DiscoverySession(
                  deviceTypes: [.builtInWideAngleCamera, .external],
                  mediaType: .video,
                  position: .unspecified
              ).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            NSLog("[AliveLock] ⚠️ Kamera aygıtı bağlanamadı.")
            return
        }
        captureSession.addInput(input)

        let output = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)

        self.session = captureSession
        self.photoOutput = output

        captureSession.startRunning()

        // Kamera sensörünün ışık ve odak ayarını yapması için 0.25s bekle
        Thread.sleep(forTimeInterval: 0.25)

        let settings = AVCapturePhotoSettings()
        let handler = PhotoCaptureHandler(folder: folder, appName: appName, session: captureSession) { [weak self] in
            self?.cameraQueue.async {
                self?.activeHandler = nil
                self?.session = nil
                self?.photoOutput = nil
            }
        }
        self.activeHandler = handler
        output.capturePhoto(with: settings, delegate: handler)
    }
}

class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate {
    let folder: String
    let appName: String
    let session: AVCaptureSession
    let onComplete: () -> Void

    init(folder: String, appName: String, session: AVCaptureSession, onComplete: @escaping () -> Void) {
        self.folder = folder
        self.appName = appName
        self.session = session
        self.onComplete = onComplete
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        session.stopRunning()
        defer { onComplete() }

        if let error = error {
            NSLog("[AliveLock] ❌ Fotoğraf çekim hatası: %@", error.localizedDescription)
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            NSLog("[AliveLock] ❌ Fotoğraf verisi oluşturulamadı.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let safeName = appName
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "izinsiz_giris_\(safeName)_\(timestamp).jpg"
        let filePath = "\(folder)/\(filename)"

        do {
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            NSLog("[AliveLock] 📸 Yetkisiz erişim fotoğrafı kaydedildi: %@", filePath)

            // Telegram Bildirimi Tetikle
            if let delegate = AppDelegate.shared,
               delegate.telegramEnabled,
               !delegate.telegramBotToken.isEmpty,
               !delegate.telegramChatId.isEmpty {
                NSLog("[AliveLock] ✈️ Telegram bildirim kuyruğuna alındı...")
                TelegramNotifier.shared.sendAlert(
                    photoData: data,
                    appName: appName,
                    reason: "Yetkisiz Erişim / Hatalı Doğrulama Girişimi",
                    token: delegate.telegramBotToken,
                    chatId: delegate.telegramChatId
                )
            }
        } catch {
            NSLog("[AliveLock] ❌ Fotoğraf kaydedilemedi: %@", error.localizedDescription)
        }
    }
}

// MARK: - Telegram Security Notifier (Fotoğraflı & Anlık Güvenlik Bildirimi)
class TelegramNotifier {
    static let shared = TelegramNotifier()

    func sendAlert(photoData: Data?, appName: String, reason: String, token: String, chatId: String, completion: ((Bool, String) -> Void)? = nil) {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChatId = chatId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanToken.isEmpty, !cleanChatId.isEmpty else {
            completion?(false, "Telegram Bot Token veya Chat ID boş.")
            return
        }

        let hostname = Host.current().localizedName ?? "MacBook"
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        let caption = """
        🚨 AliveLock Güvenlik Uyarısı!
        ⚠️ Durum: \(reason)
        📱 Uygulama: \(appName)
        💻 Cihaz: \(hostname)
        ⏰ Zaman: \(timestamp)
        """

        if let photoData = photoData, !photoData.isEmpty {
            sendPhotoMultipart(token: cleanToken, chatId: cleanChatId, photoData: photoData, caption: caption, completion: completion)
        } else {
            sendMessageText(token: cleanToken, chatId: cleanChatId, text: caption, completion: completion)
        }
    }

    private func sendPhotoMultipart(token: String, chatId: String, photoData: Data, caption: String, completion: ((Bool, String) -> Void)?) {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendPhoto") else {
            completion?(false, "Geçersiz Telegram URL adresi.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 1. chat_id
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".utf8))
        body.append(Data("\(chatId)\r\n".utf8))

        // 2. caption
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".utf8))
        body.append(Data("\(caption)\r\n".utf8))

        // 3. photo file
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"izinsiz_giris.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(photoData)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[AliveLock] ❌ Telegram fotoğraf gönderim hatası: %@", error.localizedDescription)
                DispatchQueue.main.async { completion?(false, "Bağlantı hatası: \(error.localizedDescription)") }
                return
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                NSLog("[AliveLock] ✈️ Telegram fotoğraf bildirimi başarıyla iletildi!")
                DispatchQueue.main.async { completion?(true, "Fotoğraflı bildirim Telegram'a başarıyla iletildi! ✅") }
            } else {
                let respStr = String(data: data ?? Data(), encoding: .utf8) ?? ""
                NSLog("[AliveLock] ⚠️ Telegram API hatası: %@", respStr)
                DispatchQueue.main.async { completion?(false, "Telegram API hatası (\(respStr))") }
            }
        }
        task.resume()
    }

    func sendMessageText(token: String, chatId: String, text: String, completion: ((Bool, String) -> Void)?) {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            completion?(false, "Geçersiz Telegram URL adresi.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "chat_id": chatId,
            "text": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion?(false, error.localizedDescription) }
                return
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                DispatchQueue.main.async { completion?(true, "Test mesajı Telegram'a başarıyla ulaştı! ✅") }
            } else {
                let respStr = String(data: data ?? Data(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion?(false, "Telegram API hatası (\(respStr))") }
            }
        }
        task.resume()
    }
}

// MARK: - Real-Time Biometric Mismatch Observer (Apple BiometricKit Status 57 = Hatalı Parmak İzi)
class BiometricFailureObserver {
    static let shared = BiometricFailureObserver()
    private var process: Process?
    private var isRunning = false
    var onMismatch: (() -> Void)?

    func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = [
            "stream",
            "--predicate",
            "process == 'coreauthd' and (eventMessage contains 'statusMessage:client: 57' or eventMessage contains 'statusMessage: 57')"
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            if let str = String(data: data, encoding: .utf8) {
                if str.contains("statusMessage:client: 57") || str.contains("statusMessage: 57") {
                    NSLog("[AliveLock] 📸 Tanınmayan parmak izi tespit edildi (BiometricKit status 57)! Fotoğraf tetikleniyor...")
                    DispatchQueue.main.async {
                        self.onMismatch?()
                    }
                }
            }
        }

        try? proc.run()
        self.process = proc
        NSLog("[AliveLock] 👁️ Parmak izi hata izleyicisi (Status 57) başlatıldı.")
    }
}

// MARK: - Main Application Controller
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    var fullScreenWindow: LockScreenWindow!
    var privacyCurtain: PrivacyCurtainWindow!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    
    var currentMode: String = "Korunuyor"
    var projectDir: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev/projects/mac-guard").path
    var pythonBin: String = "/usr/bin/python3"
    
    var targetApps: [TargetAppConfig] = []
    var authenticatedPids = Set<pid_t>()
    var isAuthenticating = false

    // Telegram Security Settings
    var telegramBotToken: String = ""
    var telegramChatId: String = ""
    var telegramEnabled: Bool = false
    var telegramSettingsWindow: TelegramSettingsWindow?
    
    // UI Elements
    var centerBox: NSBox!
    var animationOverlayView: UltraLockAnimationView?
    var statusBadgeLabel: NSTextField!
    var statusDotView: NSView!
    var feedbackLabel: NSTextField!
    var aliCard: NSBox!
    var protectCard: NSBox!
    var manageAppsCard: NSBox!
    var lockedAppsWindow: LockedAppsManagerWindow?
    var dashboardWindow: AliveLockDashboardWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        ProcessInfo.processInfo.disableAutomaticTermination("AliveLock Güvenlik Servisi")
        ProcessInfo.processInfo.disableSuddenTermination()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.alivelock.app.showLockScreen"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showLockScreen()
        }
        
        locateProject()
        loadConfig()
        
        setupStatusItem()
        setupLockScreen()
        setupAppWatcher()
        setupGlobalHotKey()
        setupSleepWakeObservers()
        IntruderCamera.shared.ensureCameraPermission()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        BiometricFailureObserver.shared.onMismatch = { [weak self] in
            guard let self = self else { return }
            let appName = self.privacyCurtain.isVisible ? self.privacyCurtain.currentAppName : "KilitEkrani"
            IntruderCamera.shared.captureIntruderPhoto(appName: appName)

            if self.privacyCurtain.isVisible {
                self.privacyCurtain.showBiometricFailure()
            } else if self.fullScreenWindow.isVisible {
                self.feedbackLabel?.textColor = NSColor(calibratedRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0)
                self.feedbackLabel?.stringValue = "❌ Tanınmayan parmak izi! Fotoğraf kaydedildi."
            }
        }
        BiometricFailureObserver.shared.startMonitoring()
        
        if isProtectedMode() {
            enforceProtectionOnRunningApps()
        }
        
        showLockScreen()
    }

    // MARK: - Sleep / Wake / Lock Screen Observers (Güç Düğmesi & Ekran Açılış Takibi)
    func setupSleepWakeObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        // 1. Ekran Kapandığında / Güç Tuşuna Basıldığında / Kilitlendiğinde
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onScreenSleepOrLock()
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onScreenSleepOrLock()
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onScreenSleepOrLock()
        }

        // 2. Ekran Açıldığında / Tuşa Tekrar Basıldığında / Kilit Açıldığında
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onScreenWakeOrUnlock()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onScreenWakeOrUnlock()
        }
        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onScreenWakeOrUnlock()
        }
    }

    func onScreenSleepOrLock() {
        // Ekran kapandığı salise: Açık olan WhatsApp ve Fotoğrafları derhal yok et!
        authenticatedPids.removeAll()
        currentMode = "Korunuyor"
        saveConfig()
        updateStatusBadge()
        updateStatusItem()
        enforceProtectionOnRunningApps()
    }

    func onScreenWakeOrUnlock() {
        // Ekran açıldığı salise: Uygulamaların kapalı olduğundan emin ol ve KİLİT EKRANINI DOĞRUDAN ÖNE GETİR!
        authenticatedPids.removeAll()
        currentMode = "Korunuyor"
        saveConfig()
        updateStatusBadge()
        updateStatusItem()
        enforceProtectionOnRunningApps()

        // macOS WindowServer ekranı çizdiği anda kilit ekranını öne al
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            self.showLockScreen()
        }
    }

    func isProtectedMode() -> Bool {
        return currentMode == "Korunuyor" || currentMode == "Misafir"
    }

    // MARK: - Global HotKey (Command + 7)
    func setupGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            nil
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x414C4F4B), id: 1)
        _ = RegisterEventHotKey(
            26, // '7' tuşu
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // Command + 7 basıldığında (Masaüstündeyken kilitler ve KİLİT EKRANINDA KALIR)
    @objc func lockInstantlyViaHotKey() {
        currentMode = "Korunuyor"
        authenticatedPids.removeAll()
        saveConfig()
        updateStatusBadge()
        updateStatusItem()
        buildStatusMenu()

        enforceProtectionOnRunningApps()
        showLockScreen()
        dashboardWindow?.updateStatus()
        playFullHDLockAnimation(shouldCloseWindowAfter: false)

        sendNotification(title: "AliveLock", body: "🔒 Korunuyor modu aktif. Kişisel uygulamalar kilitlendi.")
    }

    // Kilit ekranındaki Korunuyor kartına tıklandığında
    @objc func handleProtectMode() {
        currentMode = "Korunuyor"
        authenticatedPids.removeAll()
        saveConfig()
        updateStatusBadge()
        updateStatusItem()
        buildStatusMenu()
        dashboardWindow?.updateStatus()

        enforceProtectionOnRunningApps()
        
        playFullHDLockAnimation(shouldCloseWindowAfter: true)
        
        sendNotification(title: "AliveLock", body: "🔒 Korunuyor modu aktif. Seçili uygulamalar kilitlendi.")
    }

    // MARK: - Full HD Neon Key & Lock Animation (Ultra Canlı Renkler)
    func playFullHDLockAnimation(shouldCloseWindowAfter: Bool) {
        guard let contentView = fullScreenWindow.contentView else { return }
        
        animationOverlayView?.removeFromSuperview()
        let animView = UltraLockAnimationView(frame: contentView.bounds, projectDir: projectDir)
        animView.autoresizingMask = [.width, .height]
        contentView.addSubview(animView, positioned: .above, relativeTo: centerBox)
        animationOverlayView = animView
        
        animView.startAnimation { [weak self] in
            guard let self = self else { return }
            
            if shouldCloseWindowAfter {
                // Seçim yapıldı: Pencereyi tamamen kapat ve masaüstüne dön!
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.35
                    self.fullScreenWindow.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.fullScreenWindow.orderOut(nil)
                    self.fullScreenWindow.alphaValue = 1.0
                    animView.removeFromSuperview()
                    self.animationOverlayView = nil
                })
            } else {
                // Kısayolla kilitlendi: Sadece animasyon katmanını kaldır, kilit ekranı açık kalsın!
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.35
                    animView.animator().alphaValue = 0.0
                }, completionHandler: {
                    animView.removeFromSuperview()
                    self.animationOverlayView = nil
                })
            }
        }
    }

    // Uygulamadan çıkış yapılmak istendiğinde MUTLAKA Touch ID sor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let context = LAContext()
        let reason = "AliveLock uygulamasını kapatmak için Touch ID ile yönetici doğrulaması gereklidir:"
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    sender.reply(toApplicationShouldTerminate: true)
                } else {
                    sender.reply(toApplicationShouldTerminate: false)
                    self?.sendNotification(title: "AliveLock Güvenlik", body: "⛔ Kapatma engellendi: Yönetici parmak izi doğrulanmadı.")
                }
            }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLockScreen()
        return true
    }

    // MARK: - Configuration & Paths
    func locateProject() {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            let parentDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path
            if FileManager.default.fileExists(atPath: "\(parentDir)/config.json") {
                projectDir = parentDir
            }
        } else {
            let current = FileManager.default.currentDirectoryPath
            if FileManager.default.fileExists(atPath: "\(current)/config.json") {
                projectDir = current
            }
        }

        let venvPython = "\(projectDir)/venv/bin/python3"
        if FileManager.default.fileExists(atPath: venvPython) {
            pythonBin = venvPython
        } else {
            pythonBin = "/usr/bin/python3"
        }
        IntruderCamera.shared.projectDir = projectDir
    }

    func loadConfig() {
        let configPath = "\(projectDir)/config.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let mode = json["current_mode"] as? String {
            if mode == "Misafir" || mode == "Korunuyor" {
                currentMode = "Korunuyor"
            } else {
                currentMode = "Yonetici"
            }
        }

        if let token = json["telegram_bot_token"] as? String {
            telegramBotToken = token
        }
        if let chatId = json["telegram_chat_id"] as? String {
            telegramChatId = chatId
        }
        if let enabled = json["telegram_enabled"] as? Bool {
            telegramEnabled = enabled
        }

        targetApps.removeAll()
        if let apps = json["target_apps"] as? [[String: Any]], !apps.isEmpty {
            for appDict in apps {
                let pName = appDict["process_name"] as? String ?? ""
                let bId = appDict["bundle_id"] as? String ?? ""
                let dName = appDict["display_name"] as? String ?? pName
                if !pName.isEmpty || !bId.isEmpty {
                    targetApps.append(TargetAppConfig(processName: pName, bundleId: bId, displayName: dName))
                }
            }
        } else {
            // Varsayılan kilitli uygulamalar
            targetApps = [
                TargetAppConfig(processName: "WhatsApp", bundleId: "net.whatsapp.WhatsApp", displayName: "WhatsApp"),
                TargetAppConfig(processName: "Photos", bundleId: "com.apple.Photos", displayName: "Fotoğraflar")
            ]
        }
    }

    func saveConfig() {
        let configPath = "\(projectDir)/config.json"
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        json["current_mode"] = currentMode
        json["telegram_bot_token"] = telegramBotToken
        json["telegram_chat_id"] = telegramChatId
        json["telegram_enabled"] = telegramEnabled
        let appsArray: [[String: Any]] = targetApps.map {
            [
                "process_name": $0.processName,
                "bundle_id": $0.bundleId,
                "display_name": $0.displayName
            ]
        }
        json["target_apps"] = appsArray

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Real-Time App Lock Watcher & Prevention Shield
    func setupAppWatcher() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.handleAppAccess(app)
            }
        }

        nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.handleAppAccess(app)
            }
        }
    }

    func isTargetApp(_ app: NSRunningApplication) -> (Bool, String) {
        let bundleId = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        let exec = (app.executableURL?.lastPathComponent ?? "").lowercased()

        for target in targetApps {
            let pName = target.processName.lowercased()
            let bId = target.bundleId.lowercased()
            let dName = target.displayName.lowercased()

            if (!bId.isEmpty && (bundleId == bId || bundleId.contains(bId))) ||
               (!pName.isEmpty && (name == pName || name.contains(pName) || exec == pName)) ||
               (!dName.isEmpty && (name == dName || name.contains(dName))) {
                return (true, target.displayName)
            }
        }

        return (false, "")
    }

    // MARK: - Error Helper (Yanlış Parola / Parmak İzi Tespiti)
    func isWrongCredentialsError(_ error: Error?) -> Bool {
        guard let error = error else { return false }
        if let laError = error as? LAError {
            return laError.code == .authenticationFailed || laError.code == .biometryLockout
        }
        let nsError = error as NSError
        if nsError.domain == LAErrorDomain {
            return nsError.code == LAError.authenticationFailed.rawValue ||
                   nsError.code == LAError.biometryLockout.rawValue
        }
        return false
    }

    // Uygulama açılmak istendiğinde anında GİZLİLİK PERDESİ ile ekranı ört ve Şifre / Touch ID sor
    func handleAppAccess(_ app: NSRunningApplication) {
        guard isProtectedMode() else { return }

        let (matched, appName) = isTargetApp(app)
        guard matched else { return }

        if authenticatedPids.contains(app.processIdentifier) {
            return
        }

        guard !isAuthenticating else { return }
        isAuthenticating = true

        // 1. Hedef uygulamayı derhal gizle
        app.hide()

        // 2. Gizlilik perdesini sun ve kullanıcıdan doğrulama iste
        privacyCurtain.present(
            appName: appName,
            onSuccess: { [weak self] in
                guard let self = self else { return }
                self.isAuthenticating = false

                // BAŞARILI: Parmak izi veya şifre doğru girildiğinde otomatik YÖNETİCİ MODUNA GEÇ!
                // KESİNLİKLE FOTOĞRAF ÇEKİLMEZ!
                self.currentMode = "Yonetici"
                self.authenticatedPids.removeAll()
                self.saveConfig()
                self.updateStatusBadge()
                self.updateStatusItem()
                self.buildStatusMenu()

                self.authenticatedPids.insert(app.processIdentifier)
                app.unhide()
                app.activate(options: .activateIgnoringOtherApps)
                let name = NSFullUserName().isEmpty ? "Yönetici" : NSFullUserName()
                self.sendNotification(title: "AliveLock", body: "✅ Hoş geldin \(name)! Kimlik doğrulandı, Yönetici moduna geçildi.")
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                self.isAuthenticating = false

                // İptal edildi / ESC basıldı: KESİNLİKLE FOTOĞRAF ÇEKİLMEZ!
                app.hide()
                app.terminate()
                kill(app.processIdentifier, SIGKILL)
            }
        )
    }

    // KORUMA MODUNA GEÇİLDİĞİNDE AÇIK TÜM HEDEF UYGULAMALARI ANINDA KAPAT
    func enforceProtectionOnRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            let (matched, _) = isTargetApp(app)
            if matched {
                app.hide()
                app.terminate()
                let pid = app.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    if kill(pid, 0) == 0 {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
    }

    // MARK: - Menu Bar Status Item
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        buildStatusMenu()
    }

    func updateStatusItem() {
        if let button = statusItem.button {
            button.title = (currentMode != "Korunuyor") ? "🛡️ Yönetici" : "🔒 Korunuyor"
        }
    }

    func buildStatusMenu() {
        let menu = NSMenu()
        
        let header = NSMenuItem(title: "AliveLock (Aktif: \(currentMode))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let dashboardItem = NSMenuItem(title: "🛡️ Genel Bakış (⌘ 7)", action: #selector(showLockScreen), keyEquivalent: "7")
        dashboardItem.keyEquivalentModifierMask = [.command]
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let manageItem = NSMenuItem(title: "🔒 Kilitli Uygulamalar (⌘ ,)", action: #selector(openLockedAppsManager), keyEquivalent: ",")
        manageItem.keyEquivalentModifierMask = [.command]
        manageItem.target = self
        menu.addItem(manageItem)

        let galleryItem = NSMenuItem(title: "📸 Güvenlik Galerisi (⌘ G)", action: #selector(openGallery), keyEquivalent: "g")
        galleryItem.keyEquivalentModifierMask = [.command]
        galleryItem.target = self
        menu.addItem(galleryItem)

        let telegramItem = NSMenuItem(title: "✈️ Telegram Ayarları (⌘ T)", action: #selector(openTelegramSettings), keyEquivalent: "t")
        telegramItem.keyEquivalentModifierMask = [.command]
        telegramItem.target = self
        menu.addItem(telegramItem)

        menu.addItem(NSMenuItem.separator())

        let adminItem = NSMenuItem(title: "👤 Yönetici Moduna Geç (Touch ID)", action: #selector(handleAliMode), keyEquivalent: "1")
        adminItem.target = self
        menu.addItem(adminItem)

        let protectItem = NSMenuItem(title: "🔒 Korunuyor Moduna Geç", action: #selector(handleProtectMode), keyEquivalent: "")
        protectItem.target = self
        menu.addItem(protectItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Çıkış Yap (Touch ID Gerekir)", action: #selector(requestQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func openGallery() {
        showLockScreen()
        dashboardWindow?.switchTab(to: 2)
    }

    @objc func requestQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Full Screen Modal Lock Screen
    func setupLockScreen() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Hedef uygulamalar açılmaya çalışıldığında anında ekranı örten gizlilik perdesi (.floating level: 3)
        privacyCurtain = PrivacyCurtainWindow(screenRect: screenRect)
        privacyCurtain.onCancel = { [weak self] in
            guard let self = self else { return }
            self.isAuthenticating = false
            self.privacyCurtain.orderOut(nil)
        }

        fullScreenWindow = LockScreenWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        fullScreenWindow.level = .floating
        fullScreenWindow.backgroundColor = .clear
        fullScreenWindow.isOpaque = false
        fullScreenWindow.hasShadow = false
        fullScreenWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        fullScreenWindow.isReleasedWhenClosed = false

        let rootContainer = NSView(frame: screenRect)
        fullScreenWindow.contentView = rootContainer

        // Arka plan: Modern Saydam Buzlu Cam (Frosted Glass) Efekti
        let blurView = NSVisualEffectView(frame: screenRect)
        blurView.material = .fullScreenUI
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        rootContainer.addSubview(blurView)

        // Gözü yormayan derinlik katmanı (Göz konforu için dengeli karanlık filtre)
        let darkOverlay = ModernBox(frame: screenRect)
        darkOverlay.fillColor = AliveLockTheme.bgBase
        darkOverlay.borderWidth = 0
        darkOverlay.autoresizingMask = [.width, .height]
        rootContainer.addSubview(darkOverlay)

        let boxWidth: CGFloat = min(max(screenRect.width * 0.40, 520), 560)
        let boxHeight: CGFloat = 630
        let boxX = (screenRect.width - boxWidth) / 2
        let boxY = (screenRect.height - boxHeight) / 2
        let cardWidth: CGFloat = boxWidth - 64
        let cardHeight: CGFloat = 98

        centerBox = ModernBox(frame: NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight))
        centerBox.fillColor = AliveLockTheme.surfaceLow
        centerBox.borderColor = AliveLockTheme.borderDefault
        centerBox.borderWidth = 1.0
        centerBox.cornerRadius = AliveLockTheme.radiusXl
        rootContainer.addSubview(centerBox)

        // Header Title with SF Symbol Lock Shield
        let headerIcon = NSImageView(frame: NSRect(x: 32, y: boxHeight - 65, width: 28, height: 28))
        if let shieldImg = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            headerIcon.image = shieldImg.withSymbolConfiguration(config) ?? shieldImg
            headerIcon.contentTintColor = AliveLockTheme.accentCyan
        }
        centerBox.addSubview(headerIcon)

        let titleLabel = NSTextField(labelWithString: "AliveLock - Güvenlik Kilidi")
        titleLabel.frame = NSRect(x: 68, y: boxHeight - 68, width: boxWidth - 120, height: 32)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        centerBox.addSubview(titleLabel)

        // Telegram Hızlı Ayar Butonu
        let telegramQuickBtn = NSButton(frame: NSRect(x: boxWidth - 54, y: boxHeight - 64, width: 28, height: 28))
        telegramQuickBtn.bezelStyle = .regularSquare
        telegramQuickBtn.isBordered = false
        if let planeImg = NSImage(systemSymbolName: "paperplane.circle.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            telegramQuickBtn.image = planeImg.withSymbolConfiguration(conf) ?? planeImg
            telegramQuickBtn.contentTintColor = AliveLockTheme.accentCyan
        }
        telegramQuickBtn.toolTip = "Telegram Anlık Bildirim Ayarları (⌘ T)"
        telegramQuickBtn.target = self
        telegramQuickBtn.action = #selector(openTelegramSettings)
        centerBox.addSubview(telegramQuickBtn)

        let subtitleLabel = NSTextField(labelWithString: "Devam etmek için bir profil veya işlem seçiniz:")
        subtitleLabel.frame = NSRect(x: 34, y: boxHeight - 96, width: boxWidth - 68, height: 20)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = AliveLockTheme.textSecondary
        centerBox.addSubview(subtitleLabel)

        // Status Badge
        let badgeBg = ModernBox(frame: NSRect(x: 34, y: boxHeight - 134, width: 300, height: 28))
        badgeBg.fillColor = AliveLockTheme.surfaceLowest
        badgeBg.borderColor = AliveLockTheme.borderSubtle
        badgeBg.borderWidth = 1.0
        badgeBg.cornerRadius = 14
        centerBox.addSubview(badgeBg)

        statusDotView = NSView(frame: NSRect(x: 10, y: 9, width: 10, height: 10))
        statusDotView.wantsLayer = true
        statusDotView.layer?.cornerRadius = 5
        badgeBg.addSubview(statusDotView)

        statusBadgeLabel = NSTextField(labelWithString: "Aktif Durum: \(currentMode)")
        statusBadgeLabel.frame = NSRect(x: 26, y: 5, width: 265, height: 18)
        statusBadgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        statusBadgeLabel.textColor = AliveLockTheme.textPrimary
        badgeBg.addSubview(statusBadgeLabel)

        updateStatusBadge()

        // Card 1: Yönetici (Admin)
        aliCard = createCard(
            frame: NSRect(x: 32, y: boxHeight - 254, width: cardWidth, height: cardHeight),
            icon: "checkmark.shield.fill",
            title: "Yönetici (Admin)",
            shortcut: "[Tuş: 1]",
            subtitle: "Tam Yetki • Touch ID Doğrulaması",
            description: "Tüm kişisel uygulamaların kilidini kaldırır ve tam erişim sağlar.",
            accentColor: AliveLockTheme.accentEmerald,
            action: #selector(handleAliMode)
        )
        centerBox.addSubview(aliCard)

        // Card 2: Korunuyor Modu
        protectCard = createCard(
            frame: NSRect(x: 32, y: boxHeight - 366, width: cardWidth, height: cardHeight),
            icon: "lock.shield.fill",
            title: "Korunuyor",
            shortcut: "[Tuş: 2]",
            subtitle: "Korumalı Alan • Seçili Uygulamalar Kilitli",
            description: "Uygulamalara parmak izi okutulmadan kesinlikle erişilemez. (Kısayol: ⌘ 7)",
            accentColor: AliveLockTheme.accentCyan,
            action: #selector(handleProtectMode)
        )
        centerBox.addSubview(protectCard)

        // Card 3: Kilitlenecek Uygulamalar
        manageAppsCard = createCard(
            frame: NSRect(x: 32, y: boxHeight - 478, width: cardWidth, height: cardHeight),
            icon: "lock.square.stack.fill",
            title: "Kilitlenecek Uygulamalar",
            shortcut: "[Tuş: 3]",
            subtitle: "Kilitli Uygulama Listesini Yönet • Uygulama Ekle / Çıkar",
            description: "Korumalı modda kilitlenecek uygulamaları Finder veya çalışan listeden seçin.",
            accentColor: AliveLockTheme.accentPurple,
            action: #selector(openLockedAppsManager)
        )
        centerBox.addSubview(manageAppsCard)

        // Feedback Label
        feedbackLabel = NSTextField(labelWithString: "")
        feedbackLabel.frame = NSRect(x: 32, y: 56, width: cardWidth, height: 24)
        feedbackLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        feedbackLabel.alignment = .center
        feedbackLabel.textColor = AliveLockTheme.accentEmerald
        centerBox.addSubview(feedbackLabel)

        // Footer Hint
        let footerLabel = NSTextField(labelWithString: "💡 Kapatma seçeneği yoktur. İstediğiniz zaman ⌘ 7 ile anında kilitleyebilirsiniz.")
        footerLabel.frame = NSRect(x: 32, y: 20, width: cardWidth, height: 20)
        footerLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        footerLabel.alignment = .center
        footerLabel.textColor = AliveLockTheme.textSecondary
        centerBox.addSubview(footerLabel)
    }

    @objc func showLockScreen() {
        loadConfig()
        if dashboardWindow == nil {
            dashboardWindow = AliveLockDashboardWindow(appDelegate: self)
        }
        dashboardWindow?.level = .floating
        dashboardWindow?.updateStatus()
        dashboardWindow?.orderFrontRegardless()
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openTelegramSettings() {
        showLockScreen()
        dashboardWindow?.switchTab(to: 3)
    }

    @objc func handleScreenParametersChanged() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenRect = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        fullScreenWindow?.setFrame(screenRect, display: true)
        privacyCurtain?.setFrame(screenRect, display: true)
        if let win = dashboardWindow {
            let width: CGFloat = 1060
            let height: CGFloat = 680
            let rect = NSRect(
                x: screenRect.midX - (width / 2),
                y: screenRect.midY - (height / 2),
                width: width,
                height: height
            )
            win.setFrame(rect, display: true)
        }
    }

    func updateStatusBadge() {
        if currentMode != "Korunuyor" {
            statusDotView?.layer?.backgroundColor = AliveLockTheme.accentEmerald.cgColor
            statusBadgeLabel?.stringValue = "Aktif Durum: Yönetici (Tam Yetki - Açık)"
            statusBadgeLabel?.textColor = AliveLockTheme.accentEmerald
        } else {
            statusDotView?.layer?.backgroundColor = AliveLockTheme.accentCyan.cgColor
            statusBadgeLabel?.stringValue = "Aktif Durum: Korunuyor (Kilitli)"
            statusBadgeLabel?.textColor = AliveLockTheme.accentCyan
        }
    }

    func createCard(frame: NSRect, icon: String, title: String, shortcut: String, subtitle: String, description: String, accentColor: NSColor, action: Selector) -> NSBox {
        let box = ClickableCardBox(frame: frame)
        box.boxType = .custom
        let normalBg = AliveLockTheme.surfaceLow
        let hoverBg = AliveLockTheme.surfaceHover
        box.fillColor = normalBg
        box.normalFillColor = normalBg
        box.hoverFillColor = hoverBg
        box.borderColor = AliveLockTheme.borderDefault
        box.normalBorderColor = AliveLockTheme.borderDefault
        box.hoverBorderColor = accentColor.withAlphaComponent(0.50)
        box.borderWidth = 1.0
        box.cornerRadius = AliveLockTheme.radiusLg
        box.target = self
        box.action = action

        // İkon Arka Plan Rozeti (Soft Yuvarlatılmış Kare)
        let iconBadge = ModernBox(frame: NSRect(x: 16, y: (frame.height - 48) / 2, width: 48, height: 48))
        iconBadge.fillColor = accentColor.withAlphaComponent(0.14)
        iconBadge.borderColor = accentColor.withAlphaComponent(0.28)
        iconBadge.borderWidth = 1.0
        iconBadge.cornerRadius = AliveLockTheme.radiusMd
        box.addSubview(iconBadge)

        if let symImg = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            let imgView = NSImageView(frame: NSRect(x: 10, y: 10, width: 28, height: 28))
            imgView.image = symImg.withSymbolConfiguration(config) ?? symImg
            imgView.contentTintColor = accentColor
            iconBadge.addSubview(imgView)
        } else {
            let fallbackLbl = NSTextField(labelWithString: icon)
            fallbackLbl.frame = NSRect(x: 10, y: 10, width: 28, height: 28)
            fallbackLbl.font = NSFont.systemFont(ofSize: 20)
            fallbackLbl.alignment = .center
            iconBadge.addSubview(fallbackLbl)
        }

        let contentX: CGFloat = 76
        let contentWidth: CGFloat = frame.width - contentX - 16

        // Başlık
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: contentX, y: 66, width: contentWidth - 94, height: 22)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = false
        titleLabel.cell?.isScrollable = false
        box.addSubview(titleLabel)

        // Kısayol Rozeti
        let badgeLabel = NSTextField(labelWithString: shortcut)
        badgeLabel.frame = NSRect(x: frame.width - 106, y: 66, width: 90, height: 22)
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.alignment = .right
        badgeLabel.textColor = accentColor
        badgeLabel.maximumNumberOfLines = 1
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.cell?.wraps = false
        badgeLabel.cell?.isScrollable = false
        box.addSubview(badgeLabel)

        // Alt Başlık
        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.frame = NSRect(x: contentX, y: 41, width: contentWidth, height: 18)
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        subLabel.textColor = accentColor
        subLabel.maximumNumberOfLines = 1
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.cell?.wraps = false
        subLabel.cell?.isScrollable = false
        box.addSubview(subLabel)

        // Açıklama
        let descLabel = NSTextField(labelWithString: description)
        descLabel.frame = NSRect(x: contentX, y: 17, width: contentWidth, height: 18)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = AliveLockTheme.textSecondary
        descLabel.maximumNumberOfLines = 1
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.cell?.wraps = false
        descLabel.cell?.isScrollable = false
        box.addSubview(descLabel)
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.cell?.wraps = false
        descLabel.cell?.isScrollable = false
        box.addSubview(descLabel)

        return box
    }

    // MARK: - Actions
    @objc func handleAliMode() {
        feedbackLabel?.textColor = NSColor(calibratedRed: 0.063, green: 0.725, blue: 0.506, alpha: 1.0)
        feedbackLabel?.stringValue = "Touch ID / Yönetici doğrulaması bekleniyor..."

        let context = LAContext()
        let reason = "Yönetici Moduna geçmek ve kilitleri kaldırmak için Touch ID kullanın:"

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    self.currentMode = "Yonetici"
                    self.authenticatedPids.removeAll()
                    self.saveConfig()
                    self.updateStatusBadge()
                    self.updateStatusItem()
                    self.buildStatusMenu()
                    self.dashboardWindow?.updateStatus()

                    for app in NSWorkspace.shared.runningApplications {
                        let (matched, _) = self.isTargetApp(app)
                        if matched {
                            app.unhide()
                        }
                    }

                    let name = NSFullUserName().isEmpty ? "Yönetici" : NSFullUserName()
                    self.feedbackLabel?.stringValue = "✅ Hoş geldin \(name)! Kilit kaldırıldı."
                    self.sendNotification(title: "AliveLock", body: "Yönetici modu aktif. Tüm uygulamalar serbest.")
                    
                    // 0.6 saniye sonra tam ekran kilit açıksa kapat
                    if self.fullScreenWindow.isVisible {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.35
                            self.fullScreenWindow.animator().alphaValue = 0.0
                        }, completionHandler: {
                            self.fullScreenWindow.orderOut(nil)
                            self.fullScreenWindow.alphaValue = 1.0
                        })
                    }
                } else {
                    self.dashboardWindow?.updateStatus()
                    if self.isWrongCredentialsError(authError) {
                        IntruderCamera.shared.captureIntruderPhoto(appName: "KilitEkrani")
                        self.feedbackLabel?.textColor = NSColor(calibratedRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0)
                        self.feedbackLabel?.stringValue = "❌ Yetkilendirme başarısız! Fotoğraf kaydedildi."
                    } else {
                        self.feedbackLabel?.textColor = NSColor(calibratedRed: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)
                        self.feedbackLabel?.stringValue = "⚠️ Giriş iptal edildi."
                    }
                }
            }
        }
    }

    // MARK: - Locked Apps Manager (Kilitlenecek Uygulamalar Yöneticisi)
    @objc func openLockedAppsManager() {
        showLockScreen()
        dashboardWindow?.switchTab(to: 1)
    }

    func showLockedAppsManagerWindow() {
        if lockedAppsWindow == nil {
            lockedAppsWindow = LockedAppsManagerWindow(appDelegate: self)
        }
        lockedAppsWindow?.refreshList()
        lockedAppsWindow?.center()
        lockedAppsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func sendNotification(title: String, body: String) {
        let script = "display notification \"\(body)\" with title \"\(title)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}

// MARK: - Ultra-HD Neon Lock & Key Animation View (Canlı Renkler & Retina Çözünürlük)
class UltraLockAnimationView: NSView {
    private let lockContainer = CALayer()
    private let lockImageLayer = CALayer()
    private let keyLayer = CALayer()
    private let cyanRingLayer = CALayer()
    private let magentaRingLayer = CALayer()
    private let titleTextLayer = CATextLayer()
    private let subTextLayer = CATextLayer()
    private var projectDir: String = ""

    init(frame: NSRect, projectDir: String) {
        self.projectDir = projectDir
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.06, alpha: 0.96).cgColor
        setupUltraHDLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUltraHDLayers() {
        guard let rootLayer = self.layer else { return }
        let midX = bounds.midX
        let midY = bounds.midY
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // 1. Neon Cyan Shockwave Ring
        cyanRingLayer.frame = CGRect(x: midX - 110, y: midY - 30, width: 220, height: 220)
        cyanRingLayer.cornerRadius = 110
        cyanRingLayer.borderColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 0.9).cgColor
        cyanRingLayer.borderWidth = 3.5
        cyanRingLayer.opacity = 0
        rootLayer.addSublayer(cyanRingLayer)

        // 2. Neon Magenta Shockwave Ring
        magentaRingLayer.frame = CGRect(x: midX - 110, y: midY - 30, width: 220, height: 220)
        magentaRingLayer.cornerRadius = 110
        magentaRingLayer.borderColor = NSColor(calibratedRed: 0.95, green: 0.0, blue: 0.85, alpha: 0.8).cgColor
        magentaRingLayer.borderWidth = 2.5
        magentaRingLayer.opacity = 0
        rootLayer.addSublayer(magentaRingLayer)

        // 3. Ultra-HD Lock Artwork Container (200x200 Points = 400x400 Retina)
        lockContainer.frame = CGRect(x: midX - 100, y: midY - 20, width: 200, height: 200)
        lockContainer.shadowColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 1.0).cgColor
        lockContainer.shadowRadius = 35
        lockContainer.shadowOpacity = 0.9
        lockContainer.shadowOffset = .zero
        rootLayer.addSublayer(lockContainer)

        // Orijinal Neon Kilit Görselini Yükle (1024x1024 Full-HD)
        let artworkPath = "\(projectDir)/assets/LockArtwork.png"
        let bundleArtwork = Bundle.main.path(forResource: "LockArtwork", ofType: "png") ?? artworkPath
        
        if let artworkImg = NSImage(contentsOfFile: bundleArtwork) ?? NSImage(contentsOfFile: artworkPath) {
            lockImageLayer.contents = artworkImg
        } else if let sfLock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            lockImageLayer.contents = sfLock
        }
        lockImageLayer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        lockImageLayer.contentsGravity = .resizeAspect
        lockImageLayer.cornerRadius = 28
        lockImageLayer.masksToBounds = true
        lockImageLayer.borderColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 0.7).cgColor
        lockImageLayer.borderWidth = 2.0
        lockContainer.addSublayer(lockImageLayer)

        // 4. Ultra Canlı Altın Neon Anahtar (Golden Key)
        if let keyImg = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil) {
            let goldColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.1, alpha: 1.0)
            keyLayer.contents = renderVibrantKey(keyImg, color: goldColor)
        }
        keyLayer.frame = CGRect(x: midX + 150, y: midY + 45, width: 70, height: 70)
        keyLayer.contentsGravity = .resizeAspect
        keyLayer.shadowColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.0, alpha: 1.0).cgColor
        keyLayer.shadowRadius = 25
        keyLayer.shadowOpacity = 1.0
        keyLayer.shadowOffset = .zero
        rootLayer.addSublayer(keyLayer)

        // 5. Razor-Sharp Retina Typography
        titleTextLayer.string = "ALIVELOCK"
        titleTextLayer.font = NSFont.systemFont(ofSize: 26, weight: .black)
        titleTextLayer.fontSize = 26
        titleTextLayer.foregroundColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 1.0).cgColor
        titleTextLayer.alignmentMode = .center
        titleTextLayer.frame = CGRect(x: midX - 300, y: midY - 90, width: 600, height: 35)
        titleTextLayer.contentsScale = scale
        titleTextLayer.shadowColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 0.8).cgColor
        titleTextLayer.shadowRadius = 15
        titleTextLayer.shadowOpacity = 0.8
        titleTextLayer.opacity = 0
        rootLayer.addSublayer(titleTextLayer)

        subTextLayer.string = "KORUMA MODU AKTİF EDİLDİ • KİŞİSEL VERİLER KİLİTLENDİ"
        subTextLayer.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        subTextLayer.fontSize = 13
        subTextLayer.foregroundColor = NSColor(calibratedRed: 0.7, green: 0.85, blue: 1.0, alpha: 1.0).cgColor
        subTextLayer.alignmentMode = .center
        subTextLayer.frame = CGRect(x: midX - 300, y: midY - 120, width: 600, height: 25)
        subTextLayer.contentsScale = scale
        subTextLayer.opacity = 0
        rootLayer.addSublayer(subTextLayer)
    }

    private func renderVibrantKey(_ image: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: 140, height: 140)
        let output = NSImage(size: size)
        output.lockFocus()
        color.set()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }

    func startAnimation(completion: @escaping () -> Void) {
        let midX = bounds.midX
        let midY = bounds.midY

        // 1. Anahtar kilide doğru hızla kayar
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.38)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        let keyMove = CABasicAnimation(keyPath: "position")
        keyMove.fromValue = NSValue(point: NSPoint(x: midX + 185, y: midY + 80))
        keyMove.toValue = NSValue(point: NSPoint(x: midX + 30, y: midY + 80))
        keyMove.duration = 0.38
        keyMove.fillMode = .forwards
        keyMove.isRemovedOnCompletion = false
        keyLayer.add(keyMove, forKey: "keyMove")

        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            
            // 2. Anahtar kilidin içinde 90 derece döner
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.28)
            
            let keyRotate = CABasicAnimation(keyPath: "transform.rotation.z")
            keyRotate.fromValue = 0
            keyRotate.toValue = -Double.pi / 2
            keyRotate.duration = 0.28
            keyRotate.fillMode = .forwards
            keyRotate.isRemovedOnCompletion = false
            self.keyLayer.add(keyRotate, forKey: "keyRotate")

            CATransaction.setCompletionBlock {
                // 3. Kilit "tık" diye darbeyle kilitlenir ve neon şok dalgaları yayılır!
                self.triggerUltraLockSnap()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    completion()
                }
            }
            CATransaction.commit()
        }
        CATransaction.commit()
    }

    private func triggerUltraLockSnap() {
        // Yaylı (Spring) Elastik Büyüme ve Darbe
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.damping = 9
        spring.initialVelocity = 6
        spring.fromValue = 1.0
        spring.toValue = 1.15
        spring.duration = 0.4
        lockContainer.add(spring, forKey: "springSnap")

        // Cyan Neon Halka Patlaması
        let cyanScale = CABasicAnimation(keyPath: "transform.scale")
        cyanScale.fromValue = 0.6
        cyanScale.toValue = 2.1
        cyanScale.duration = 0.55

        let cyanOpacity = CABasicAnimation(keyPath: "opacity")
        cyanOpacity.fromValue = 1.0
        cyanOpacity.toValue = 0.0
        cyanOpacity.duration = 0.55

        let cyanGroup = CAAnimationGroup()
        cyanGroup.animations = [cyanScale, cyanOpacity]
        cyanGroup.duration = 0.55
        cyanRingLayer.add(cyanGroup, forKey: "cyanPulse")

        // Magenta Neon Halka Patlaması (Hafif gecikmeli)
        let magScale = CABasicAnimation(keyPath: "transform.scale")
        magScale.fromValue = 0.5
        magScale.toValue = 1.9
        magScale.duration = 0.5

        let magOpacity = CABasicAnimation(keyPath: "opacity")
        magOpacity.fromValue = 0.85
        magOpacity.toValue = 0.0
        magOpacity.duration = 0.5

        let magGroup = CAAnimationGroup()
        magGroup.animations = [magScale, magOpacity]
        magGroup.duration = 0.5
        magentaRingLayer.add(magGroup, forKey: "magentaPulse")

        // Canlı Başlık ve Açıklamanın Belirmesi
        let textFade = CABasicAnimation(keyPath: "opacity")
        textFade.fromValue = 0
        textFade.toValue = 1.0
        textFade.duration = 0.3
        textFade.fillMode = .forwards
        textFade.isRemovedOnCompletion = false
        titleTextLayer.add(textFade, forKey: "titleFade")
        subTextLayer.add(textFade, forKey: "subFade")
    }
}

// MARK: - Modern Zero-Margin Box (Prevents AppKit default title & margin offsets)
class ModernBox: NSBox {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.boxType = .custom
        self.titlePosition = .noTitle
        self.contentViewMargins = .zero
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.boxType = .custom
        self.titlePosition = .noTitle
        self.contentViewMargins = .zero
    }
}

// MARK: - Modern High-Contrast Styled Button (UI-md Specification)
class ModernButton: NSButton {
    var normalBgColor: NSColor = AliveLockTheme.surfaceHigh {
        didSet { updateLayerColors() }
    }
    var hoverBgColor: NSColor = AliveLockTheme.surfaceHover {
        didSet { updateLayerColors() }
    }
    var normalBorderColor: NSColor = AliveLockTheme.borderDefault {
        didSet { updateLayerColors() }
    }
    var hoverBorderColor: NSColor = AliveLockTheme.borderFocused {
        didSet { updateLayerColors() }
    }
    var customTextColor: NSColor = AliveLockTheme.textPrimary {
        didSet { updateStyledTitle() }
    }
    var customCornerRadius: CGFloat = AliveLockTheme.radiusMd {
        didSet { layer?.cornerRadius = customCornerRadius }
    }
    var textAlignment: NSTextAlignment = .center {
        didSet { updateStyledTitle() }
    }
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    override var title: String {
        didSet { updateStyledTitle() }
    }

    override var font: NSFont? {
        didSet { updateStyledTitle() }
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.45
            updateLayerColors()
        }
    }

    convenience init(
        frame: NSRect,
        title: String,
        symbolName: String? = nil,
        bgColor: NSColor = AliveLockTheme.surfaceHigh,
        hoverBgColor: NSColor = AliveLockTheme.surfaceHover,
        borderColor: NSColor = AliveLockTheme.borderDefault,
        hoverBorderColor: NSColor = AliveLockTheme.borderFocused,
        textColor: NSColor = AliveLockTheme.textPrimary,
        font: NSFont = NSFont.systemFont(ofSize: 13, weight: .semibold),
        cornerRadius: CGFloat = AliveLockTheme.radiusMd,
        alignment: NSTextAlignment = .center,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) {
        self.init(frame: frame)
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        if let btnCell = self.cell as? NSButtonCell {
            btnCell.highlightsBy = []
            btnCell.showsStateBy = []
            btnCell.backgroundColor = .clear
        }
        self.normalBgColor = bgColor
        self.hoverBgColor = hoverBgColor
        self.normalBorderColor = borderColor
        self.hoverBorderColor = hoverBorderColor
        self.customTextColor = textColor
        self.customCornerRadius = cornerRadius
        self.textAlignment = alignment
        self.font = font
        self.title = title
        self.target = target
        self.action = action

        if let sym = symbolName, let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: max(font.pointSize, 12), weight: .semibold)
            let configured = img.withSymbolConfiguration(conf) ?? img
            self.image = configured
            self.imagePosition = .imageLeading
            self.contentTintColor = textColor
        }

        self.layer?.cornerRadius = cornerRadius
        self.layer?.borderWidth = 1.0
        updateLayerColors()
        updateStyledTitle()
    }

    static func primary(frame: NSRect, title: String, symbolName: String? = nil, accentColor: NSColor = AliveLockTheme.accentCyan, target: AnyObject?, action: Selector?) -> ModernButton {
        return ModernButton(
            frame: frame,
            title: title,
            symbolName: symbolName,
            bgColor: accentColor.withAlphaComponent(0.24),
            hoverBgColor: accentColor.withAlphaComponent(0.38),
            borderColor: accentColor.withAlphaComponent(0.60),
            hoverBorderColor: accentColor.withAlphaComponent(0.95),
            textColor: .white,
            font: NSFont.systemFont(ofSize: 13, weight: .bold),
            cornerRadius: AliveLockTheme.radiusMd,
            target: target,
            action: action
        )
    }

    static func secondary(frame: NSRect, title: String, symbolName: String? = nil, target: AnyObject?, action: Selector?) -> ModernButton {
        return ModernButton(
            frame: frame,
            title: title,
            symbolName: symbolName,
            bgColor: AliveLockTheme.surfaceHigh,
            hoverBgColor: AliveLockTheme.surfaceHover,
            borderColor: AliveLockTheme.borderDefault,
            hoverBorderColor: AliveLockTheme.borderStrong,
            textColor: AliveLockTheme.textPrimary,
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            cornerRadius: AliveLockTheme.radiusMd,
            target: target,
            action: action
        )
    }

    static func danger(frame: NSRect, title: String, symbolName: String? = nil, target: AnyObject?, action: Selector?) -> ModernButton {
        return ModernButton(
            frame: frame,
            title: title,
            symbolName: symbolName,
            bgColor: AliveLockTheme.accentRed.withAlphaComponent(0.18),
            hoverBgColor: AliveLockTheme.accentRed.withAlphaComponent(0.32),
            borderColor: AliveLockTheme.accentRed.withAlphaComponent(0.50),
            hoverBorderColor: AliveLockTheme.accentRed.withAlphaComponent(0.85),
            textColor: AliveLockTheme.accentRed,
            font: NSFont.systemFont(ofSize: 12, weight: .bold),
            cornerRadius: AliveLockTheme.radiusSm,
            target: target,
            action: action
        )
    }

    func updateLayerColors() {
        self.layer?.backgroundColor = (isHovered ? hoverBgColor : normalBgColor).cgColor
        self.layer?.borderColor = (isHovered ? hoverBorderColor : normalBorderColor).cgColor
    }

    func updateStyledTitle() {
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = textAlignment
        pStyle.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: customTextColor,
            .font: self.font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .paragraphStyle: pStyle
        ]
        self.attributedTitle = NSAttributedString(string: self.title, attributes: attrs)
        self.contentTintColor = customTextColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateLayerColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateLayerColors()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Modern Sidebar Navigation Pill (Zero Text Clipping & High Contrast)
class SidebarNavButton: NSButton {
    var iconName: String = ""
    var itemTitle: String = ""
    var shortcutText: String = ""
    var isSelectedTab: Bool = false {
        didSet { updateAppearance() }
    }
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?
    private var iconView: NSImageView!
    private var titleLbl: NSTextField!
    private var shortcutBadge: NSTextField?
    private var activeIndicator: NSView!

    init(frame: NSRect, title: String, icon: String, shortcut: String, target: AnyObject?, action: Selector?) {
        super.init(frame: frame)
        self.itemTitle = title
        self.iconName = icon
        self.shortcutText = shortcut
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.title = ""

        if let btnCell = self.cell as? NSButtonCell {
            btnCell.highlightsBy = []
            btnCell.showsStateBy = []
            btnCell.backgroundColor = .clear
        }

        // Active indicator on left
        activeIndicator = NSView(frame: NSRect(x: 3, y: 9, width: 3, height: frame.height - 18))
        activeIndicator.wantsLayer = true
        activeIndicator.layer?.cornerRadius = 1.5
        activeIndicator.layer?.backgroundColor = AliveLockTheme.accentCyan.cgColor
        activeIndicator.isHidden = true
        addSubview(activeIndicator)

        // Icon
        iconView = NSImageView(frame: NSRect(x: 14, y: (frame.height - 18) / 2, width: 18, height: 18))
        addSubview(iconView)

        // Title
        titleLbl = NSTextField(labelWithString: title)
        titleLbl.frame = NSRect(x: 40, y: (frame.height - 18) / 2, width: frame.width - 82, height: 18)
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLbl.textColor = AliveLockTheme.textSecondary
        addSubview(titleLbl)

        // Shortcut badge on right
        if !shortcut.isEmpty {
            let badge = NSTextField(labelWithString: shortcut)
            badge.frame = NSRect(x: frame.width - 38, y: (frame.height - 18) / 2, width: 28, height: 18)
            badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            badge.alignment = .center
            badge.textColor = AliveLockTheme.textTertiary
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
            addSubview(badge)
            self.shortcutBadge = badge
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateAppearance() {
        if isSelectedTab {
            layer?.backgroundColor = AliveLockTheme.accentCyan.withAlphaComponent(0.16).cgColor
            layer?.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.35).cgColor
            layer?.borderWidth = 1.0
            activeIndicator.isHidden = false
            titleLbl.textColor = AliveLockTheme.accentCyan
            titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .bold)

            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
                iconView.image = img.withSymbolConfiguration(conf) ?? img
                iconView.contentTintColor = AliveLockTheme.accentCyan
            }
            shortcutBadge?.textColor = AliveLockTheme.accentCyan
            shortcutBadge?.layer?.backgroundColor = AliveLockTheme.accentCyan.withAlphaComponent(0.12).cgColor
        } else {
            layer?.backgroundColor = isHovered ? AliveLockTheme.surfaceHover.cgColor : NSColor.clear.cgColor
            layer?.borderColor = isHovered ? AliveLockTheme.borderSubtle.cgColor : NSColor.clear.cgColor
            layer?.borderWidth = 1.0
            activeIndicator.isHidden = true
            titleLbl.textColor = isHovered ? AliveLockTheme.textPrimary : AliveLockTheme.textSecondary
            titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)

            if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                iconView.image = img.withSymbolConfiguration(conf) ?? img
                iconView.contentTintColor = isHovered ? AliveLockTheme.textPrimary : AliveLockTheme.textSecondary
            }
            shortcutBadge?.textColor = AliveLockTheme.textTertiary
            shortcutBadge?.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Clickable Card Box (UI-md Tonal Elevation & Smooth Hover)
class ClickableCardBox: ModernBox {
    weak var target: AnyObject?
    var action: Selector?
    var normalFillColor: NSColor = AliveLockTheme.surfaceLow
    var hoverFillColor: NSColor = AliveLockTheme.surfaceHover
    var normalBorderColor: NSColor = AliveLockTheme.borderDefault
    var hoverBorderColor: NSColor = AliveLockTheme.borderFocused
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        fillColor = hoverFillColor
        borderColor = hoverBorderColor
    }

    override func mouseExited(with event: NSEvent) {
        fillColor = normalFillColor
        borderColor = normalBorderColor
    }

    override func mouseDown(with event: NSEvent) {
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Flipped View for Natural Vertical Scroll
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Dedicated Telegram Settings Window (Telegram Bildirim Ayarları)
class TelegramSettingsWindow: NSWindow {
    weak var appDelegate: AppDelegate?
    var enableCheckbox: NSButton!
    var tokenField: NSTextField!
    var chatIdField: NSTextField!
    var statusLabel: NSTextField!
    var testButton: ModernButton!
    var saveButton: ModernButton!

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let width: CGFloat = 520
        let height: CGFloat = 490
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let rect = NSRect(
            x: screenRect.midX - (width / 2),
            y: screenRect.midY - (height / 2),
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "AliveLock - Telegram Bildirim Ayarları"
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isReleasedWhenClosed = false

        setupUI(width: width, height: height)
    }

    private func setupUI(width: CGFloat, height: CGFloat) {
        guard let contentView = self.contentView else { return }

        // Frosted Glass Arka Plan
        let blurView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        let darkTint = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: height))
        darkTint.boxType = .custom
        darkTint.fillColor = AliveLockTheme.bgBase
        darkTint.borderWidth = 0
        darkTint.autoresizingMask = [.width, .height]
        contentView.addSubview(darkTint)

        // 1. Header Box
        let headerBox = NSBox(frame: NSRect(x: 20, y: height - 105, width: width - 40, height: 85))
        headerBox.boxType = .custom
        headerBox.fillColor = AliveLockTheme.surfaceLow
        headerBox.borderColor = AliveLockTheme.borderDefault
        headerBox.borderWidth = 1.0
        headerBox.cornerRadius = AliveLockTheme.radiusLg
        contentView.addSubview(headerBox)

        let iconBadge = NSBox(frame: NSRect(x: 16, y: 18, width: 48, height: 48))
        iconBadge.boxType = .custom
        iconBadge.fillColor = AliveLockTheme.accentCyan.withAlphaComponent(0.14)
        iconBadge.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.30)
        iconBadge.borderWidth = 1.0
        iconBadge.cornerRadius = AliveLockTheme.radiusMd
        headerBox.addSubview(iconBadge)

        let iconView = NSImageView(frame: NSRect(x: 10, y: 10, width: 28, height: 28))
        if let planeImg = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            iconView.image = planeImg.withSymbolConfiguration(conf) ?? planeImg
            iconView.contentTintColor = AliveLockTheme.accentCyan
        }
        iconBadge.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Telegram Anlık Bildirimleri")
        titleLabel.frame = NSRect(x: 74, y: 44, width: 380, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        headerBox.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Yetkisiz giriş veya hatalı şifrede çekilen fotoğraf anında iletilir.")
        subtitleLabel.frame = NSRect(x: 74, y: 22, width: 390, height: 18)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = AliveLockTheme.textSecondary
        headerBox.addSubview(subtitleLabel)

        // 2. Enable Checkbox
        enableCheckbox = NSButton(checkboxWithTitle: "Fotoğraflı Telegram bildirimlerini aktif et", target: self, action: nil)
        enableCheckbox.frame = NSRect(x: 24, y: height - 145, width: 420, height: 24)
        enableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        enableCheckbox.state = (appDelegate?.telegramEnabled == true) ? .on : .off
        contentView.addSubview(enableCheckbox)

        // 3. Bot Token Field
        let tokenLabel = NSTextField(labelWithString: "Telegram Bot Token:")
        tokenLabel.frame = NSRect(x: 24, y: height - 180, width: 300, height: 18)
        tokenLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        tokenLabel.textColor = AliveLockTheme.textPrimary
        contentView.addSubview(tokenLabel)

        tokenField = NSTextField(frame: NSRect(x: 24, y: height - 215, width: width - 48, height: 32))
        tokenField.placeholderString = "Örn: 123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tokenField.stringValue = appDelegate?.telegramBotToken ?? ""
        tokenField.backgroundColor = AliveLockTheme.surfaceLowest
        tokenField.textColor = AliveLockTheme.textPrimary
        tokenField.wantsLayer = true
        tokenField.layer?.cornerRadius = 8
        tokenField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        tokenField.layer?.borderWidth = 1.0
        contentView.addSubview(tokenField)

        let tokenHint = NSTextField(labelWithString: "💡 Telegram'da @BotFather ile ücretsiz bir bot açıp tokeninizi alın.")
        tokenHint.frame = NSRect(x: 24, y: height - 238, width: width - 48, height: 16)
        tokenHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        tokenHint.textColor = AliveLockTheme.textSecondary
        contentView.addSubview(tokenHint)

        // 4. Chat ID Field
        let chatLabel = NSTextField(labelWithString: "Telegram Chat ID:")
        chatLabel.frame = NSRect(x: 24, y: height - 272, width: 300, height: 18)
        chatLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        chatLabel.textColor = AliveLockTheme.textPrimary
        contentView.addSubview(chatLabel)

        chatIdField = NSTextField(frame: NSRect(x: 24, y: height - 307, width: width - 48, height: 32))
        chatIdField.placeholderString = "Örn: 987654321"
        chatIdField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        chatIdField.stringValue = appDelegate?.telegramChatId ?? ""
        chatIdField.backgroundColor = AliveLockTheme.surfaceLowest
        chatIdField.textColor = AliveLockTheme.textPrimary
        chatIdField.wantsLayer = true
        chatIdField.layer?.cornerRadius = 8
        chatIdField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        chatIdField.layer?.borderWidth = 1.0
        contentView.addSubview(chatIdField)

        let chatHint = NSTextField(labelWithString: "💡 Botunuza /start yazıp @userinfobot botundan kendi ID'nizi öğrenebilirsiniz.")
        chatHint.frame = NSRect(x: 24, y: height - 330, width: width - 48, height: 16)
        chatHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        chatHint.textColor = AliveLockTheme.textSecondary
        contentView.addSubview(chatHint)

        // 5. Status Feedback Label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 24, y: 72, width: width - 48, height: 26)
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)

        // 6. Action Buttons
        testButton = ModernButton.secondary(
            frame: NSRect(x: 24, y: 22, width: 210, height: 38),
            title: "🧪 Test Bildirimi Gönder",
            symbolName: nil,
            target: self,
            action: #selector(handleSendTest)
        )
        contentView.addSubview(testButton)

        saveButton = ModernButton.primary(
            frame: NSRect(x: width - 180, y: 22, width: 156, height: 38),
            title: "💾 Ayarları Kaydet",
            symbolName: nil,
            accentColor: AliveLockTheme.accentCyan,
            target: self,
            action: #selector(handleSaveTelegramSettings)
        )
        contentView.addSubview(saveButton)
    }

    @objc func handleSendTest() {
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatId = chatIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty, !chatId.isEmpty else {
            statusLabel.textColor = AliveLockTheme.accentRed
            statusLabel.stringValue = "⚠️ Lütfen önce Bot Token ve Chat ID alanlarını doldurunuz."
            return
        }

        statusLabel.textColor = AliveLockTheme.accentCyan
        statusLabel.stringValue = "✈️ Fotoğraflı test bildirimi Telegram'a gönderiliyor..."
        testButton.isEnabled = false

        var testPhotoData: Data? = nil
        if let appDelegate = appDelegate {
            let artworkPath = "\(appDelegate.projectDir)/assets/LockArtwork.png"
            testPhotoData = try? Data(contentsOf: URL(fileURLWithPath: artworkPath))
        }

        TelegramNotifier.shared.sendAlert(
            photoData: testPhotoData,
            appName: "AliveLock (Test)",
            reason: "🧪 Telegram Entegrasyon & Fotoğraf Testi",
            token: token,
            chatId: chatId
        ) { [weak self] success, message in
            guard let self = self else { return }
            self.testButton.isEnabled = true
            if success {
                self.enableCheckbox.state = .on
                self.statusLabel.textColor = AliveLockTheme.accentEmerald
                self.statusLabel.stringValue = "✅ Harika! Fotoğraflı test bildirimi Telegram'a başarıyla iletildi."
            } else {
                self.statusLabel.textColor = AliveLockTheme.accentRed
                self.statusLabel.stringValue = "❌ Hata: \(message)"
            }
        }
    }

    @objc func handleSaveTelegramSettings() {
        guard let appDelegate = appDelegate else { return }
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatId = chatIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        appDelegate.telegramBotToken = token
        appDelegate.telegramChatId = chatId
        if !token.isEmpty && !chatId.isEmpty {
            appDelegate.telegramEnabled = true
            enableCheckbox.state = .on
        } else {
            appDelegate.telegramEnabled = (enableCheckbox.state == .on)
        }
        appDelegate.saveConfig()

        statusLabel.textColor = AliveLockTheme.accentEmerald
        statusLabel.stringValue = "💾 Fotoğraflı Telegram bildirimleri aktif edildi ve kaydedildi!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.orderOut(nil)
        }
    }
}

// MARK: - Dedicated Locked Apps Manager Window (Kilitlenecek Uygulamalar Yöneticisi)
class LockedAppsManagerWindow: NSWindow {
    weak var appDelegate: AppDelegate?
    var countBadge: NSTextField!
    var scrollView: NSScrollView!
    var listContainer: FlippedView!
    var runningAppsPopUp: NSPopUpButton!

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let width: CGFloat = 540
        let height: CGFloat = 620
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let rect = NSRect(
            x: screenRect.midX - (width / 2),
            y: screenRect.midY - (height / 2),
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "AliveLock - Kilitlenecek Uygulamalar"
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isReleasedWhenClosed = false

        setupUI(width: width, height: height)
    }

    private func setupUI(width: CGFloat, height: CGFloat) {
        guard let contentView = self.contentView else { return }

        // Modern Frosted Glass Arka Plan
        let blurView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        let darkTint = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: height))
        darkTint.boxType = .custom
        darkTint.fillColor = AliveLockTheme.bgBase
        darkTint.borderWidth = 0
        darkTint.autoresizingMask = [.width, .height]
        contentView.addSubview(darkTint)

        // 1. Header Area
        let headerBox = NSBox(frame: NSRect(x: 20, y: height - 105, width: width - 40, height: 85))
        headerBox.boxType = .custom
        headerBox.fillColor = AliveLockTheme.surfaceLow
        headerBox.borderColor = AliveLockTheme.borderDefault
        headerBox.borderWidth = 1.0
        headerBox.cornerRadius = AliveLockTheme.radiusLg
        contentView.addSubview(headerBox)

        let iconBadge = NSBox(frame: NSRect(x: 16, y: 18, width: 48, height: 48))
        iconBadge.boxType = .custom
        iconBadge.fillColor = AliveLockTheme.accentPurple.withAlphaComponent(0.15)
        iconBadge.borderColor = AliveLockTheme.accentPurple.withAlphaComponent(0.30)
        iconBadge.borderWidth = 1.0
        iconBadge.cornerRadius = AliveLockTheme.radiusMd
        headerBox.addSubview(iconBadge)

        let iconView = NSImageView(frame: NSRect(x: 10, y: 10, width: 28, height: 28))
        if let stackImg = NSImage(systemSymbolName: "lock.square.stack.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            iconView.image = stackImg.withSymbolConfiguration(conf) ?? stackImg
            iconView.contentTintColor = AliveLockTheme.accentPurple
        }
        iconBadge.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Kilitlenecek Uygulamalar")
        titleLabel.frame = NSRect(x: 74, y: 44, width: 270, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        headerBox.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Korunuyor modunda şifre/Touch ID ile kilitlenecek uygulamalar.")
        subtitleLabel.frame = NSRect(x: 74, y: 22, width: 390, height: 18)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = AliveLockTheme.textSecondary
        headerBox.addSubview(subtitleLabel)

        countBadge = NSTextField(labelWithString: "0 Uygulama")
        countBadge.frame = NSRect(x: headerBox.frame.width - 150, y: 46, width: 135, height: 22)
        countBadge.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        countBadge.alignment = .right
        countBadge.textColor = AliveLockTheme.accentPurple
        headerBox.addSubview(countBadge)

        // 2. Action Buttons (Finder'dan Ekle & Açık Uygulamalardan Ekle)
        let addFinderBtn = ModernButton.primary(
            frame: NSRect(x: 20, y: height - 158, width: 245, height: 38),
            title: " Finder'dan Ekle (.app)",
            symbolName: "plus.app.fill",
            accentColor: AliveLockTheme.accentPurple,
            target: self,
            action: #selector(handleSelectAppFromFinder)
        )
        contentView.addSubview(addFinderBtn)

        runningAppsPopUp = NSPopUpButton(frame: NSRect(x: 275, y: height - 158, width: 245, height: 38), pullsDown: true)
        runningAppsPopUp.bezelStyle = .rounded
        runningAppsPopUp.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(runningAppsPopUp)

        // 3. Scrollable List of Apps
        let scrollY: CGFloat = 65
        let scrollHeight = height - 170 - scrollY
        scrollView = NSScrollView(frame: NSRect(x: 20, y: scrollY, width: width - 40, height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = AliveLockTheme.radiusMd
        scrollView.backgroundColor = AliveLockTheme.surfaceLowest
        scrollView.drawsBackground = true

        listContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollHeight))
        scrollView.documentView = listContainer
        contentView.addSubview(scrollView)

        // 4. Footer info & Close Button
        let hintLabel = NSTextField(labelWithString: "💡 Listeye eklenen her uygulama, Korunuyor modunda açıldığında kilitlenir.")
        hintLabel.frame = NSRect(x: 20, y: 22, width: 380, height: 20)
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = AliveLockTheme.textSecondary
        contentView.addSubview(hintLabel)

        let closeBtn = ModernButton.secondary(
            frame: NSRect(x: width - 115, y: 16, width: 95, height: 32),
            title: "Tamam",
            symbolName: nil,
            target: self,
            action: #selector(handleManagerClose)
        )
        contentView.addSubview(closeBtn)
    }

    func reloadRunningAppsMenu() {
        runningAppsPopUp.removeAllItems()
        let topItem = NSMenuItem(title: " Açık Uygulamalardan Ekle ▾", action: nil, keyEquivalent: "")
        if let boltImg = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            topItem.image = boltImg.withSymbolConfiguration(conf) ?? boltImg
        }
        runningAppsPopUp.menu?.addItem(topItem)

        let currentLockedBundleIds = Set(appDelegate?.targetApps.map { $0.bundleId.lowercased() } ?? [])
        let currentLockedProcesses = Set(appDelegate?.targetApps.map { $0.processName.lowercased() } ?? [])

        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        if running.isEmpty {
            let emptyItem = NSMenuItem(title: "Açık uygulama bulunamadı", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            runningAppsPopUp.menu?.addItem(emptyItem)
            return
        }

        for app in running {
            let bId = (app.bundleIdentifier ?? "").lowercased()
            let pName = (app.localizedName ?? "").lowercased()
            if !currentLockedBundleIds.contains(bId) && !currentLockedProcesses.contains(pName) {
                let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? "Uygulama"
                let item = NSMenuItem(title: "➕ \(name)", action: #selector(handleRunningAppMenuItemSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app
                if let icon = app.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                runningAppsPopUp.menu?.addItem(item)
            }
        }
    }

    @objc func handleRunningAppMenuItemSelected(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        let bundleId = app.bundleIdentifier ?? ""
        let execName = app.executableURL?.lastPathComponent ?? app.localizedName ?? ""
        let displayName = app.localizedName ?? execName

        guard let appDel = appDelegate else { return }
        if appDel.targetApps.contains(where: {
            (!bundleId.isEmpty && $0.bundleId.lowercased() == bundleId.lowercased()) ||
            $0.processName.lowercased() == execName.lowercased()
        }) {
            return
        }

        appDel.targetApps.append(TargetAppConfig(processName: execName, bundleId: bundleId, displayName: displayName))
        appDel.saveConfig()
        refreshList()

        if appDel.isProtectedMode() {
            appDel.enforceProtectionOnRunningApps()
        }
    }

    @objc func handleSelectAppFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Kilitlenecek Uygulamayı Seçin"
        panel.prompt = "Kilit Listesine Ekle"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self = self else { return }
            for url in panel.urls {
                self.addAppFromURL(url)
            }
        }
    }

    func addAppFromURL(_ url: URL) {
        guard let bundle = Bundle(url: url) else { return }
        let bundleId = bundle.bundleIdentifier ?? ""
        let execName = bundle.executableURL?.lastPathComponent ?? url.deletingPathExtension().lastPathComponent
        let displayName = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")

        guard let appDel = appDelegate else { return }

        if appDel.targetApps.contains(where: {
            (!bundleId.isEmpty && $0.bundleId.lowercased() == bundleId.lowercased()) ||
            $0.processName.lowercased() == execName.lowercased()
        }) {
            return
        }

        appDel.targetApps.append(TargetAppConfig(processName: execName, bundleId: bundleId, displayName: displayName))
        appDel.saveConfig()
        refreshList()

        if appDel.isProtectedMode() {
            appDel.enforceProtectionOnRunningApps()
        }
    }

    @objc func handleRemoveApp(_ sender: NSButton) {
        let index = sender.tag
        guard let appDel = appDelegate, index >= 0 && index < appDel.targetApps.count else { return }
        _ = appDel.targetApps.remove(at: index)
        appDel.saveConfig()
        refreshList()
    }

    func refreshList() {
        reloadRunningAppsMenu()
        guard let appDel = appDelegate else { return }
        countBadge.stringValue = "\(appDel.targetApps.count) Uygulama Kilitli"

        for sub in listContainer.subviews {
            sub.removeFromSuperview()
        }

        let rowHeight: CGFloat = 54
        let spacing: CGFloat = 8
        let totalHeight = max(CGFloat(appDel.targetApps.count) * (rowHeight + spacing) + 20, scrollView.contentSize.height)
        listContainer.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: totalHeight)

        if appDel.targetApps.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "Henüz kilitli bir uygulama eklenmedi. Yukarıdaki butonları kullanarak uygulama ekleyebilirsiniz.")
            emptyLabel.frame = NSRect(x: 20, y: 80, width: scrollView.contentSize.width - 40, height: 60)
            emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            emptyLabel.alignment = .center
            emptyLabel.textColor = AliveLockTheme.textSecondary
            listContainer.addSubview(emptyLabel)
            return
        }

        for (index, target) in appDel.targetApps.enumerated() {
            let y = CGFloat(index) * (rowHeight + spacing) + 8
            let rowBox = NSBox(frame: NSRect(x: 8, y: y, width: scrollView.contentSize.width - 16, height: rowHeight))
            rowBox.boxType = .custom
            rowBox.fillColor = AliveLockTheme.surfaceLow
            rowBox.borderColor = AliveLockTheme.borderSubtle
            rowBox.borderWidth = 1.0
            rowBox.cornerRadius = AliveLockTheme.radiusMd
            listContainer.addSubview(rowBox)

            // App Icon
            let iconView = NSImageView(frame: NSRect(x: 10, y: 9, width: 36, height: 36))
            var icon: NSImage?
            if !target.bundleId.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else if let path = NSWorkspace.shared.fullPath(forApplication: target.processName) {
                icon = NSWorkspace.shared.icon(forFile: path)
            }
            if icon == nil {
                icon = NSImage(systemSymbolName: "app.badge.checkmark", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            }
            iconView.image = icon
            rowBox.addSubview(iconView)

            // App Name
            let nameLabel = NSTextField(labelWithString: target.displayName)
            nameLabel.frame = NSRect(x: 56, y: 26, width: rowBox.frame.width - 160, height: 20)
            nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            nameLabel.textColor = AliveLockTheme.textPrimary
            rowBox.addSubview(nameLabel)

            // Subtitle
            let subText = target.bundleId.isEmpty ? target.processName : target.bundleId
            let subLabel = NSTextField(labelWithString: subText)
            subLabel.frame = NSRect(x: 56, y: 8, width: rowBox.frame.width - 160, height: 16)
            subLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            subLabel.textColor = AliveLockTheme.textSecondary
            rowBox.addSubview(subLabel)

            // Remove button
            let removeBtn = ModernButton.danger(
                frame: NSRect(x: rowBox.frame.width - 92, y: 12, width: 82, height: 30),
                title: "🗑️ Kaldır",
                symbolName: nil,
                target: self,
                action: #selector(handleRemoveApp(_:))
            )
            removeBtn.tag = index
            rowBox.addSubview(removeBtn)
        }
    }

    @objc func handleManagerClose() {
        self.orderOut(nil)
    }
}

// MARK: - Dedicated Privacy Curtain Window (.floating Level: 3)
class PrivacyCurtainWindow: NSWindow {
    var cardBox: ModernBox!
    var titleLabel: NSTextField!
    var subLabel: NSTextField!
    var iconView: NSImageView!
    var passwordField: NSSecureTextField!
    var unlockButton: ModernButton!
    var touchIDButton: ModernButton!
    var cancelButton: ModernButton!
    var feedbackLabel: NSTextField!

    var currentAppName: String = "Uygulama"
    var onSuccess: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            handleCancel()
            return
        }
        super.keyDown(with: event)
    }

    init(screenRect: NSRect) {
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.appearance = NSAppearance(named: .darkAqua)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        let root = NSView(frame: screenRect)
        self.contentView = root

        // Modern Buzlu Cam (Frosted Glass) Arka Plan
        let blurView = NSVisualEffectView(frame: screenRect)
        blurView.material = .fullScreenUI
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        root.addSubview(blurView)

        let darkOverlay = ModernBox(frame: screenRect)
        darkOverlay.fillColor = AliveLockTheme.bgBase
        darkOverlay.borderWidth = 0
        darkOverlay.autoresizingMask = [.width, .height]
        root.addSubview(darkOverlay)

        let boxWidth: CGFloat = 460
        let boxHeight: CGFloat = 425
        let boxX = (screenRect.width - boxWidth) / 2
        let boxY = (screenRect.height - boxHeight) / 2

        cardBox = ModernBox(frame: NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight))
        cardBox.fillColor = AliveLockTheme.surfaceLow
        cardBox.borderColor = AliveLockTheme.borderStrong
        cardBox.borderWidth = 1.0
        cardBox.cornerRadius = AliveLockTheme.radiusXl
        root.addSubview(cardBox)

        iconView = NSImageView(frame: NSRect(x: (boxWidth - 56) / 2, y: boxHeight - 74, width: 56, height: 56))
        if let lockImg = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
            let configured = lockImg.withSymbolConfiguration(config) ?? lockImg
            iconView.image = configured
            iconView.contentTintColor = AliveLockTheme.accentCyan
        }
        cardBox.addSubview(iconView)

        titleLabel = NSTextField(labelWithString: "Uygulama Kilitli")
        titleLabel.frame = NSRect(x: 20, y: boxHeight - 110, width: boxWidth - 40, height: 26)
        titleLabel.font = NSFont.systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        titleLabel.alignment = .center
        cardBox.addSubview(titleLabel)

        subLabel = NSTextField(labelWithString: "Açmak için Touch ID okutun veya parolanızı girin:")
        subLabel.frame = NSRect(x: 20, y: boxHeight - 134, width: boxWidth - 40, height: 18)
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = AliveLockTheme.textSecondary
        subLabel.alignment = .center
        cardBox.addSubview(subLabel)

        touchIDButton = ModernButton.primary(
            frame: NSRect(x: 40, y: boxHeight - 190, width: boxWidth - 80, height: 42),
            title: "  Touch ID ile Kilidi Aç",
            symbolName: "touchid",
            accentColor: AliveLockTheme.accentCyan,
            target: self,
            action: #selector(triggerTouchID)
        )
        cardBox.addSubview(touchIDButton)

        let orLabel = NSTextField(labelWithString: "─────── VEYA PAROLA GİRİN ───────")
        orLabel.frame = NSRect(x: 40, y: boxHeight - 224, width: boxWidth - 80, height: 18)
        orLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        orLabel.textColor = AliveLockTheme.textTertiary
        orLabel.alignment = .center
        cardBox.addSubview(orLabel)

        passwordField = NSSecureTextField(frame: NSRect(x: 40, y: boxHeight - 272, width: boxWidth - 80, height: 38))
        passwordField.placeholderString = "Mac parolanızı girin..."
        passwordField.font = NSFont.systemFont(ofSize: 14)
        passwordField.focusRingType = .none
        passwordField.backgroundColor = AliveLockTheme.surfaceLowest
        passwordField.textColor = AliveLockTheme.textPrimary
        passwordField.isBordered = true
        passwordField.wantsLayer = true
        passwordField.layer?.cornerRadius = 8
        passwordField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        passwordField.layer?.borderWidth = 1.0
        passwordField.target = self
        passwordField.action = #selector(handlePasswordSubmit)
        cardBox.addSubview(passwordField)

        unlockButton = ModernButton.primary(
            frame: NSRect(x: 40, y: boxHeight - 324, width: 235, height: 38),
            title: "  Kilidi Aç (↵)",
            symbolName: "lock.open.fill",
            accentColor: AliveLockTheme.accentEmerald,
            target: self,
            action: #selector(handlePasswordSubmit)
        )
        unlockButton.keyEquivalent = "\r"
        cardBox.addSubview(unlockButton)

        cancelButton = ModernButton.secondary(
            frame: NSRect(x: 285, y: boxHeight - 324, width: 135, height: 38),
            title: "İptal [ESC]",
            symbolName: nil,
            target: self,
            action: #selector(handleCancel)
        )
        cardBox.addSubview(cancelButton)

        feedbackLabel = NSTextField(labelWithString: "")
        feedbackLabel.frame = NSRect(x: 20, y: boxHeight - 368, width: boxWidth - 40, height: 24)
        feedbackLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        feedbackLabel.alignment = .center
        cardBox.addSubview(feedbackLabel)

        let hintLabel = NSTextField(labelWithString: "⚠️ Hatalı parola veya yetkisiz parmak izinde anında fotoğraf kaydedilir.")
        hintLabel.frame = NSRect(x: 20, y: 14, width: boxWidth - 40, height: 16)
        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = AliveLockTheme.textSecondary
        hintLabel.alignment = .center
        cardBox.addSubview(hintLabel)
    }

    func shakeCard() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.45
        animation.values = [-14, 14, -10, 10, -6, 6, -2, 2, 0]
        cardBox.layer?.add(animation, forKey: "shake")
    }

    func showBiometricFailure() {
        feedbackLabel.textColor = AliveLockTheme.accentRed
        feedbackLabel.stringValue = "❌ Tanınmayan parmak izi! Fotoğraf kaydedildi."
        shakeCard()
    }

    func present(appName: String, onSuccess: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.currentAppName = appName
        self.onSuccess = onSuccess
        self.onCancel = onCancel

        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        self.setFrame(screenRect, display: true)

        let boxWidth: CGFloat = 460
        let boxHeight: CGFloat = 420
        let boxX = (screenRect.width - boxWidth) / 2
        let boxY = (screenRect.height - boxHeight) / 2
        cardBox.frame = NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)

        titleLabel.stringValue = "🔒 \(appName) Kilitli"
        passwordField.stringValue = ""
        feedbackLabel.stringValue = ""

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.makeFirstResponder(passwordField)

        triggerTouchID()
    }

    @objc func triggerTouchID() {
        let context = LAContext()
        context.localizedCancelTitle = "Parola Kullan"
        let reason = "AliveLock: \(currentAppName) kilidini açmak için parmak izinizi okutun:"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    self.feedbackLabel.textColor = AliveLockTheme.accentEmerald
                    self.feedbackLabel.stringValue = "✅ Doğrulandı! Açılıyor..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.orderOut(nil)
                        self.onSuccess?()
                    }
                } else {
                    if let err = authError as? LAError, err.code == .userCancel || err.code == .userFallback {
                        self.makeFirstResponder(self.passwordField)
                        return
                    }
                    if let appDel = NSApp.delegate as? AppDelegate, appDel.isWrongCredentialsError(authError) {
                        IntruderCamera.shared.captureIntruderPhoto(appName: self.currentAppName)
                        self.showBiometricFailure()
                    }
                }
            }
        }
    }

    @objc func handlePasswordSubmit() {
        let enteredPassword = passwordField.stringValue
        guard !enteredPassword.isEmpty else {
            feedbackLabel.textColor = AliveLockTheme.accentAmber
            feedbackLabel.stringValue = "⚠️ Lütfen parolanızı giriniz."
            shakeCard()
            return
        }

        feedbackLabel.textColor = AliveLockTheme.accentCyan
        feedbackLabel.stringValue = "Doğrulanıyor..."
        unlockButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let isValid = verifyUserPassword(enteredPassword)

            DispatchQueue.main.async {
                self.unlockButton.isEnabled = true
                if isValid {
                    self.feedbackLabel.textColor = AliveLockTheme.accentEmerald
                    self.feedbackLabel.stringValue = "✅ Parola doğru! Açılıyor..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.passwordField.stringValue = ""
                        self.orderOut(nil)
                        self.onSuccess?()
                    }
                } else {
                    IntruderCamera.shared.captureIntruderPhoto(appName: self.currentAppName)
                    self.feedbackLabel.textColor = AliveLockTheme.accentRed
                    self.feedbackLabel.stringValue = "❌ Hatalı parola! Fotoğraf kaydedildi."
                    self.passwordField.stringValue = ""
                    self.shakeCard()
                }
            }
        }
    }

    @objc func handleCancel() {
        self.passwordField.stringValue = ""
        self.orderOut(nil)
        self.onCancel?()
    }
}

// MARK: - Photo Preview Modal Window
class PhotoPreviewWindow: NSWindow {
    init(image: NSImage, title: String) {
        let width: CGFloat = 800
        let height: CGFloat = 600
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let rect = NSRect(
            x: screenRect.midX - (width / 2),
            y: screenRect.midY - (height / 2),
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "AliveLock Güvenlik Kaydı: \(title)"
        self.level = .floating
        self.backgroundColor = AliveLockTheme.bgBase

        let imgView = NSImageView(frame: NSRect(x: 20, y: 20, width: width - 40, height: height - 60))
        imgView.image = image
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(imgView)
    }
}

// MARK: - Master AliveLock Dashboard Window (Genel Bakış, Kilitli Uygulamalar & Galeri)
class AliveLockDashboardWindow: NSWindow {
    weak var appDelegate: AppDelegate?

    var sidebarView: NSView!
    var contentContainer: NSView!
    var navButtons: [SidebarNavButton] = []
    var currentTab: Int = 0

    // Tab Views
    var overviewView: NSView!
    var appsGridView: NSView!
    var galleryView: NSView!
    var settingsView: NSView!

    // Overview components
    var overviewStatusBadgeLabel: NSTextField!
    var overviewStatusDot: NSView!
    var overviewLockToggleBtn: ModernButton!
    var overviewHeroActionBtn: ModernButton!
    var overviewHeroStatusLabel: NSTextField!
    var heroBox: NSBox!
    var aliCard: ClickableCardBox!
    var protectCard: ClickableCardBox!
    var appsCard: NSBox!

    // Apps Grid components
    var searchField: NSSearchField!
    var filterSegment: NSSegmentedControl!
    var appsGridContainer: FlippedView!
    var appsScrollView: NSScrollView!
    var allAppItems: [(displayName: String, processName: String, bundleId: String, icon: NSImage?)] = []

    // Gallery components
    var galleryGridContainer: FlippedView!
    var galleryScrollView: NSScrollView!
    var galleryCountLabel: NSTextField!

    // Settings components
    var tokenField: NSTextField!
    var chatIdField: NSTextField!
    var enableCheckbox: NSButton!
    var settingsStatusLabel: NSTextField!
    var testBtn: ModernButton!
    var saveBtn: ModernButton!

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters {
            if chars == "1" {
                appDelegate?.handleAliMode()
                return
            } else if chars == "2" {
                appDelegate?.handleProtectMode()
                return
            } else if chars == "3" {
                switchTab(to: 1) // Kilitli Uygulamalar
                return
            } else if chars == "4" {
                switchTab(to: 2) // Galeri
                return
            } else if chars == "5" {
                switchTab(to: 3) // Ayarlar
                return
            }
        }
        if event.keyCode == 53 { // ESC
            self.orderOut(nil)
            return
        }
        super.keyDown(with: event)
    }

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let width: CGFloat = 1060
        let height: CGFloat = 680
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1440, height: 900)
        let rect = NSRect(
            x: screenRect.midX - (width / 2),
            y: screenRect.midY - (height / 2),
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.title = ""
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isReleasedWhenClosed = false
        self.level = .floating

        setupUI(width: width, height: height)
    }

    private func setupUI(width: CGFloat, height: CGFloat) {
        guard let contentView = self.contentView else { return }

        // Frosted Glass Window Backdrop
        let blurView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        let darkTint = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: height))
        darkTint.boxType = .custom
        darkTint.fillColor = AliveLockTheme.bgBase
        darkTint.borderWidth = 0
        darkTint.autoresizingMask = [.width, .height]
        contentView.addSubview(darkTint)

        // 1. Sidebar (Width: 220)
        let sidebarWidth: CGFloat = 220
        sidebarView = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: height))
        contentView.addSubview(sidebarView)

        let sidebarDivider = NSBox(frame: NSRect(x: sidebarWidth - 1, y: 0, width: 1, height: height))
        sidebarDivider.boxType = .custom
        sidebarDivider.fillColor = AliveLockTheme.borderSubtle
        sidebarDivider.borderWidth = 0
        contentView.addSubview(sidebarDivider)

        setupSidebar(width: sidebarWidth, height: height)

        // 2. Content Container (Width: width - 220)
        let contentX = sidebarWidth
        let contentWidth = width - contentX
        contentContainer = NSView(frame: NSRect(x: contentX, y: 0, width: contentWidth, height: height))
        contentView.addSubview(contentContainer)

        buildOverviewView(width: contentWidth, height: height)
        buildAppsGridView(width: contentWidth, height: height)
        buildGalleryView(width: contentWidth, height: height)
        buildSettingsView(width: contentWidth, height: height)

        switchTab(to: 0)
        updateStatus()
    }

    // MARK: - Sidebar Setup
    private func setupSidebar(width: CGFloat, height: CGFloat) {
        // App Logo & Brand Header
        let logoView = NSImageView(frame: NSRect(x: 18, y: height - 76, width: 36, height: 36))
        if let artImg = NSImage(contentsOfFile: "\(appDelegate?.projectDir ?? "")/assets/LockArtwork.png") ??
                         NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
            logoView.image = artImg
            logoView.wantsLayer = true
            logoView.layer?.cornerRadius = 9
            logoView.layer?.masksToBounds = true
            logoView.layer?.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.35).cgColor
            logoView.layer?.borderWidth = 1.0
        }
        sidebarView.addSubview(logoView)

        let brandLabel = NSTextField(labelWithString: "AliveLock")
        brandLabel.frame = NSRect(x: 62, y: height - 68, width: 140, height: 22)
        brandLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        brandLabel.textColor = AliveLockTheme.textPrimary
        sidebarView.addSubview(brandLabel)

        let brandSubLabel = NSTextField(labelWithString: "Güvenlik & Kilit")
        brandSubLabel.frame = NSRect(x: 63, y: height - 85, width: 140, height: 16)
        brandSubLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        brandSubLabel.textColor = AliveLockTheme.textSecondary
        sidebarView.addSubview(brandSubLabel)

        // Navigation Items
        let items = [
            ("Genel Bakış", "rectangle.grid.2x2.fill", "⌘ 1"),
            ("Kilitli Uygulamalar", "lock.square.stack.fill", "⌘ 2"),
            ("Güvenlik Günlükleri", "photo.stack.fill", "⌘ 3"),
            ("Telegram & Ayarlar", "paperplane.fill", "⌘ 4")
        ]

        var startY: CGFloat = height - 140
        for (index, item) in items.enumerated() {
            let btn = SidebarNavButton(
                frame: NSRect(x: 14, y: startY, width: width - 28, height: 42),
                title: item.0,
                icon: item.1,
                shortcut: item.2,
                target: self,
                action: #selector(handleNavClicked(_:))
            )
            btn.tag = index
            sidebarView.addSubview(btn)
            navButtons.append(btn)
            startY -= 48
        }

        // Bottom User Profile Pill
        let profileBox = NSBox(frame: NSRect(x: 14, y: 18, width: width - 28, height: 60))
        profileBox.boxType = .custom
        profileBox.fillColor = AliveLockTheme.surfaceLow
        profileBox.borderColor = AliveLockTheme.borderSubtle
        profileBox.borderWidth = 1.0
        profileBox.cornerRadius = AliveLockTheme.radiusLg
        sidebarView.addSubview(profileBox)

        let avatarView = NSImageView(frame: NSRect(x: 12, y: 14, width: 32, height: 32))
        if let userImg = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
            avatarView.image = userImg.withSymbolConfiguration(conf) ?? userImg
            avatarView.contentTintColor = AliveLockTheme.textSecondary
        }
        profileBox.addSubview(avatarView)

        let userName = NSFullUserName().isEmpty ? "Yönetici" : NSFullUserName()
        let nameLabel = NSTextField(labelWithString: "\(userName) (Admin)")
        nameLabel.frame = NSRect(x: 50, y: 30, width: 110, height: 18)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        nameLabel.textColor = AliveLockTheme.textPrimary
        profileBox.addSubview(nameLabel)

        let roleLabel = NSTextField(labelWithString: "Tam Yetki • Ana Profil")
        roleLabel.frame = NSRect(x: 50, y: 14, width: 110, height: 16)
        roleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        roleLabel.textColor = AliveLockTheme.textSecondary
        profileBox.addSubview(roleLabel)

        let statusDot = NSView(frame: NSRect(x: profileBox.frame.width - 20, y: 26, width: 8, height: 8))
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = AliveLockTheme.accentEmerald.cgColor
        profileBox.addSubview(statusDot)
    }

    @objc func handleNavClicked(_ sender: NSButton) {
        switchTab(to: sender.tag)
    }

    func switchTab(to index: Int) {
        currentTab = index
        for (i, btn) in navButtons.enumerated() {
            btn.isSelectedTab = (i == index)
        }

        overviewView.isHidden = (index != 0)
        appsGridView.isHidden = (index != 1)
        galleryView.isHidden = (index != 2)
        settingsView.isHidden = (index != 3)

        if index == 1 {
            refreshAppsGrid()
        } else if index == 2 {
            refreshGallery()
        }
    }

    // MARK: - Tab 0: Overview (Genel Bakış)
    private func buildOverviewView(width: CGFloat, height: CGFloat) {
        overviewView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentContainer.addSubview(overviewView)

        // Top Header
        let titleLabel = NSTextField(labelWithString: "Genel Bakış")
        titleLabel.frame = NSRect(x: 28, y: height - 60, width: 160, height: 32)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        overviewView.addSubview(titleLabel)

        let statusPill = NSBox(frame: NSRect(x: 185, y: height - 58, width: 295, height: 28))
        statusPill.boxType = .custom
        statusPill.fillColor = AliveLockTheme.surfaceLowest
        statusPill.borderColor = AliveLockTheme.borderDefault
        statusPill.borderWidth = 1.0
        statusPill.cornerRadius = 14
        overviewView.addSubview(statusPill)

        overviewStatusDot = NSView(frame: NSRect(x: 10, y: 9, width: 10, height: 10))
        overviewStatusDot.wantsLayer = true
        overviewStatusDot.layer?.cornerRadius = 5
        overviewStatusDot.layer?.backgroundColor = AliveLockTheme.accentEmerald.cgColor
        statusPill.addSubview(overviewStatusDot)

        overviewStatusBadgeLabel = NSTextField(labelWithString: "Aktif Durum: Yönetici (Tam Yetki - Açık)")
        overviewStatusBadgeLabel.frame = NSRect(x: 26, y: 5, width: 260, height: 18)
        overviewStatusBadgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        overviewStatusBadgeLabel.textColor = AliveLockTheme.textPrimary
        statusPill.addSubview(overviewStatusBadgeLabel)

        // Right Toggle "Kilidi Etkinleştir ⌘ 7"
        let toggleBox = NSBox(frame: NSRect(x: width - 210, y: height - 58, width: 182, height: 28))
        toggleBox.boxType = .custom
        toggleBox.fillColor = AliveLockTheme.surfaceLowest
        toggleBox.borderColor = AliveLockTheme.borderDefault
        toggleBox.cornerRadius = 14
        overviewView.addSubview(toggleBox)

        let toggleLbl = NSTextField(labelWithString: "Hızlı Kilit:")
        toggleLbl.frame = NSRect(x: 12, y: 5, width: 75, height: 18)
        toggleLbl.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        toggleLbl.textColor = AliveLockTheme.textSecondary
        toggleBox.addSubview(toggleLbl)

        overviewLockToggleBtn = ModernButton(
            frame: NSRect(x: 90, y: 2, width: 84, height: 24),
            title: "⌘ 7 Kilit",
            bgColor: AliveLockTheme.accentCyan.withAlphaComponent(0.20),
            hoverBgColor: AliveLockTheme.accentCyan.withAlphaComponent(0.35),
            borderColor: AliveLockTheme.accentCyan.withAlphaComponent(0.40),
            textColor: AliveLockTheme.accentCyan,
            font: NSFont.systemFont(ofSize: 11, weight: .bold),
            cornerRadius: 6,
            target: self,
            action: #selector(handleToggleQuickLock)
        )
        toggleBox.addSubview(overviewLockToggleBtn)

        // Left Hero Card (Matching anasayfa.jpg)
        heroBox = NSBox(frame: NSRect(x: 28, y: 55, width: 340, height: height - 130))
        heroBox.boxType = .custom
        heroBox.fillColor = AliveLockTheme.surfaceLow
        heroBox.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.40)
        heroBox.borderWidth = 1.2
        heroBox.cornerRadius = AliveLockTheme.radiusXl
        overviewView.addSubview(heroBox)

        overviewHeroStatusLabel = NSTextField(labelWithString: "Güvenlik Kilidi Aktif")
        overviewHeroStatusLabel.frame = NSRect(x: 20, y: heroBox.frame.height - 52, width: heroBox.frame.width - 40, height: 26)
        overviewHeroStatusLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        overviewHeroStatusLabel.textColor = AliveLockTheme.textPrimary
        overviewHeroStatusLabel.alignment = .center
        heroBox.addSubview(overviewHeroStatusLabel)

        // Center Glowing Lock Graphic
        let heroArtwork = NSImageView(frame: NSRect(x: (heroBox.frame.width - 190) / 2, y: (heroBox.frame.height - 190) / 2 + 10, width: 190, height: 190))
        if let art = NSImage(contentsOfFile: "\(appDelegate?.projectDir ?? "")/assets/LockArtwork.png") {
            heroArtwork.image = art
        } else if let shield = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 110, weight: .bold)
            heroArtwork.image = shield.withSymbolConfiguration(conf) ?? shield
            heroArtwork.contentTintColor = AliveLockTheme.accentCyan
        }
        heroBox.addSubview(heroArtwork)

        let heroSub = NSTextField(labelWithString: "Korumalı Alan • Seçili Uygulamalar Kilitli")
        heroSub.frame = NSRect(x: 16, y: 80, width: heroBox.frame.width - 32, height: 20)
        heroSub.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        heroSub.textColor = AliveLockTheme.textSecondary
        heroSub.alignment = .center
        heroBox.addSubview(heroSub)

        overviewHeroActionBtn = ModernButton.primary(
            frame: NSRect(x: (heroBox.frame.width - 180) / 2, y: 26, width: 180, height: 42),
            title: "Kilitle [⌘ 7]",
            symbolName: "lock.fill",
            accentColor: AliveLockTheme.accentCyan,
            target: self,
            action: #selector(handleHeroAction)
        )
        heroBox.addSubview(overviewHeroActionBtn)

        // Right Column Cards
        let rightX: CGFloat = 388
        let rightWidth: CGFloat = width - rightX - 28

        // Card 1: Yönetici (Admin)
        aliCard = createDashboardCard(
            frame: NSRect(x: rightX, y: height - 195, width: rightWidth, height: 110),
            icon: "checkmark.shield.fill",
            title: "Yönetici (Admin)",
            shortcut: "[Tuş: 1]",
            subtitle: "Tam Yetki • Touch ID Doğrulaması",
            description: "Tüm kişisel uygulamaların kilidini kaldırır ve tam erişim sağlar.",
            accentColor: AliveLockTheme.accentEmerald,
            action: #selector(handleAliFromOverview)
        )
        overviewView.addSubview(aliCard)

        // Card 2: Korunuyor
        protectCard = createDashboardCard(
            frame: NSRect(x: rightX, y: height - 315, width: rightWidth, height: 110),
            icon: "lock.shield.fill",
            title: "Korunuyor",
            shortcut: "[Tuş: 2]",
            subtitle: "Korumalı Alan • Seçili Uygulamalar Kilitli",
            description: "Uygulamalara parmak izi okutulmadan kesinlikle erişilemez. (Kısayol: ⌘ 7)",
            accentColor: AliveLockTheme.accentCyan,
            action: #selector(handleProtectFromOverview)
        )
        overviewView.addSubview(protectCard)

        // Card 3: Kilitlenecek Uygulamalar
        appsCard = NSBox(frame: NSRect(x: rightX, y: 55, width: rightWidth, height: height - 380))
        appsCard.boxType = .custom
        appsCard.fillColor = AliveLockTheme.surfaceLow
        appsCard.borderColor = AliveLockTheme.borderDefault
        appsCard.borderWidth = 1.0
        appsCard.cornerRadius = AliveLockTheme.radiusLg
        overviewView.addSubview(appsCard)

        let appsIcon = NSImageView(frame: NSRect(x: 18, y: appsCard.frame.height - 40, width: 22, height: 22))
        if let img = NSImage(systemSymbolName: "lock.square.stack.fill", accessibilityDescription: nil) {
            appsIcon.image = img
            appsIcon.contentTintColor = AliveLockTheme.accentPurple
        }
        appsCard.addSubview(appsIcon)

        let appsTitle = NSTextField(labelWithString: "Kilitlenecek Uygulamalar [Tuş: 3]")
        appsTitle.frame = NSRect(x: 48, y: appsCard.frame.height - 40, width: 280, height: 22)
        appsTitle.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        appsTitle.textColor = AliveLockTheme.textPrimary
        appsCard.addSubview(appsTitle)

        let appsSub = NSTextField(labelWithString: "Kilitli Uygulama Listesini Yönet")
        appsSub.frame = NSRect(x: 48, y: appsCard.frame.height - 58, width: 350, height: 16)
        appsSub.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        appsSub.textColor = AliveLockTheme.accentPurple
        appsCard.addSubview(appsSub)

        let appsDesc = NSTextField(labelWithString: "Korunmalı modda kilitlenecek uygulamaları seçin.")
        appsDesc.frame = NSRect(x: 18, y: appsCard.frame.height - 78, width: 380, height: 16)
        appsDesc.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appsDesc.textColor = AliveLockTheme.textSecondary
        appsCard.addSubview(appsDesc)

        // Mini Quick App Rows (Finder, Safari, WhatsApp, Photos)
        let quickApps = [
            ("Finder", "com.apple.finder"),
            ("Safari", "com.apple.Safari"),
            ("WhatsApp", "net.whatsapp.WhatsApp"),
            ("Fotoğraflar", "com.apple.Photos")
        ]
        var rowY: CGFloat = appsCard.frame.height - 114
        for app in quickApps {
            let rowIcon = NSImageView(frame: NSRect(x: 20, y: rowY, width: 20, height: 20))
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.1) {
                rowIcon.image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                rowIcon.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            }
            appsCard.addSubview(rowIcon)

            let rowName = NSTextField(labelWithString: app.0)
            rowName.frame = NSRect(x: 48, y: rowY + 1, width: 160, height: 18)
            rowName.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            rowName.textColor = AliveLockTheme.textPrimary
            appsCard.addSubview(rowName)

            let isLocked = (appDelegate?.targetApps.contains(where: { $0.bundleId.lowercased() == app.1.lowercased() || $0.processName.lowercased() == app.0.lowercased() }) == true)
            let toggle = NSSwitch(frame: NSRect(x: appsCard.frame.width - 65, y: rowY - 1, width: 44, height: 22))
            toggle.state = isLocked ? .on : .off
            toggle.target = self
            toggle.action = #selector(handleQuickAppToggle(_:))
            appsCard.addSubview(toggle)

            rowY -= 30
        }

        let manageAllBtn = ModernButton.secondary(
            frame: NSRect(x: appsCard.frame.width - 165, y: 12, width: 150, height: 28),
            title: "➕ Tümünü Yönet...",
            symbolName: nil,
            target: self,
            action: #selector(handleGoToAppsGrid)
        )
        appsCard.addSubview(manageAllBtn)

        // Bottom Footer Warning
        let footerLabel = NSTextField(labelWithString: "💡 Kapatma seçeneği yoktur. İstediğiniz zaman ⌘ 7 ile anında kilitleyebilirsiniz.")
        footerLabel.frame = NSRect(x: 28, y: 16, width: width - 56, height: 20)
        footerLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        footerLabel.textColor = AliveLockTheme.textSecondary
        footerLabel.alignment = .center
        overviewView.addSubview(footerLabel)
    }

    private func createDashboardCard(frame: NSRect, icon: String, title: String, shortcut: String, subtitle: String, description: String, accentColor: NSColor, action: Selector) -> ClickableCardBox {
        let box = ClickableCardBox(frame: frame)
        box.boxType = .custom
        let normalBg = AliveLockTheme.surfaceLow
        let hoverBg = AliveLockTheme.surfaceHover
        box.fillColor = normalBg
        box.normalFillColor = normalBg
        box.hoverFillColor = hoverBg
        box.borderColor = AliveLockTheme.borderDefault
        box.normalBorderColor = AliveLockTheme.borderDefault
        box.hoverBorderColor = accentColor.withAlphaComponent(0.50)
        box.borderWidth = 1.0
        box.cornerRadius = AliveLockTheme.radiusLg
        box.target = self
        box.action = action

        let iconBadge = NSBox(frame: NSRect(x: 16, y: (frame.height - 50) / 2, width: 50, height: 50))
        iconBadge.boxType = .custom
        iconBadge.fillColor = accentColor.withAlphaComponent(0.14)
        iconBadge.borderColor = accentColor.withAlphaComponent(0.28)
        iconBadge.borderWidth = 1.0
        iconBadge.cornerRadius = AliveLockTheme.radiusMd
        box.addSubview(iconBadge)

        let imgView = NSImageView(frame: NSRect(x: 10, y: 10, width: 30, height: 30))
        if let symImg = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            imgView.image = symImg.withSymbolConfiguration(config) ?? symImg
            imgView.contentTintColor = accentColor
        }
        iconBadge.addSubview(imgView)

        let contentX: CGFloat = 80
        let contentWidth = frame.width - contentX - 16

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: contentX, y: 68, width: contentWidth - 90, height: 22)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        box.addSubview(titleLabel)

        let badgeLabel = NSTextField(labelWithString: shortcut)
        badgeLabel.frame = NSRect(x: frame.width - 104, y: 68, width: 90, height: 22)
        badgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        badgeLabel.alignment = .right
        badgeLabel.textColor = accentColor
        box.addSubview(badgeLabel)

        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.frame = NSRect(x: contentX, y: 44, width: contentWidth, height: 18)
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        subLabel.textColor = accentColor
        box.addSubview(subLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.frame = NSRect(x: contentX, y: 18, width: contentWidth, height: 20)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = AliveLockTheme.textSecondary
        box.addSubview(descLabel)

        return box
    }

    // MARK: - Tab 1: Apps Grid (Kilitlenecek Uygulamalar)
    private func buildAppsGridView(width: CGFloat, height: CGFloat) {
        appsGridView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentContainer.addSubview(appsGridView)

        let titleLabel = NSTextField(labelWithString: "Kilitli ve Korumalı Uygulamalar")
        titleLabel.frame = NSRect(x: 28, y: height - 60, width: 420, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        appsGridView.addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: "Açılırken biyometrik veya yönetici parolası doğrulaması gerektirecek uygulamaları belirleyin.")
        subLabel.frame = NSRect(x: 28, y: height - 84, width: 560, height: 18)
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = AliveLockTheme.textSecondary
        appsGridView.addSubview(subLabel)

        // Right Security Settings Pill
        let secBox = NSBox(frame: NSRect(x: width - 260, y: height - 85, width: 232, height: 50))
        secBox.boxType = .custom
        secBox.fillColor = AliveLockTheme.surfaceLowest
        secBox.borderColor = AliveLockTheme.borderDefault
        secBox.cornerRadius = AliveLockTheme.radiusMd
        appsGridView.addSubview(secBox)

        let touchLabel = NSTextField(labelWithString: "Touch ID Koruması: AKTİF")
        touchLabel.frame = NSRect(x: 10, y: 26, width: 210, height: 16)
        touchLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        touchLabel.textColor = AliveLockTheme.accentEmerald
        secBox.addSubview(touchLabel)

        let masterLabel = NSTextField(labelWithString: "Yönetici Parolası: AKTİF")
        masterLabel.frame = NSRect(x: 10, y: 8, width: 210, height: 16)
        masterLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        masterLabel.textColor = AliveLockTheme.accentEmerald
        secBox.addSubview(masterLabel)

        // Filter Bar (Search + Segmented + Add from Finder)
        searchField = NSSearchField(frame: NSRect(x: 28, y: height - 128, width: 240, height: 32))
        searchField.placeholderString = "Uygulamalarda ara..."
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 8
        searchField.layer?.backgroundColor = AliveLockTheme.surfaceLowest.cgColor
        searchField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        searchField.layer?.borderWidth = 1.0
        searchField.textColor = AliveLockTheme.textPrimary
        searchField.target = self
        searchField.action = #selector(handleAppFilterChanged)
        appsGridView.addSubview(searchField)

        filterSegment = NSSegmentedControl(labels: ["Tümü", "Kilitliler", "Korumasız"], trackingMode: .selectOne, target: self, action: #selector(handleAppFilterChanged))
        filterSegment.frame = NSRect(x: 280, y: height - 128, width: 220, height: 32)
        filterSegment.selectedSegment = 0
        appsGridView.addSubview(filterSegment)

        let addBtn = ModernButton.primary(
            frame: NSRect(x: width - 220, y: height - 130, width: 192, height: 34),
            title: "➕ Finder'dan Ekle (.app)",
            symbolName: nil,
            accentColor: AliveLockTheme.accentCyan,
            target: self,
            action: #selector(handleSelectAppFromFinder)
        )
        appsGridView.addSubview(addBtn)

        // Scrollable Grid Area
        let scrollY: CGFloat = 55
        let scrollH = height - 145 - scrollY
        appsScrollView = NSScrollView(frame: NSRect(x: 28, y: scrollY, width: width - 56, height: scrollH))
        appsScrollView.hasVerticalScroller = true
        appsScrollView.autohidesScrollers = true
        appsScrollView.borderType = .noBorder
        appsScrollView.drawsBackground = false
        appsGridView.addSubview(appsScrollView)

        appsGridContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: appsScrollView.contentSize.width, height: 600))
        appsScrollView.documentView = appsGridContainer

        // Bottom Footer
        let activeUser = NSFullUserName().isEmpty ? "Yönetici" : NSFullUserName()
        let footer = NSTextField(labelWithString: "💡 Koruma aktiftir. Anında kilitleme kısayolu: ⌘ 7. Aktif Profil: \(activeUser) (Admin)")
        footer.frame = NSRect(x: 28, y: 16, width: width - 56, height: 20)
        footer.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        footer.textColor = AliveLockTheme.accentEmerald
        footer.alignment = .center
        appsGridView.addSubview(footer)
    }

    func refreshAppsGrid() {
        guard let appDelegate = appDelegate else { return }
        let defaultApps: [(String, String, String)] = [
            ("Safari", "Safari", "com.apple.Safari"),
            ("Photos", "Photos", "com.apple.Photos"),
            ("Terminal", "Terminal", "com.apple.Terminal"),
            ("Finder", "Finder", "com.apple.finder"),
            ("VS Code", "Code", "com.microsoft.VSCode"),
            ("Slack", "Slack", "com.tinyspeck.slackmacgap"),
            ("Messages", "Messages", "com.apple.MobileSMS"),
            ("Spotify", "Spotify", "com.spotify.client"),
            ("WhatsApp", "WhatsApp", "net.whatsapp.WhatsApp")
        ]

        var combined: [(displayName: String, processName: String, bundleId: String, icon: NSImage?)] = []
        var seenBundleIds = Set<String>()

        // 1. Target apps from config first
        for target in appDelegate.targetApps {
            let bId = target.bundleId.lowercased()
            if !seenBundleIds.contains(bId) {
                seenBundleIds.insert(bId)
                var icon: NSImage? = nil
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                }
                combined.append((displayName: target.displayName, processName: target.processName, bundleId: target.bundleId, icon: icon))
            }
        }

        // 2. Default apps to complete grid
        for d in defaultApps {
            let bId = d.2.lowercased()
            if !seenBundleIds.contains(bId) {
                seenBundleIds.insert(bId)
                var icon: NSImage? = nil
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: d.2) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                }
                combined.append((displayName: d.0, processName: d.1, bundleId: d.2, icon: icon))
            }
        }

        allAppItems = combined
        renderAppCards()
    }

    private func renderAppCards() {
        appsGridContainer.subviews.removeAll()

        guard let appDelegate = appDelegate else { return }
        let currentLocked = Set(appDelegate.targetApps.map { $0.bundleId.lowercased() })
        let currentLockedProc = Set(appDelegate.targetApps.map { $0.processName.lowercased() })

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seg = filterSegment.selectedSegment // 0: All, 1: Locked, 2: Unlocked

        let filtered = allAppItems.filter { item in
            let isLocked = currentLocked.contains(item.bundleId.lowercased()) || currentLockedProc.contains(item.processName.lowercased())
            if seg == 1 && !isLocked { return false }
            if seg == 2 && isLocked { return false }
            if !query.isEmpty {
                return item.displayName.lowercased().contains(query) || item.processName.lowercased().contains(query)
            }
            return true
        }

        let cardWidth: CGFloat = 186
        let cardHeight: CGFloat = 146
        let spacing: CGFloat = 16
        let columns = 4

        for (idx, item) in filtered.enumerated() {
            let col = idx % columns
            let row = idx / columns
            let x = CGFloat(col) * (cardWidth + spacing)
            let y = CGFloat(row) * (cardHeight + spacing)

            let isLocked = currentLocked.contains(item.bundleId.lowercased()) || currentLockedProc.contains(item.processName.lowercased())

            let card = NSBox(frame: NSRect(x: x, y: y, width: cardWidth, height: cardHeight))
            card.boxType = .custom
            card.fillColor = AliveLockTheme.surfaceLow
            card.borderColor = isLocked ? AliveLockTheme.accentCyan.withAlphaComponent(0.45) : AliveLockTheme.borderSubtle
            card.borderWidth = 1.0
            card.cornerRadius = AliveLockTheme.radiusMd
            appsGridContainer.addSubview(card)

            let iconView = NSImageView(frame: NSRect(x: (cardWidth - 52) / 2, y: cardHeight - 66, width: 52, height: 52))
            iconView.image = item.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            card.addSubview(iconView)

            let nameLbl = NSTextField(labelWithString: item.displayName)
            nameLbl.frame = NSRect(x: 8, y: 40, width: cardWidth - 16, height: 18)
            nameLbl.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            nameLbl.textColor = AliveLockTheme.textPrimary
            nameLbl.alignment = .center
            card.addSubview(nameLbl)

            // Status Badge Pill & Switch
            let statusBadge = NSBox(frame: NSRect(x: 10, y: 10, width: 88, height: 22))
            statusBadge.boxType = .custom
            statusBadge.cornerRadius = 6
            statusBadge.borderWidth = 1.0

            let statusLbl = NSTextField(labelWithString: isLocked ? "🔒 Kilitli" : "🔓 Açık")
            statusLbl.frame = NSRect(x: 0, y: 2, width: 88, height: 16)
            statusLbl.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            statusLbl.alignment = .center

            if isLocked {
                statusBadge.fillColor = AliveLockTheme.accentCyan.withAlphaComponent(0.15)
                statusBadge.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.35)
                statusLbl.textColor = AliveLockTheme.accentCyan
            } else {
                statusBadge.fillColor = AliveLockTheme.surfaceHigh
                statusBadge.borderColor = AliveLockTheme.borderSubtle
                statusLbl.textColor = AliveLockTheme.textSecondary
            }
            statusBadge.addSubview(statusLbl)
            card.addSubview(statusBadge)

            let sw = NSSwitch(frame: NSRect(x: cardWidth - 54, y: 10, width: 44, height: 22))
            sw.state = isLocked ? .on : .off
            sw.target = self
            sw.action = #selector(handleGridAppSwitchToggled(_:))
            sw.identifier = NSUserInterfaceItemIdentifier("\(item.bundleId)||||\(item.processName)||||\(item.displayName)")
            card.addSubview(sw)
        }

        let totalRows = (filtered.count + columns - 1) / columns
        let totalH = max(CGFloat(totalRows) * (cardHeight + spacing) + 30, appsScrollView.contentSize.height)
        appsGridContainer.frame = NSRect(x: 0, y: 0, width: appsScrollView.contentSize.width, height: totalH)
    }

    @objc func handleAppFilterChanged() {
        renderAppCards()
    }

    @objc func handleGridAppSwitchToggled(_ sender: NSSwitch) {
        guard let rawId = sender.identifier?.rawValue else { return }
        let parts = rawId.components(separatedBy: "||||")
        guard parts.count == 3, let appDelegate = appDelegate else { return }
        let bId = parts[0]
        let pName = parts[1]
        let dName = parts[2]

        if sender.state == .on {
            if !appDelegate.targetApps.contains(where: { $0.bundleId.lowercased() == bId.lowercased() }) {
                appDelegate.targetApps.append(TargetAppConfig(processName: pName, bundleId: bId, displayName: dName))
            }
        } else {
            appDelegate.targetApps.removeAll { $0.bundleId.lowercased() == bId.lowercased() || $0.processName.lowercased() == pName.lowercased() }
        }

        appDelegate.saveConfig()
        if appDelegate.isProtectedMode() {
            appDelegate.enforceProtectionOnRunningApps()
        }
        renderAppCards()
    }

    @objc func handleSelectAppFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Korumaya Ekle"
        panel.message = "Kilitlemek istediğiniz uygulamayı seçin:"

        panel.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, let appDelegate = self.appDelegate else { return }
            let bundle = Bundle(url: url)
            let bId = bundle?.bundleIdentifier ?? ""
            let pName = url.deletingPathExtension().lastPathComponent
            let dName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
                        (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? pName

            if !appDelegate.targetApps.contains(where: { $0.bundleId.lowercased() == bId.lowercased() }) {
                appDelegate.targetApps.append(TargetAppConfig(processName: pName, bundleId: bId, displayName: dName))
                appDelegate.saveConfig()
                if appDelegate.isProtectedMode() {
                    appDelegate.enforceProtectionOnRunningApps()
                }
                self.refreshAppsGrid()
            }
        }
    }

    // MARK: - Tab 2: Gallery (Güvenlik Günlükleri)
    private func buildGalleryView(width: CGFloat, height: CGFloat) {
        galleryView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentContainer.addSubview(galleryView)

        let titleLabel = NSTextField(labelWithString: "Güvenlik Günlükleri & Fotoğraf Kasası")
        titleLabel.frame = NSRect(x: 28, y: height - 60, width: 440, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        galleryView.addSubview(titleLabel)

        let vaultBadge = NSBox(frame: NSRect(x: width - 230, y: height - 58, width: 202, height: 28))
        vaultBadge.boxType = .custom
        vaultBadge.fillColor = AliveLockTheme.accentAmber.withAlphaComponent(0.15)
        vaultBadge.borderColor = AliveLockTheme.accentAmber.withAlphaComponent(0.40)
        vaultBadge.borderWidth = 1.0
        vaultBadge.cornerRadius = 8
        galleryView.addSubview(vaultBadge)

        let vaultLbl = NSTextField(labelWithString: "🔒 Kasa Durumu: AES-256 Şifreli")
        vaultLbl.frame = NSRect(x: 8, y: 5, width: 186, height: 16)
        vaultLbl.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        vaultLbl.textColor = AliveLockTheme.accentAmber
        vaultBadge.addSubview(vaultLbl)

        // Top Banner
        let bannerBox = NSBox(frame: NSRect(x: 28, y: height - 150, width: width - 56, height: 80))
        bannerBox.boxType = .custom
        bannerBox.fillColor = AliveLockTheme.surfaceLow
        bannerBox.borderColor = AliveLockTheme.accentAmber.withAlphaComponent(0.30)
        bannerBox.borderWidth = 1.0
        bannerBox.cornerRadius = AliveLockTheme.radiusLg
        galleryView.addSubview(bannerBox)

        let bannerIcon = NSImageView(frame: NSRect(x: (bannerBox.frame.width - 32) / 2, y: 44, width: 32, height: 32))
        if let lockDown = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
            bannerIcon.image = lockDown
            bannerIcon.contentTintColor = AliveLockTheme.accentAmber
        }
        bannerBox.addSubview(bannerIcon)

        let bannerText = NSTextField(labelWithString: "Yetkisiz Giriş & Hatalı Parmak İzi Fotoğraf Kayıtları")
        bannerText.frame = NSRect(x: 20, y: 22, width: bannerBox.frame.width - 40, height: 18)
        bannerText.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        bannerText.textColor = AliveLockTheme.textPrimary
        bannerText.alignment = .center
        bannerBox.addSubview(bannerText)

        let bannerSub = NSTextField(labelWithString: "İzinsiz giriş denemelerinde çekilen fotoğraflar bu cihazda şifreli saklanır ve Telegram'a aktarılır.")
        bannerSub.frame = NSRect(x: 20, y: 6, width: bannerBox.frame.width - 40, height: 16)
        bannerSub.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        bannerSub.textColor = AliveLockTheme.textSecondary
        bannerSub.alignment = .center
        bannerBox.addSubview(bannerSub)

        // Photo Grid Scroll View
        let scrollY: CGFloat = 50
        let scrollH = height - 165 - scrollY
        galleryScrollView = NSScrollView(frame: NSRect(x: 28, y: scrollY, width: width - 56, height: scrollH))
        galleryScrollView.hasVerticalScroller = true
        galleryScrollView.autohidesScrollers = true
        galleryScrollView.borderType = .noBorder
        galleryScrollView.drawsBackground = false
        galleryView.addSubview(galleryScrollView)

        galleryGridContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: galleryScrollView.contentSize.width, height: 600))
        galleryScrollView.documentView = galleryGridContainer

        // Bottom Storage Footer
        galleryCountLabel = NSTextField(labelWithString: "Kasa Depolama: 0 Fotoğraf • AES-256 Şifreli")
        galleryCountLabel.frame = NSRect(x: 28, y: 16, width: width - 56, height: 20)
        galleryCountLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        galleryCountLabel.textColor = AliveLockTheme.textSecondary
        galleryView.addSubview(galleryCountLabel)
    }

    func refreshGallery() {
        galleryGridContainer.subviews.removeAll()

        guard let appDelegate = appDelegate else { return }
        let folder = "\(appDelegate.projectDir)/logs/intruders"
        let folderURL = URL(fileURLWithPath: folder)

        guard let files = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return
        }

        let jpgs = files
            .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return d1 > d2
            }

        galleryCountLabel.stringValue = "Kasa Depolama: \(jpgs.count) Fotoğraf Kaydı • AES-256 Şifreli Yerel Kasa"

        if jpgs.isEmpty {
            let emptyBox = NSBox(frame: NSRect(x: (galleryScrollView.contentSize.width - 340) / 2, y: 120, width: 340, height: 160))
            emptyBox.boxType = .custom
            emptyBox.fillColor = AliveLockTheme.surfaceLow
            emptyBox.borderColor = AliveLockTheme.borderSubtle
            emptyBox.cornerRadius = AliveLockTheme.radiusLg

            let emptyIcon = NSImageView(frame: NSRect(x: (340 - 44) / 2, y: 95, width: 44, height: 44))
            if let img = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
                emptyIcon.image = img.withSymbolConfiguration(conf) ?? img
                emptyIcon.contentTintColor = AliveLockTheme.accentEmerald
            }
            emptyBox.addSubview(emptyIcon)

            let emptyLabel = NSTextField(labelWithString: "Henüz kaydedilmiş yetkisiz giriş kaydı bulunmuyor.")
            emptyLabel.frame = NSRect(x: 10, y: 60, width: 320, height: 22)
            emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            emptyLabel.textColor = AliveLockTheme.textPrimary
            emptyLabel.alignment = .center
            emptyBox.addSubview(emptyLabel)

            let emptySub = NSTextField(labelWithString: "Sisteminiz tamamen güvende ve koruma altında.")
            emptySub.frame = NSRect(x: 10, y: 38, width: 320, height: 18)
            emptySub.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            emptySub.textColor = AliveLockTheme.textSecondary
            emptySub.alignment = .center
            emptyBox.addSubview(emptySub)

            galleryGridContainer.addSubview(emptyBox)
            return
        }

        let cardWidth: CGFloat = 186
        let cardHeight: CGFloat = 142
        let spacing: CGFloat = 16
        let columns = 4

        for (idx, photoURL) in jpgs.enumerated() {
            let col = idx % columns
            let row = idx / columns
            let x = CGFloat(col) * (cardWidth + spacing)
            let y = CGFloat(row) * (cardHeight + spacing)

            let photoBox = NSBox(frame: NSRect(x: x, y: y, width: cardWidth, height: cardHeight))
            photoBox.boxType = .custom
            photoBox.fillColor = AliveLockTheme.surfaceLow
            photoBox.borderColor = AliveLockTheme.borderDefault
            photoBox.borderWidth = 1.0
            photoBox.cornerRadius = AliveLockTheme.radiusMd
            galleryGridContainer.addSubview(photoBox)

            let imgView = NSImageView(frame: NSRect(x: 0, y: 30, width: cardWidth, height: cardHeight - 30))
            imgView.imageScaling = .scaleProportionallyUpOrDown
            imgView.image = NSImage(contentsOf: photoURL)
            imgView.wantsLayer = true
            imgView.layer?.cornerRadius = 10
            imgView.layer?.masksToBounds = true
            photoBox.addSubview(imgView)

            // Top Lock Badge
            let lockBadge = NSBox(frame: NSRect(x: cardWidth - 84, y: cardHeight - 28, width: 78, height: 22))
            lockBadge.boxType = .custom
            lockBadge.fillColor = NSColor.black.withAlphaComponent(0.70)
            lockBadge.borderColor = AliveLockTheme.accentRed.withAlphaComponent(0.60)
            lockBadge.cornerRadius = 6
            photoBox.addSubview(lockBadge)

            let lockLbl = NSTextField(labelWithString: "🚨 İhlal Tespiti")
            lockLbl.frame = NSRect(x: 2, y: 3, width: 74, height: 16)
            lockLbl.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            lockLbl.textColor = AliveLockTheme.accentRed
            lockLbl.alignment = .center
            lockBadge.addSubview(lockLbl)

            // Bottom Label (App & Time)
            let filename = photoURL.lastPathComponent
            let cleanTag = filename
                .replacingOccurrences(of: "izinsiz_giris_", with: "")
                .replacingOccurrences(of: ".jpg", with: "")
                .replacingOccurrences(of: "_", with: " ")

            let bottomBar = NSTextField(labelWithString: cleanTag)
            bottomBar.frame = NSRect(x: 6, y: 6, width: cardWidth - 12, height: 20)
            bottomBar.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            bottomBar.textColor = AliveLockTheme.textPrimary
            bottomBar.alignment = .center
            bottomBar.lineBreakMode = .byTruncatingTail
            photoBox.addSubview(bottomBar)

            // Click Overlay Button for preview
            let clickBtn = NSButton(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
            clickBtn.isTransparent = true
            clickBtn.target = self
            clickBtn.action = #selector(handlePhotoPreviewClicked(_:))
            clickBtn.identifier = NSUserInterfaceItemIdentifier(photoURL.path)
            photoBox.addSubview(clickBtn)
        }

        let totalRows = (jpgs.count + columns - 1) / columns
        let totalH = max(CGFloat(totalRows) * (cardHeight + spacing) + 30, galleryScrollView.contentSize.height)
        galleryGridContainer.frame = NSRect(x: 0, y: 0, width: galleryScrollView.contentSize.width, height: totalH)
    }

    @objc func handlePhotoPreviewClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, let img = NSImage(contentsOfFile: path) else { return }
        let win = PhotoPreviewWindow(image: img, title: URL(fileURLWithPath: path).lastPathComponent)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - Tab 3: Settings (Telegram & Ayarlar)
    private func buildSettingsView(width: CGFloat, height: CGFloat) {
        settingsView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        contentContainer.addSubview(settingsView)

        let titleLabel = NSTextField(labelWithString: "Telegram & Güvenlik Ayarları")
        titleLabel.frame = NSRect(x: 28, y: height - 60, width: 440, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AliveLockTheme.textPrimary
        settingsView.addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: "İzinsiz giriş denemelerinde çekilen fotoğraflar Telegram botunuza anında gönderilir.")
        subLabel.frame = NSRect(x: 28, y: height - 84, width: 600, height: 18)
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = AliveLockTheme.textSecondary
        settingsView.addSubview(subLabel)

        // Settings Box
        let box = NSBox(frame: NSRect(x: 28, y: 100, width: width - 56, height: height - 200))
        box.boxType = .custom
        box.fillColor = AliveLockTheme.surfaceLow
        box.borderColor = AliveLockTheme.borderDefault
        box.borderWidth = 1.0
        box.cornerRadius = AliveLockTheme.radiusLg
        settingsView.addSubview(box)

        enableCheckbox = NSButton(checkboxWithTitle: "Fotoğraflı Telegram bildirimlerini aktif et", target: self, action: nil)
        enableCheckbox.frame = NSRect(x: 24, y: box.frame.height - 48, width: 450, height: 24)
        enableCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        enableCheckbox.state = (appDelegate?.telegramEnabled == true) ? .on : .off
        box.addSubview(enableCheckbox)

        let tokenLbl = NSTextField(labelWithString: "Telegram Bot Token:")
        tokenLbl.frame = NSRect(x: 24, y: box.frame.height - 90, width: 300, height: 18)
        tokenLbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        tokenLbl.textColor = AliveLockTheme.textPrimary
        box.addSubview(tokenLbl)

        tokenField = NSTextField(frame: NSRect(x: 24, y: box.frame.height - 124, width: box.frame.width - 48, height: 32))
        tokenField.placeholderString = "Örn: 123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tokenField.stringValue = appDelegate?.telegramBotToken ?? ""
        tokenField.backgroundColor = AliveLockTheme.surfaceLowest
        tokenField.textColor = AliveLockTheme.textPrimary
        tokenField.wantsLayer = true
        tokenField.layer?.cornerRadius = 8
        tokenField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        tokenField.layer?.borderWidth = 1.0
        box.addSubview(tokenField)

        let tokenHint = NSTextField(labelWithString: "💡 Telegram'da @BotFather ile açtığınız botun HTTP API Token'ı.")
        tokenHint.frame = NSRect(x: 24, y: box.frame.height - 146, width: 500, height: 16)
        tokenHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        tokenHint.textColor = AliveLockTheme.textSecondary
        box.addSubview(tokenHint)

        let chatLbl = NSTextField(labelWithString: "Telegram Chat ID:")
        chatLbl.frame = NSRect(x: 24, y: box.frame.height - 185, width: 300, height: 18)
        chatLbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        chatLbl.textColor = AliveLockTheme.textPrimary
        box.addSubview(chatLbl)

        chatIdField = NSTextField(frame: NSRect(x: 24, y: box.frame.height - 219, width: box.frame.width - 48, height: 32))
        chatIdField.placeholderString = "Örn: 123456789"
        chatIdField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        chatIdField.stringValue = appDelegate?.telegramChatId ?? ""
        chatIdField.backgroundColor = AliveLockTheme.surfaceLowest
        chatIdField.textColor = AliveLockTheme.textPrimary
        chatIdField.wantsLayer = true
        chatIdField.layer?.cornerRadius = 8
        chatIdField.layer?.borderColor = AliveLockTheme.borderDefault.cgColor
        chatIdField.layer?.borderWidth = 1.0
        box.addSubview(chatIdField)

        let chatHint = NSTextField(labelWithString: "💡 Telegram'da @userinfobot botundan öğrendiğiniz kullanıcı ID'niz.")
        chatHint.frame = NSRect(x: 24, y: box.frame.height - 241, width: 500, height: 16)
        chatHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        chatHint.textColor = AliveLockTheme.textSecondary
        box.addSubview(chatHint)

        settingsStatusLabel = NSTextField(labelWithString: "")
        settingsStatusLabel.frame = NSRect(x: 24, y: 70, width: box.frame.width - 48, height: 24)
        settingsStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        settingsStatusLabel.alignment = .center
        box.addSubview(settingsStatusLabel)

        testBtn = ModernButton.secondary(
            frame: NSRect(x: 24, y: 22, width: 220, height: 38),
            title: "🧪 Fotoğraflı Test Gönder",
            symbolName: nil,
            target: self,
            action: #selector(handleSendTestPhotoFromSettings)
        )
        box.addSubview(testBtn)

        saveBtn = ModernButton.primary(
            frame: NSRect(x: box.frame.width - 180, y: 22, width: 156, height: 38),
            title: "💾 Ayarları Kaydet",
            symbolName: nil,
            accentColor: AliveLockTheme.accentCyan,
            target: self,
            action: #selector(handleSaveSettings)
        )
        box.addSubview(saveBtn)
    }

    @objc func handleSendTestPhotoFromSettings() {
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatId = chatIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty, !chatId.isEmpty else {
            settingsStatusLabel.textColor = AliveLockTheme.accentRed
            settingsStatusLabel.stringValue = "⚠️ Lütfen önce Bot Token ve Chat ID alanlarını doldurunuz."
            return
        }

        settingsStatusLabel.textColor = AliveLockTheme.accentCyan
        settingsStatusLabel.stringValue = "✈️ Fotoğraflı test bildirimi Telegram'a iletiliyor..."
        testBtn.isEnabled = false

        var testData: Data? = nil
        if let appDelegate = appDelegate {
            let path = "\(appDelegate.projectDir)/assets/LockArtwork.png"
            testData = try? Data(contentsOf: URL(fileURLWithPath: path))
        }

        TelegramNotifier.shared.sendAlert(
            photoData: testData,
            appName: "AliveLock (Test)",
            reason: "🧪 Dashboard Entegrasyon Testi",
            token: token,
            chatId: chatId
        ) { [weak self] success, message in
            guard let self = self else { return }
            self.testBtn.isEnabled = true
            if success {
                self.enableCheckbox.state = .on
                self.settingsStatusLabel.textColor = AliveLockTheme.accentEmerald
                self.settingsStatusLabel.stringValue = "✅ Harika! Fotoğraflı test mesajı Telegram'a ulaştı."
            } else {
                self.settingsStatusLabel.textColor = AliveLockTheme.accentRed
                self.settingsStatusLabel.stringValue = "❌ Hata: \(message)"
            }
        }
    }

    @objc func handleSaveSettings() {
        guard let appDelegate = appDelegate else { return }
        appDelegate.telegramBotToken = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        appDelegate.telegramChatId = chatIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        appDelegate.telegramEnabled = (enableCheckbox.state == .on)
        appDelegate.saveConfig()

        settingsStatusLabel.textColor = AliveLockTheme.accentEmerald
        settingsStatusLabel.stringValue = "💾 Ayarlar başarıyla kaydedildi!"
    }

    // MARK: - Actions & Status Updates
    func updateStatus() {
        guard let appDelegate = appDelegate else { return }
        let mode = appDelegate.currentMode
        if mode != "Korunuyor" {
            overviewStatusDot.layer?.backgroundColor = AliveLockTheme.accentEmerald.cgColor
            overviewStatusBadgeLabel.stringValue = "Aktif Durum: Yönetici (Tam Yetki - Açık)"
            overviewStatusBadgeLabel.textColor = AliveLockTheme.accentEmerald
            overviewHeroStatusLabel.stringValue = "Güvenlik Kilidi Açık (Yönetici Modu)"
            overviewHeroStatusLabel.textColor = AliveLockTheme.accentEmerald
            overviewHeroActionBtn.title = "🛡️ Kilitle [⌘ 7]"
            overviewHeroActionBtn.normalBgColor = AliveLockTheme.accentCyan.withAlphaComponent(0.24)
            overviewHeroActionBtn.hoverBgColor = AliveLockTheme.accentCyan.withAlphaComponent(0.38)
            overviewHeroActionBtn.normalBorderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.60)
            overviewHeroActionBtn.hoverBorderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.95)
            overviewHeroActionBtn.customTextColor = .white
            overviewLockToggleBtn.title = "Açık"
            overviewLockToggleBtn.customTextColor = AliveLockTheme.accentEmerald
            heroBox.borderColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.45)
            aliCard.borderColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.60)
            protectCard.borderColor = AliveLockTheme.borderDefault
        } else {
            overviewStatusDot.layer?.backgroundColor = AliveLockTheme.accentCyan.cgColor
            overviewStatusBadgeLabel.stringValue = "Aktif Durum: Korunuyor (Kilitli)"
            overviewStatusBadgeLabel.textColor = AliveLockTheme.accentCyan
            overviewHeroStatusLabel.stringValue = "Güvenlik Kilidi Aktif"
            overviewHeroStatusLabel.textColor = AliveLockTheme.accentCyan
            overviewHeroActionBtn.title = "🔓 Kilidi Aç (Touch ID)"
            overviewHeroActionBtn.normalBgColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.24)
            overviewHeroActionBtn.hoverBgColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.38)
            overviewHeroActionBtn.normalBorderColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.60)
            overviewHeroActionBtn.hoverBorderColor = AliveLockTheme.accentEmerald.withAlphaComponent(0.95)
            overviewHeroActionBtn.customTextColor = .white
            overviewLockToggleBtn.title = "Kilitli"
            overviewLockToggleBtn.customTextColor = AliveLockTheme.accentCyan
            heroBox.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.45)
            aliCard.borderColor = AliveLockTheme.borderDefault
            protectCard.borderColor = AliveLockTheme.accentCyan.withAlphaComponent(0.60)
        }
    }

    @objc func handleToggleQuickLock() {
        guard let appDelegate = appDelegate else { return }
        if appDelegate.currentMode != "Korunuyor" {
            appDelegate.handleProtectMode()
        } else {
            appDelegate.handleAliMode()
        }
        updateStatus()
    }

    @objc func handleHeroAction() {
        handleToggleQuickLock()
    }

    @objc func handleAliFromOverview() {
        appDelegate?.handleAliMode()
        updateStatus()
    }

    @objc func handleProtectFromOverview() {
        appDelegate?.handleProtectMode()
        updateStatus()
    }

    @objc func handleGoToAppsGrid() {
        switchTab(to: 1)
    }

    @objc func handleQuickAppToggle(_ sender: NSSwitch) {
        switchTab(to: 1)
    }
}

// MARK: - Lock Screen Window
class LockScreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters {
            if chars == "1" {
                if let appDel = NSApp.delegate as? AppDelegate {
                    appDel.handleAliMode()
                }
                return
            } else if chars == "2" {
                if let appDel = NSApp.delegate as? AppDelegate {
                    appDel.handleProtectMode()
                }
                return
            } else if chars == "3" {
                if let appDel = NSApp.delegate as? AppDelegate {
                    appDel.openLockedAppsManager()
                }
                return
            }
        }
        if event.keyCode == 53 { // ESC
            if let appDel = NSApp.delegate as? AppDelegate {
                appDel.feedbackLabel?.textColor = AliveLockTheme.accentAmber
                appDel.feedbackLabel?.stringValue = "⚠️ Devam etmek için 1 (Yönetici) veya 2 (Korunuyor) seçmelisiniz."
            }
            return
        }
        super.keyDown(with: event)
    }
}


// MARK: - Kernel-Level Single Instance Lock & Main Entry
let lockFilePath = "/tmp/alivelock.lock"
let lockFd = open(lockFilePath, O_CREAT | O_RDWR, 0o600)

if lockFd < 0 || flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
    print("[AliveLock] Başka bir örnek zaten çalışıyor. Mevcut örnek öne getiriliyor...")
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("com.alivelock.app.showLockScreen"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.alivelock.app")
    for app in running {
        if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
