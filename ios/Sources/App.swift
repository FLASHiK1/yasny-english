import UIKit
import WebKit
import AVFoundation
import Speech
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var web: WKWebView!
    private let synth = AVSpeechSynthesizer()
    private var saveWork: DispatchWorkItem?
    private let storageKey = "yasny-eng-v1"

    // Распознавание речи
    private let audioEngine = AVAudioEngine()
    private var recRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("state.json")
    }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        let uc = WKUserContentController()
        for name in ["tts", "store", "speech", "reminder", "gemini"] { uc.add(self, name: name) }

        // Прогресс дублируется в файл приложения и возвращается в localStorage при запуске.
        var boot = "window.__NATIVE_APP=true;window.__IOS_APP=true;"
        if let data = try? Data(contentsOf: stateURL),
           let saved = String(data: data, encoding: .utf8),
           let json = try? JSONSerialization.data(withJSONObject: [saved]),
           let literal = String(data: json, encoding: .utf8) {
            boot += """
            try{var __s=\(literal)[0];var __l=localStorage.getItem('\(storageKey)');
            if(!__l||(JSON.parse(__s).updatedAt||0)>(JSON.parse(__l).updatedAt||0))localStorage.setItem('\(storageKey)',__s)}catch(e){}
            """
        }
        uc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        cfg.userContentController = uc
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: - Сообщения из JavaScript

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "store":
            guard let state = message.body as? String else { return }
            saveWork?.cancel()
            let target = stateURL
            let work = DispatchWorkItem {
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? state.data(using: .utf8)?.write(to: target, options: .atomic)
            }
            saveWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
        case "tts":
            guard let body = message.body as? [String: Any] else { return }
            if (body["cmd"] as? String) == "stop" { synth.stopSpeaking(at: .immediate); return }
            speak(text: body["text"] as? String ?? "", rate: body["rate"] as? Double ?? 1, lang: body["lang"] as? String ?? "en-US", pitch: body["pitch"] as? Double ?? 1)
        case "speech":
            guard let body = message.body as? [String: Any] else { return }
            if (body["cmd"] as? String) == "start" { startListening(lang: body["lang"] as? String ?? "en-US") }
            else { finishAudio() }
        case "gemini":
            // Запрос копируется в буфер, открывается Gemini (приложение или сайт) — пользователь вставляет и отправляет
            guard let text = message.body as? String else { return }
            UIPasteboard.general.string = text
            if let url = URL(string: "https://gemini.google.com/app") { UIApplication.shared.open(url) }
        case "reminder":
            guard let body = message.body as? [String: Any] else { return }
            setReminder(on: body["on"] as? Bool ?? false, hour: body["hour"] as? Int ?? 20, minute: body["minute"] as? Int ?? 0)
        default: break
        }
    }

    // MARK: - Озвучка

    private func speak(text: String, rate: Double, lang: String, pitch: Double = 1) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-US")
        let r = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
        u.rate = min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        u.pitchMultiplier = Float(min(max(pitch, 0.5), 2.0))
        synth.speak(u)
    }

    // MARK: - Распознавание речи

    private func sendSpeech(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__nativeSpeech&&window.__nativeSpeech(\(json))", completionHandler: nil)
    }

    private func startListening(lang: String) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.sendSpeech(["type": "error", "error": "permission"]); return }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted { self.beginRecognition(lang: lang) }
                        else { self.sendSpeech(["type": "error", "error": "permission"]) }
                    }
                }
            }
        }
    }

    private func beginRecognition(lang: String) {
        cleanupRecognition()
        synth.stopSpeaking(at: .immediate)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang)), recognizer.isAvailable else {
            sendSpeech(["type": "error", "error": "unavailable"]); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recRequest = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            audioEngine.prepare()
            try audioEngine.start()
            sendSpeech(["type": "start"])

            recTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        if result.isFinal {
                            let alts = result.transcriptions.prefix(5).map { $0.formattedString }
                            self.sendSpeech(["type": "final", "text": text, "alts": Array(alts)])
                            self.cleanupRecognition()
                        } else {
                            self.sendSpeech(["type": "partial", "text": text])
                            self.armSilenceTimer(seconds: 1.6)
                        }
                    } else if error != nil {
                        self.sendSpeech(["type": "error", "error": "nomatch"])
                        self.cleanupRecognition()
                    }
                }
            }
            armSilenceTimer(seconds: 6)
        } catch {
            sendSpeech(["type": "error", "error": "audio"])
            cleanupRecognition()
        }
    }

    /// Пауза в речи или кнопка «стоп»: заканчиваем запись и ждём итоговый результат.
    private func armSilenceTimer(seconds: Double) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.finishAudio() }
    }

    private func finishAudio() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        recRequest?.endAudio()
    }

    private func cleanupRecognition() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        recRequest?.endAudio(); recRequest = nil
        recTask?.cancel(); recTask = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    // MARK: - Напоминания

    private func setReminder(on: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily"])
        guard on else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                DispatchQueue.main.async {
                    self.web.evaluateJavaScript("window.__nativeReminderDenied&&window.__nativeReminderDenied()", completionHandler: nil)
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Время английского"
            content.body = "10–15 минут сегодня — и серия продолжается"
            content.sound = .default
            var date = DateComponents()
            date.hour = hour
            date.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            center.add(UNNotificationRequest(identifier: "daily", content: content, trigger: trigger))
        }
    }

    // MARK: - Ссылки наружу

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "tel"].contains(scheme),
           navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
