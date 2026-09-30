import Cocoa
import WebKit
import UniformTypeIdentifiers
import CryptoKit

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
//  - Keeping up to date. Nearly everything Myrling ships is a change to index.html, so
//    the app keeps its own copy of that one file and refreshes it from GitHub Pages.

final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
  private var files: [String: URL] = [:]     // handle id -> the file it stands for
  private var dirs: [String: URL] = [:]      // handle id -> a folder the user chose to save into
  private var dropped: [String: [URL]] = [:]  // name -> the files of that name in the last drop
  private var twice = Set<String>()            // names the last drop carried more than once

  // the page sees nothing bigger than a sheet of sprites; far past that is not a picture
  private static let mostBytes = 64 * 1024 * 1024

  // ids are random so nothing can write through a handle it was never given by guessing
  // its number
  private func newId(_ kind: String) -> String { kind + UUID().uuidString }

  // a new page starts with no grants: handles belong to the page they were handed to
  func forget() {
    files = [:]
    dirs = [:]
    dropped = [:]
    twice = []
  }

  // where the work is: every panel opens here, and lands here again next launch
  private let lastDirKey = "myrlingLastDir"
  private var lastDir: URL? {
    get {
      guard let p = UserDefaults.standard.string(forKey: lastDirKey) else { return nil }
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { return nil }
      return URL(fileURLWithPath: p)
    }
    set { UserDefaults.standard.set(newValue?.path, forKey: lastDirKey) }
  }
  func notePlace(_ url: URL, isDirectory: Bool = false) {
    lastDir = isDirectory ? url : url.deletingLastPathComponent()
  }
  func startPanel(_ panel: NSOpenPanel) {
    if let d = lastDir { panel.directoryURL = d }
  }

  // the native drop layer saw these before the page did; the page claims them by name.
  // Only this drop counts: a name left over from an earlier drop would hand the page a
  // handle onto the wrong file, and Save over would then write into it.
  func noteDrop(_ urls: [URL]) {
    dropped = [:]
    twice = []
    for u in urls {
      if dropped[u.lastPathComponent] != nil { twice.insert(u.lastPathComponent) }
      dropped[u.lastPathComponent, default: []].append(u)
    }
    if let first = urls.first { notePlace(first) }
  }

  // Two files of one name from two folders: the page's File says which it is by its size
  // and its modification time. One that still cannot be told apart gets no handle at all.
  private static func same(_ url: URL, _ body: [String: Any]) -> Bool {
    guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return false }
    if let size = body["size"] as? Double, Double(v.fileSize ?? -1) != size { return false }
    if let ms = body["modified"] as? Double, let date = v.contentModificationDate,
       abs(date.timeIntervalSince1970 * 1000 - ms) >= 1000 { return false }
    return true
  }

  // one plain .png name for a file inside a chosen folder: nothing that climbs out of it,
  // hides in it, or carries characters no one would type
  static func plainName(_ name: String) -> Bool {
    return !name.isEmpty && name.utf8.count <= 255 && !name.hasPrefix(".")
      && name.lowercased().hasSuffix(".png") && !name.contains("/")
      && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }

  private static func bytes(_ body: [String: Any]) -> Data? {
    guard let b64 = body["bytes"] as? String, b64.utf8.count <= mostBytes / 3 * 4 + 4 else { return nil }
    return Data(base64Encoded: b64)
  }

  func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                             replyHandler: @escaping (Any?, String?) -> Void) {
    // only the editor page itself drives the bridge: not a frame inside it, and not
    // anything the window might have been led away to
    guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "file" else {
      replyHandler(nil, "Only the editor page can do that"); return
    }
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
    startPanel(panel)
    panel.begin { resp in
      guard resp == .OK, !panel.urls.isEmpty else { reply(["cancelled": true], nil); return }
      self.notePlace(panel.urls[0])
      var out: [[String: Any]] = []
      for url in panel.urls {
        guard let data = try? Data(contentsOf: url) else { continue }
        let id = self.newId("f")
        self.files[id] = url
        out.append(["id": id, "name": url.lastPathComponent, "bytes": data.base64EncodedString(),
                    "dir": url.deletingLastPathComponent().path])
      }
      reply(["files": out], nil)
    }
  }

  private func claim(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let name = body["name"] as? String, var list = dropped[name] else { reply([:], nil); return }
    if twice.contains(name) { list = list.filter { BridgeHandler.same($0, body) } }
    guard list.count == 1, let url = list.first else { reply([:], nil); return }
    // each file is handed out once
    dropped[name]?.removeAll { $0 == url }
    let id = newId("f")
    files[id] = url
    reply(["id": id, "dir": url.deletingLastPathComponent().path], nil)
  }

  private func pickDir(_ reply: @escaping (Any?, String?) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Save here"
    startPanel(panel)
    panel.begin { resp in
      guard resp == .OK, let url = panel.urls.first else { reply(["cancelled": true], nil); return }
      self.notePlace(url, isDirectory: true)
      let id = self.newId("d")
      self.dirs[id] = url
      reply(["id": id, "name": url.lastPathComponent, "path": url.path], nil)
    }
  }

  private func writeTo(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let dirId = body["dir"] as? String, let dir = dirs[dirId],
          let name = body["name"] as? String, BridgeHandler.plainName(name),
          let data = BridgeHandler.bytes(body) else {
      reply(nil, "Nothing to write"); return
    }
    do {
      try data.write(to: dir.appendingPathComponent(name), options: .atomic)
      notePlace(dir, isDirectory: true)
      reply(["ok": true], nil)
    }
    catch { reply(nil, error.localizedDescription) }
  }

  // the page's PixelLab calls travel natively so WebKit's cross-origin wall never
  // matters. Pinned to api.pixellab.ai and its generate paths; this is not a proxy. The
  // path is plain letters and dashes, so no escaped dots or query can steer it to another
  // endpoint with the key, and a redirect is never followed, so the prompt and the pictures
  // sent with it go to PixelLab or nowhere.
  private lazy var pixellabSession = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
  private func pixellab(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
    guard let path = body["path"] as? String,
          path.range(of: "^/generate-image[a-z0-9-]*$", options: .regularExpression) != nil,
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
    pixellabSession.dataTask(with: req) { data, resp, err in
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
          let data = BridgeHandler.bytes(body) else {
      reply(nil, "Nothing to write"); return
    }
    do { try data.write(to: url, options: .atomic); reply(["ok": true], nil) }
    catch { reply(nil, error.localizedDescription) }
  }
}

// a redirect answered with nothing: the task finishes on the 3xx itself
final class NoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

// WebKit gives the page the dropped files but never their places on disk, so this
// subclass notes the real URLs on the way past and the bridge hands them to the page.
// Every drop is reported, even one with no files on disk in it (a picture dragged out
// of a browser), so the names from an earlier drop never stand in for it.
final class DropCatchingWebView: WKWebView {
  var onFileDrop: (([URL]) -> Void)?
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL]
    onFileDrop?(urls ?? [])
    return super.performDragOperation(sender)
  }
}

// The page carries its own version in one meta tag in its head, so the app can ask any
// copy of index.html how old it is without keeping a note of it somewhere else.
func pageVersion(inHTML html: String) -> String? {
  let head = String(html.prefix(20000))
  guard let tag = head.range(of: "<meta[^>]*myrling-version[^>]*>",
                             options: [.regularExpression, .caseInsensitive]) else { return nil }
  let inside = String(head[tag])
  guard let content = inside.range(of: "content=[\"'][^\"']*[\"']",
                                   options: [.regularExpression, .caseInsensitive]) else { return nil }
  let quoted = String(inside[content]).dropFirst("content=".count)
  let text = String(quoted.dropFirst().dropLast())
  return text.isEmpty ? nil : text
}
func pageVersion(of file: URL) -> String? {
  guard let html = try? String(contentsOf: file, encoding: .utf8) else { return nil }
  return pageVersion(inHTML: html)
}

// Versions are dotted numbers. Compare them piece by piece as numbers, so 2026.9.22.10
// beats 2026.9.22.9 the way a plain string compare would not; a missing piece is zero,
// an empty one too, so 2026..1 is 2026.0.1 and not 2026.1.
func versionIsNewer(_ a: String, than b: String) -> Bool {
  let mine = a.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
  let theirs = b.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
  for i in 0..<max(mine.count, theirs.count) {
    let x = i < mine.count ? mine[i] : 0
    let y = i < theirs.count ? theirs[i] : 0
    if x != y { return x > y }
  }
  return false
}

// Where the live page lives. The app bundle is code-signed, so nothing may ever be
// written inside it; the page the window actually loads sits in Application Support at
// the same path every launch, and that one file is what an update replaces. The page's
// kept sprites are safe across the move: WebKit gives every file:// page the single
// origin "file://", so localStorage does not care which folder the page came from.
final class PageStore {
  let file: URL
  private let bundled: URL?

  init() {
    let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: true))
      ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
    let dir = support.appendingPathComponent("Myrling/page", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    file = dir.appendingPathComponent("index.html")
    bundled = Bundle.main.url(forResource: "index", withExtension: "html")
  }

  var version: String { pageVersion(of: file) ?? "0" }

  // The page to load. A freshly installed app has to beat a stale cached page, so the
  // bundled copy wins whenever it is newer, or whenever there is nothing cached yet.
  func livePage() -> URL {
    guard let bundled = bundled else { return file }
    let there = FileManager.default.fileExists(atPath: file.path)
    if there && !versionIsNewer(pageVersion(of: bundled) ?? "0", than: pageVersion(of: file) ?? "") {
      return file
    }
    do {
      try Data(contentsOf: bundled).write(to: file, options: .atomic)
      return file
    } catch {
      NSLog("Myrling: could not put the page in place (%@); running from the bundle", "\(error)")
      return bundled
    }
  }

  // An update lands whole or not at all, so a half-written page can never be loaded
  func replace(with data: Data) throws { try data.write(to: file, options: .atomic) }
}

// Where an update may come from. The app only ever builds `live`, so the host is fixed
// at the one that publishes Myrling; it is a field rather than a constant so a test can
// point the very same code at a server of its own.
struct UpdateSource {
  let manifest: URL
  var host: String { manifest.host ?? "" }
  var scheme: String { manifest.scheme ?? "" }
  static let live = UpdateSource(
    manifest: URL(string: "https://josiah-turnquist.github.io/myrling-sprite-editor/update.json")!)
}

// What one check found out about the page
enum PageNews {
  case current             // what is in hand is the newest there is
  case updated(String)     // a page that checked out is in the cache, ready next launch
  case failed(String)      // nothing was written; the reason is for the log
}
// ...and about the app around it, which cannot replace itself
struct AppNews { let version: String; let url: URL; let notes: String? }

final class Updater: NSObject, URLSessionTaskDelegate {
  // the one key that says a page is really ours: Ed25519, raw 32 bytes, base64
  private static let publicKey = "TSNuDQVNl3TLwrxYe4mkB+nThjF9lBbhX32niIRnXgs="
  // the page is a few hundred kilobytes; anything near this is not the page
  private static let mostBytes = 32 * 1024 * 1024

  let source: UpdateSource
  let store: PageStore
  private var busy = false
  // a second ask while a check is out (Check for Updates… just as the quiet launch
  // check runs) waits for that check's answer rather than being told it failed
  private var waiting: [(PageNews, AppNews?) -> Void] = []
  // ephemeral: a check keeps no cache and no cookies of its own between runs
  private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

  init(store: PageStore, source: UpdateSource = .live) {
    self.store = store
    self.source = source
  }

  // the manifest and the page it names both have to come from the one host, over the one
  // scheme; a redirect off it is a different publisher, so it is refused, not followed
  private func allowed(_ url: URL) -> Bool { url.scheme == source.scheme && url.host == source.host }
  func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(newRequest.url.map(allowed) == true ? newRequest : nil)
  }

  // The whole check, from the manifest to a page sitting in the cache. It answers on the
  // main thread and never blocks the caller; every way it can go wrong ends in .failed.
  func check(done: @escaping (PageNews, AppNews?) -> Void) {
    if busy { waiting.append(done); return }
    busy = true
    let finish: (PageNews, AppNews?) -> Void = { news, app in
      DispatchQueue.main.async {
        self.busy = false
        let others = self.waiting
        self.waiting = []
        done(news, app)
        others.forEach { $0(news, app) }
      }
    }
    fetch(source.manifest) { data, why in
      guard let data = data else { finish(.failed(why ?? "no answer"), nil); return }
      guard let all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        finish(.failed("the manifest was not JSON"), nil); return
      }
      let app = Updater.appNews(from: all["app"] as? [String: Any])
      guard let page = all["page"] as? [String: Any],
            let want = page["version"] as? String,
            let text = page["url"] as? String, let url = URL(string: text),
            let sha = (page["sha256"] as? String)?.lowercased(),
            let signature = page["signature"] as? String else {
        finish(.failed("the manifest said nothing usable about the page"), app); return
      }
      guard versionIsNewer(want, than: self.store.version) else { finish(.current, app); return }
      self.fetch(url) { body, why in
        guard let body = body else { finish(.failed(why ?? "the page did not arrive"), app); return }
        if let trouble = self.trouble(with: body, version: want, sha: sha, signature: signature) {
          finish(.failed(trouble), app); return
        }
        do { try self.store.replace(with: body) }
        catch { finish(.failed("could not keep the new page: \(error)"), app); return }
        finish(.updated(want), app)
      }
    }
  }

  private func fetch(_ url: URL, done: @escaping (Data?, String?) -> Void) {
    guard allowed(url) else { done(nil, "\(url.absoluteString) is not on " + source.host); return }
    var req = URLRequest(url: url)
    req.timeoutInterval = 10
    req.cachePolicy = .reloadIgnoringLocalCacheData
    session.dataTask(with: req) { data, resp, err in
      if let err = err { done(nil, err.localizedDescription); return }
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      guard code >= 200, code < 300 else { done(nil, "the server said \(code)"); return }
      guard let data = data, !data.isEmpty else { done(nil, "nothing came back"); return }
      guard data.count <= Updater.mostBytes else { done(nil, "that was far too big to be the page"); return }
      done(data, nil)
    }.resume()
  }

  // The point of the whole exercise. The page drives a bridge that opens panels and
  // writes real files, so a page is only ever kept when it is byte for byte the page the
  // signature covers and the signature is ours; nil here means there is no trouble.
  private func trouble(with body: Data, version: String, sha: String, signature: String) -> String? {
    let got = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    guard got == sha else { return "the page did not match the sha256 the manifest claimed" }
    guard let raw = Data(base64Encoded: Updater.publicKey),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
      return "the key built into this app is broken"
    }
    guard let sig = Data(base64Encoded: signature) else { return "the signature was not base64" }
    let signed = Data(("myrling-page\n" + version + "\n" + sha).utf8)
    guard key.isValidSignature(sig, for: signed) else { return "the signature did not check out" }
    // and it has to admit to being the version the manifest sold, or the app would keep
    // fetching the same page forever without ever counting as up to date
    guard let html = String(data: body, encoding: .utf8) else { return "the page was not text" }
    guard pageVersion(inHTML: html) == version else { return "the page calls itself a different version" }
    return nil
  }

  // A new app cannot install itself from in here, so the most this does is point at the
  // release page. Pinned to https and this project's own releases on GitHub, which is the
  // only place Myrling is released: this half of the manifest is not signed, so it must
  // not be able to send anyone to somebody else's download.
  private static let releases = "/josiah-turnquist/myrling-sprite-editor/releases"
  private static func appNews(from app: [String: Any]?) -> AppNews? {
    guard let app = app, let version = app["version"] as? String,
          let text = app["url"] as? String, let url = URL(string: text),
          url.scheme == "https", url.host == "github.com", url.port == nil,
          url.path.lowercased() == releases || url.path.lowercased().hasPrefix(releases + "/"),
          let mine = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          versionIsNewer(version, than: mine) else { return nil }
    return AppNews(version: version, url: url, notes: app["notes"] as? String)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSToolbarDelegate {
  var window: NSWindow!
  var webView: DropCatchingWebView!
  let store = PageStore()
  lazy var updater = Updater(store: store)
  let bridge = BridgeHandler()
  // the one page this window is for; set by load(), and the only place it may navigate
  private var page: URL?
  private let autoKey = "myrlingAutoUpdate"
  private let toldKey = "myrlingToldAboutApp"

  // the title bar toolbar: each button presses one of the page's own image operations,
  // so the toolbar and the Image menu in the page can never disagree
  struct Tool { let id: String; let label: String; let symbol: String; let tip: String; let js: String }
  let tools: [Tool] = [
    Tool(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", tip: "Undo (Cmd+Z)", js: "EDITOR.undo()"),
    Tool(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", tip: "Redo (Shift+Z)", js: "EDITOR.redo()"),
    Tool(id: "size", label: "Canvas size", symbol: "arrow.up.left.and.arrow.down.right", tip: "Grow, shrink or scale the canvas", js: "EDITOR.image.size()"),
    Tool(id: "crop", label: "Crop", symbol: "crop", tip: "Crop to the selected box", js: "EDITOR.image.crop()"),
    Tool(id: "trim", label: "Trim", symbol: "rectangle.dashed", tip: "Trim away the empty edges", js: "EDITOR.image.trim()"),
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
    ucc.addScriptMessageHandler(bridge, contentWorld: .page, name: "eldermyr")

    webView = DropCatchingWebView(frame: .zero, configuration: config)
    webView.onFileDrop = { [bridge] in bridge.noteDrop($0) }
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

    // always the copy in Application Support, never the one sealed inside the bundle
    load(store.livePage())
    NSApp.activate(ignoringOtherApps: true)

    // the update can wait: the window is up and drawable first, and nothing about
    // launching depends on the network being there at all
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      guard let self = self, UserDefaults.standard.bool(forKey: self.autoKey) else { return }
      self.runCheck(quiet: true)
    }
    // and again every few hours, so an app left open for days still hears about fixes.
    // The check is quiet and cheap: it downloads the page only when there is a new one.
    Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
      guard let self = self, UserDefaults.standard.bool(forKey: self.autoKey) else { return }
      self.runCheck(quiet: true)
    }
  }

  @objc func checkForUpdates(_ sender: Any?) { runCheck(quiet: false) }

  @objc func toggleAutoUpdate(_ sender: NSMenuItem) {
    let on = !UserDefaults.standard.bool(forKey: autoKey)
    UserDefaults.standard.set(on, forKey: autoKey)
    sender.state = on ? .on : .off
  }

  // A quiet check is the one that runs itself at launch: it keeps to the log unless it
  // has something to say. A check the user asked for answers either way.
  private func runCheck(quiet: Bool) {
    updater.check { [weak self] news, app in
      guard let self = self else { return }
      switch news {
      case .current:
        if !quiet { self.tell("Myrling is up to date.", "This is page version " + self.store.version + ".") }
      case .updated(let version):
        NSLog("Myrling: page %@ is in place for next launch", version)
        if quiet { self.sayInPage("Myrling updated to " + version + ". It will be ready next time you open it.") }
        else { self.offerReload(version) }
      case .failed(let why):
        NSLog("Myrling: nothing updated (%@)", why)
        if !quiet { self.tell("Myrling could not check for updates.", why) }
      }
      if let app = app { self.mention(app, quiet: quiet) }
    }
  }

  // the page has a status line of its own, so a quiet check speaks through that and
  // nowhere else. An older page that has no say() must not throw here. The words go in
  // as an argument, never pasted into the script, so nothing in them can run.
  private func sayInPage(_ words: String) {
    webView.callAsyncJavaScript("if (typeof say === 'function') say(words, 'good')",
                                arguments: ["words": words], in: nil, in: .page, completionHandler: nil)
  }

  private func tell(_ head: String, _ body: String) {
    let alert = NSAlert()
    alert.messageText = head
    alert.informativeText = body
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // updates wait for the next launch, because the user may be halfway through a drawing;
  // having asked for the check, though, they can have it now if they want it
  private func offerReload(_ version: String) {
    let alert = NSAlert()
    alert.messageText = "Myrling updated to " + version + "."
    alert.informativeText = "It will be ready next time you open it, or you can pick it up now. Your sprites are kept either way."
    alert.addButton(withTitle: "Reload Now")
    alert.addButton(withTitle: "Later")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    load(store.file)
  }

  private func load(_ url: URL) {
    page = url
    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }

  // the app around the page has to be replaced by hand, so this only points the way.
  // Unasked, it raises any one version once and then stays out of the way.
  private func mention(_ app: AppNews, quiet: Bool) {
    if quiet {
      if UserDefaults.standard.string(forKey: toldKey) == app.version { return }
      UserDefaults.standard.set(app.version, forKey: toldKey)
    }
    let mine = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let alert = NSAlert()
    alert.messageText = "Myrling " + app.version + " is out."
    var body = "This copy is version " + mine + ". A whole new app has to be downloaded and put in place by hand."
    if let notes = app.notes, !notes.isEmpty { body = notes + "\n\n" + body }
    alert.informativeText = body
    alert.addButton(withTitle: "Download")
    alert.addButton(withTitle: "Later")
    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(app.url) }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

  // The page writes its kept work half a second after each change, and quitting takes
  // WebKit down without the beforeunload a browser tab would get, so a stroke made just
  // before Cmd+Q, or before the window was closed, was lost. Hand the page that event
  // first: its own handler writes only when something is waiting to be written.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let webView = webView else { return .terminateNow }
    var answered = false
    // run loop timers, not the main queue: AppKit waits for the answer in a modal run
    // loop, and when the quit began inside a main-queue block that queue cannot drain
    func after(_ seconds: TimeInterval) {
      RunLoop.main.add(Timer(timeInterval: seconds, repeats: false) { _ in
        guard !answered else { return }
        answered = true
        sender.reply(toApplicationShouldTerminate: true)
      }, forMode: .common)
    }
    // and a moment after the page answers, for WebKit to carry what was written to disk
    webView.evaluateJavaScript("window.dispatchEvent(new Event('beforeunload')); true") { _, _ in after(0.3) }
    // a page that never answers must not keep the app from quitting
    after(3)
    return .terminateLater
  }

  // a fresh page starts without the old page's file grants
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { bridge.forget() }

  // if WebKit's page process dies (memory, a crash), the window would sit blank until
  // relaunched; the kept work is in the page's store, so loading it again brings it back
  // (once in a while: a page that takes its process down as it loads must not loop)
  private var lastRevival = Date.distantPast
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    NSLog("Myrling: the page's process ended")
    guard let page = page, Date().timeIntervalSince(lastRevival) > 30 else { return }
    lastRevival = Date()
    load(page)
  }

  // the plain <input type=file>, the page's fallback when the bridge is missing
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.png]
    if let d = UserDefaults.standard.string(forKey: "myrlingLastDir") { panel.directoryURL = URL(fileURLWithPath: d) }
    panel.begin { resp in
      if resp == .OK, let first = panel.urls.first {
        UserDefaults.standard.set(first.deletingLastPathComponent().path, forKey: "myrlingLastDir")
      }
      completionHandler(resp == .OK ? panel.urls : nil)
    }
  }

  // Export frames clicks <a download> links; WebKit hands those over as downloads.
  // Otherwise the window only ever shows the editor page: anywhere else a link or a
  // stray drop might lead would get the bridge and every file the page was granted, so
  // web links open in the browser instead and anything else goes nowhere.
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
    guard navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url else {
      decisionHandler(.allow); return
    }
    if url.isFileURL, let page = page, url.standardizedFileURL.path == page.standardizedFileURL.path {
      decisionHandler(.allow); return
    }
    if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    decisionHandler(.cancel)
  }
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    var url = dir.appendingPathComponent(suggestedFilename)
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
    var n = 1
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base) (\(n))\(ext)")
      n += 1
    }
    completionHandler(url)
  }

  // the menu bar drives the page: each item just presses the page's own controls
  private func pageItem(_ menu: NSMenu, _ title: String, _ js: String, _ key: String = "",
                        pageHasKey: Bool = false) {
    let item = NSMenuItem(title: title, action: #selector(runPageAction(_:)), keyEquivalent: key)
    item.target = self
    item.representedObject = js
    item.tag = pageHasKey ? 1 : 0
    menu.addItem(item)
  }
  // The page answers =, - and 0 itself, with Cmd or without, and lets the key go on
  // past it, so WebKit hands it to the menu as well and one press used to zoom two
  // steps. For those items the menu stands aside when its own key equivalent is what
  // chose it, and acts when it was chosen any other way.
  @objc func runPageAction(_ sender: NSMenuItem) {
    if sender.tag == 1, let ev = NSApp.currentEvent, ev.type == .keyDown, ev.modifierFlags.contains(.command),
       ev.charactersIgnoringModifiers == sender.keyEquivalent { return }
    if let js = sender.representedObject as? String { webView.evaluateJavaScript(js) }
  }

  func buildMenu() -> NSMenu {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Myrling",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
    check.target = self
    appMenu.addItem(check)
    let auto = NSMenuItem(title: "Check for Updates Automatically",
                          action: #selector(toggleAutoUpdate(_:)), keyEquivalent: "")
    auto.target = self
    auto.state = UserDefaults.standard.bool(forKey: autoKey) ? .on : .off
    appMenu.addItem(auto)
    appMenu.addItem(.separator())
    pageItem(appMenu, "Settings…", "EDITOR.showKeys()", ",")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Myrling", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let others = appMenu.addItem(withTitle: "Hide Others",
                                 action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    others.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(withTitle: "Show All",
                    action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
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
    pageItem(image, "Trim Empty Edges", "EDITOR.image.trim()")
    image.addItem(.separator())
    pageItem(image, "Flip Left–Right", "EDITOR.image.flipH()")
    pageItem(image, "Flip Top–Bottom", "EDITOR.image.flipV()")
    pageItem(image, "Rotate 90° Clockwise", "EDITOR.image.rotate()")
    image.addItem(.separator())
    pageItem(image, "Tilesheet Grid…", "EDITOR.image.sheet()")
    pageItem(image, "Split Sheet into Sprites…", "EDITOR.image.split()")
    pageItem(image, "Add Sprites to a Sheet…", "EDITOR.image.add()")
    imageItem.submenu = image
    let viewItem = NSMenuItem(); main.addItem(viewItem)
    let view = NSMenu(title: "View")
    pageItem(view, "Grid", "document.getElementById('bGrid').click()")
    pageItem(view, "Guides", "document.getElementById('bGuides').click()")
    pageItem(view, "Onion Skin", "document.getElementById('bOnion').click()")
    view.addItem(.separator())
    pageItem(view, "Zoom In", "document.getElementById('zIn').click()", "=", pageHasKey: true)
    pageItem(view, "Zoom Out", "document.getElementById('zOut').click()", "-", pageHasKey: true)
    pageItem(view, "Fit", "EDITOR.fitView()", "0", pageHasKey: true)
    viewItem.submenu = view
    // Close is Cmd+W as everywhere else; with one window it quits, which saves first
    let windowItem = NSMenuItem(); main.addItem(windowItem)
    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    window.addItem(.separator())
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = window
    NSApp.windowsMenu = window
    return main
  }
}

let app = NSApplication.shared
// the app looks after its own page unless the user says otherwise; the menu is built
// below and reads this, so it has to be settled first
UserDefaults.standard.register(defaults: ["myrlingAutoUpdate": true])
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.mainMenu = delegate.buildMenu()
app.run()
