import UIKit
import WebKit
import AVFoundation

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

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("state.json")
    }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(self, name: "tts")
        uc.add(self, name: "store")

        // Прогресс дублируется в файл приложения: при запуске он возвращается в localStorage,
        // если там пусто или файл новее.
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

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "store", let state = message.body as? String {
            saveWork?.cancel()
            let target = stateURL
            let work = DispatchWorkItem {
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? state.data(using: .utf8)?.write(to: target, options: .atomic)
            }
            saveWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
            return
        }
        if message.name == "tts", let body = message.body as? [String: Any] {
            if (body["cmd"] as? String) == "stop" {
                synth.stopSpeaking(at: .immediate)
                return
            }
            let text = body["text"] as? String ?? ""
            let rate = body["rate"] as? Double ?? 1
            let lang = body["lang"] as? String ?? "en-US"
            synth.stopSpeaking(at: .immediate)
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-US")
            let r = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
            u.rate = min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            synth.speak(u)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" {
            if navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}
