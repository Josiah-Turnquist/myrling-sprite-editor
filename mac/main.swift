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
    case "pickdir": pickDir(replyHandler)
    case "writeto": writeTo(body, replyHandler)
    case "pixellab": pixellab(body, replyHandler)
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

  private func pickDir(_ reply: @escaping (Any?, String?) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Save here"
    panel.begin { resp in
      guard resp == .OK, let url = panel.urls.first else { reply(["cancelled": true], nil); return }
      self.nextId += 1
      let id = "d\(self.nextId)"
      self.files[id] = url
      reply(["id": id, "name": url.lastPathComponent, "path": url.path], nil)
    }
  }

  private func writeTo(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let dirId = body["dir"] as? String, let dir = files[dirId],
          let name = body["name"] as? String, !name.isEmpty,
          !name.contains("/"), !name.contains(".."),
          let b64 = body["bytes"] as? String, let data = Data(base64Encoded: b64) else {
      reply(nil, "Nothing to write"); return
    }
    do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); reply(["ok": true], nil) }
    catch { reply(nil, error.localizedDescription) }
  }

  // the page's PixelLab calls travel natively so WebKit's cross-origin wall never
  // matters. Pinned to api.pixellab.ai and its generate paths; this is not a proxy.
  private func pixellab(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let path = body["path"] as? String, path.hasPrefix("/generate-image"), !path.contains(".."),
          let key = body["key"] as? String, !key.isEmpty,
          let json = body["body"] as? String,
          let url = URL(string: "https://api.pixellab.ai/v1" + path) else {
      reply(nil, "Nothing to ask PixelLab"); return
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 120
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    req.httpBody = json.data(using: .utf8)
    URLSession.shared.dataTask(with: req) { data, resp, err in
      DispatchQueue.main.async {
        if let err = err { reply(nil, err.localizedDescription); return }
        guard let data = data, let text = String(data: data, encoding: .utf8) else {
          reply(nil, "An empty answer came back"); return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 { reply(nil, "PixelLab said \(code): " + String(text.prefix(300))); return }
        reply(["json": text], nil)
      }
    }.resume()
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSToolbarDelegate {
  var window: NSWindow!
  var webView: DropCatchingWebView!

  // the title bar toolbar: each button presses one of the page's own image operations,
  // so the toolbar and the Image menu in the page can never disagree
  struct Tool { let id: String; let label: String; let symbol: String; let tip: String; let js: String }
  let tools: [Tool] = [
    Tool(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", tip: "Undo (Cmd+Z)", js: "EDITOR.undo()"),
    Tool(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", tip: "Redo (Shift+Z)", js: "EDITOR.redo()"),
    Tool(id: "size", label: "Canvas size", symbol: "arrow.up.left.and.arrow.down.right", tip: "Grow, shrink or scale the canvas", js: "EDITOR.image.size()"),
    Tool(id: "crop", label: "Crop", symbol: "crop", tip: "Crop to the selected box", js: "EDITOR.image.crop()"),
    Tool(id: "trim", label: "Trim", symbol: "rectangle.dashed", tip: "Trim the canvas to the painted pixels", js: "EDITOR.image.trim()"),
    Tool(id: "flipH", label: "Flip", symbol: "arrow.left.and.right", tip: "Flip left to right", js: "EDITOR.image.flipH()"),
    Tool(id: "flipV", label: "Flip vertical", symbol: "arrow.up.and.down", tip: "Flip top to bottom", js: "EDITOR.image.flipV()"),
    Tool(id: "rotate", label: "Rotate", symbol: "rotate.right", tip: "Rotate a quarter turn clockwise", js: "EDITOR.image.rotate()"),
    Tool(id: "grid", label: "Grid", symbol: "grid", tip: "Show or hide the pixel grid (G)", js: "document.getElementById('bGrid').click()"),
    Tool(id: "guides", label: "Guides", symbol: "ruler", tip: "Show or hide the feet line and the centre line", js: "document.getElementById('bGuides').click()")
  ]
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    var ids: [NSToolbarItem.Identifier] = []
    for (i, t) in tools.enumerated() {
      if i == 2 || i == 5 { ids.append(.space) }
      ids.append(NSToolbarItem.Identifier(t.id))
    }
    return ids
  }
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return tools.map { NSToolbarItem.Identifier($0.id) } + [.space, .flexibleSpace]
  }
  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
    guard let t = tools.first(where: { $0.id == id.rawValue }) else { return nil }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = t.label
    item.paletteLabel = t.label
    item.toolTip = t.tip
    item.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.label)
    item.target = self
    item.action = #selector(toolbarAction(_:))
    item.isBordered = true
    return item
  }
  @objc func toolbarAction(_ sender: NSToolbarItem) {
    if let t = tools.first(where: { $0.id == sender.itemIdentifier.rawValue }) { webView.evaluateJavaScript(t.js) }
  }

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
    let bar = NSToolbar(identifier: "myrling-main")
    bar.delegate = self
    bar.displayMode = .iconOnly
    bar.allowsUserCustomization = true
    bar.autosavesConfiguration = true
    window.toolbar = bar
    window.toolbarStyle = .unified
    window.titleVisibility = .hidden
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

  // the menu bar drives the page: each item just presses the page's own controls
  private func pageItem(_ menu: NSMenu, _ title: String, _ js: String, _ key: String = "") {
    let item = NSMenuItem(title: title, action: #selector(runPageAction(_:)), keyEquivalent: key)
    item.target = self
    item.representedObject = js
    menu.addItem(item)
  }
  @objc func runPageAction(_ sender: NSMenuItem) {
    if let js = sender.representedObject as? String { webView.evaluateJavaScript(js) }
  }

  func buildMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Myrling",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    pageItem(appMenu, "Settings…", "EDITOR.showKeys()", ",")
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
    let imageItem = NSMenuItem(); main.addItem(imageItem)
    let image = NSMenu(title: "Image")
    pageItem(image, "Canvas Size…", "EDITOR.image.size()")
    pageItem(image, "Crop to Selection", "EDITOR.image.crop()")
    pageItem(image, "Trim to Pixels", "EDITOR.image.trim()")
    image.addItem(.separator())
    pageItem(image, "Flip Left–Right", "EDITOR.image.flipH()")
    pageItem(image, "Flip Top–Bottom", "EDITOR.image.flipV()")
    pageItem(image, "Rotate 90° Clockwise", "EDITOR.image.rotate()")
    imageItem.submenu = image
    let viewItem = NSMenuItem(); main.addItem(viewItem)
    let view = NSMenu(title: "View")
    pageItem(view, "Grid", "document.getElementById('bGrid').click()")
    pageItem(view, "Guides", "document.getElementById('bGuides').click()")
    pageItem(view, "Onion Skin", "document.getElementById('bOnion').click()")
    view.addItem(.separator())
    pageItem(view, "Zoom In", "document.getElementById('zIn').click()", "=")
    pageItem(view, "Zoom Out", "document.getElementById('zOut').click()", "-")
    pageItem(view, "Fit", "EDITOR.fitView()", "0")
    viewItem.submenu = view
    return main
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = delegate.buildMenu()
app.run()
