import Cocoa
import WebKit
import UniformTypeIdentifiers

// The Mac shell around Myrling. One window, one WKWebView, and the
// same index.html that runs in a browser, unchanged. The only native work is the part
// WebKit cannot do itself:
//
//  - Save over. WebKit has no File System Access API, so mac/bridge.js fills in
//    showOpenFilePicker and the handles it returns, and talks to BridgeHandler here to
//    show the real open panel and write the real files.
//  - Export frames. The page saves through <a download> links, which WebKit hands over
//    as WKDownloads; they land in ~/Downloads like a browser would put them.
//  - The plain file input, used when the bridge is not there, needs runOpenPanelWith.

final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
  private var files: [String: URL] = [:]     // handle id -> the file it stands for
  private var dropped: [String: URL] = [:]   // name -> file, from the last drop onto the window
  private var nextId = 0

  // the native drop layer saw these before the page did; the page claims them by name
  func noteDrop(_ urls: [URL]) {
    for u in urls { dropped[u.lastPathComponent] = u }
  }

  func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                             replyHandler: @escaping (Any?, String?) -> Void) {
    guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
      replyHandler(nil, "The message from the page made no sense"); return
    }
    switch op {
    case "pick": pick(replyHandler)
    case "write": write(body, replyHandler)
    case "claim": claim(body, replyHandler)
    default: replyHandler(nil, "Unknown op " + op)
    }
  }

  private func pick(_ reply: @escaping (Any?, String?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.png]
    panel.begin { resp in
      guard resp == .OK, !panel.urls.isEmpty else { reply(["cancelled": true], nil); return }
      var out: [[String: Any]] = []
      for url in panel.urls {
        guard let data = try? Data(contentsOf: url) else { continue }
        self.nextId += 1
        let id = "f\(self.nextId)"
        self.files[id] = url
        out.append(["id": id, "name": url.lastPathComponent, "bytes": data.base64EncodedString(),
                    "dir": url.deletingLastPathComponent().path])
      }
      reply(["files": out], nil)
    }
  }

  private func claim(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let name = body["name"] as? String, let url = dropped[name] else { reply([:], nil); return }
    nextId += 1
    let id = "f\(nextId)"
    files[id] = url
    reply(["id": id, "dir": url.deletingLastPathComponent().path], nil)
  }

  private func write(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let id = body["id"] as? String, let url = files[id],
          let b64 = body["bytes"] as? String, let data = Data(base64Encoded: b64) else {
      reply(nil, "Nothing to write"); return
    }
    do { try data.write(to: url, options: .atomic); reply(["ok": true], nil) }
    catch { reply(nil, error.localizedDescription) }
  }
}

// WebKit gives the page the dropped files but never their places on disk, so this
// subclass notes the real URLs on the way past and the bridge hands them to the page
final class DropCatchingWebView: WKWebView {
  var onFileDrop: (([URL]) -> Void)?
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
      onFileDrop?(urls)
    }
    return super.performDragOperation(sender)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
  var window: NSWindow!
  var webView: DropCatchingWebView!

  func applicationDidFinishLaunching(_ note: Notification) {
    let config = WKWebViewConfiguration()
    let ucc = config.userContentController
    if let bridge = Bundle.main.url(forResource: "bridge", withExtension: "js"),
       let src = try? String(contentsOf: bridge, encoding: .utf8) {
      ucc.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    let bridge = BridgeHandler()
    ucc.addScriptMessageHandler(bridge, contentWorld: .page, name: "eldermyr")

    webView = DropCatchingWebView(frame: .zero, configuration: config)
    webView.onFileDrop = { bridge.noteDrop($0) }
    webView.navigationDelegate = self
    webView.uiDelegate = self

    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                      styleMask: [.titled, .closable, .miniaturizable, .resizable],
                      backing: .buffered, defer: false)
    window.title = "Myrling"
    window.minSize = NSSize(width: 900, height: 620)
    window.contentView = webView
    window.center()
    window.setFrameAutosaveName("Myrling")
    window.makeKeyAndOrderFront(nil)

    if let html = Bundle.main.url(forResource: "index", withExtension: "html") {
      webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

  // the plain <input type=file>, the page's fallback when the bridge is missing
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.png]
    panel.begin { resp in completionHandler(resp == .OK ? panel.urls : nil) }
  }

  // Export frames clicks <a download> links; WebKit hands those over as downloads
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
  }
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    var url = dir.appendingPathComponent(suggestedFilename)
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var n = 1
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
      n += 1
    }
    completionHandler(url)
  }

  func buildMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Myrling",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: "Quit Myrling",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    // cut, copy, paste for the name boxes. No Undo item: Cmd+Z belongs to the page.
    let editItem = NSMenuItem(); main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    return main
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = delegate.buildMenu()
app.run()
