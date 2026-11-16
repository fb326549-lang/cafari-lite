// Cafari Lite -- the small, open part of Cafari: a web view on the CarPlay
// screen, and nothing else. The full app, which also casts to Chromecast and
// AirPlay receivers, and its sideload builds, are at
// https://github.com/rPlayAI/cafari-public
//
// The whole app: a web view pointed at YouTube's mobile site, plus the few
// controls a passenger needs. Nothing private, nothing clever -- the trick is
// entirely in which scene this view controller happens to be living in.

import UIKit
import WebKit

final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
  private let home = URL(string: "https://m.youtube.com")!
  private let showsStatus: Bool
  private var webView: WKWebView!
  private var statusLabel: UILabel?
  // Whether the last page was a sign-in page, so finishing on YouTube after it
  // means an account just changed. See webView(_:didFinish:).
  private var wasSigningIn = false
  private var loggedCarLayout = false
  private var drivingCover: UIView?

  private static let remoteBootstrap = """
  (() => {
    if (window.__myCarRemote) return;
    const state = { x: window.innerWidth / 2, y: window.innerHeight / 2, cursor: null };
    const ensureCursor = () => {
      if (!document.documentElement) return;
      if (!state.cursor || !document.documentElement.contains(state.cursor)) {
        const cursor = document.createElement('div');
        cursor.id = 'mycar-remote-pointer';
        cursor.setAttribute('aria-hidden', 'true');
        cursor.style.cssText = 'position:fixed;left:0;top:0;width:22px;height:22px;border:2px solid #fff;border-radius:50%;background:rgba(0,122,255,.45);box-shadow:0 0 0 2px rgba(0,0,0,.55),0 2px 8px rgba(0,0,0,.45);z-index:2147483647;pointer-events:none;transform:translate(-50%,-50%);';
        document.documentElement.appendChild(cursor);
        state.cursor = cursor;
      }
      state.cursor.style.left = state.x + 'px';
      state.cursor.style.top = state.y + 'px';
    };
    state.move = (dx, dy) => {
      state.x = Math.max(8, Math.min(window.innerWidth - 8, state.x + dx * window.innerWidth));
      state.y = Math.max(8, Math.min(window.innerHeight - 8, state.y + dy * window.innerHeight));
      ensureCursor();
    };
    state.reset = () => {
      state.x = window.innerWidth / 2;
      state.y = window.innerHeight / 2;
      ensureCursor();
    };
    state.tap = () => {
      ensureCursor();
      const hit = document.elementFromPoint(state.x, state.y);
      if (!hit) return;
      const target = hit.closest('button,a,[role="button"],input,textarea,select,[tabindex],[contenteditable="true"],video') || hit;
      const rect = target.getBoundingClientRect();
      const init = {
        bubbles: true, cancelable: true, view: window,
        clientX: state.x, clientY: state.y,
        screenX: state.x, screenY: state.y,
        button: 0, buttons: 1
      };
      try {
        target.dispatchEvent(new PointerEvent('pointerdown', Object.assign({}, init, { pointerId: 1, pointerType: 'mouse', isPrimary: true })));
        target.dispatchEvent(new MouseEvent('mousedown', init));
        target.dispatchEvent(new PointerEvent('pointerup', Object.assign({}, init, { pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 0 })));
        target.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, init, { buttons: 0 })));
        target.dispatchEvent(new MouseEvent('click', Object.assign({}, init, { buttons: 0 })));
        if (target instanceof HTMLElement && target.matches('button,a,input,[role="button"],[tabindex]')) target.click();
      } catch (_) {}
    };
    state.scroll = (dx, dy) => {
      const deltaX = -dx * window.innerWidth * 1.1;
      const deltaY = -dy * window.innerHeight * 1.1;
      let node = document.elementFromPoint(state.x, state.y);
      let scroller = null;
      while (node && node !== document.body && node !== document.documentElement) {
        const style = window.getComputedStyle(node);
        const canScrollY = /(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight;
        const canScrollX = /(auto|scroll)/.test(style.overflowX) && node.scrollWidth > node.clientWidth;
        if ((deltaY !== 0 && canScrollY) || (deltaX !== 0 && canScrollX)) { scroller = node; break; }
        node = node.parentElement;
      }
      if (scroller) {
        scroller.scrollBy(deltaX, deltaY);
      } else {
        window.scrollBy(deltaX, deltaY);
      }
      ensureCursor();
    };
    state.insertText = (text) => {
      let target = document.activeElement;
      if (!target || target === document.body || target === document.documentElement) {
        const hit = document.elementFromPoint(state.x, state.y);
        target = hit && hit.closest('input,textarea,[contenteditable="true"]');
      }
      if (!target) return;
      if (target.matches && target.matches('input,textarea')) {
        const proto = target.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        const next = (target.value || '') + text;
        if (setter) setter.call(target, next); else target.value = next;
        target.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
        target.dispatchEvent(new Event('change', { bubbles: true }));
      } else if (target.isContentEditable) {
        target.focus();
        document.execCommand('insertText', false, text);
      }
    };
    window.__myCarRemote = state;
    ensureCursor();
    window.addEventListener('pageshow', ensureCursor);
  })();
  """

  init(showsStatus: Bool) {
    self.showsStatus = showsStatus
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    Log.write("viewDidLoad showsStatus=\(showsStatus)")
    // The car window sits behind video, so black. The phone window gets a
    // colour no system background ever is: in dark mode systemBackground is
    // itself black, so it could not distinguish "our view is up and the page
    // did not draw" from "our window is not on screen", which was the point.
    view.backgroundColor = showsStatus
      ? UIColor(red: 0.07, green: 0.11, blue: 0.22, alpha: 1)
      : .black

    let configuration = WKWebViewConfiguration()
    // Play in place rather than handing off to the full-screen system player,
    // which on the car screen would put the video where we cannot see it.
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.addUserScript(
      WKUserScript(source: Self.remoteBootstrap, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.scrollView.contentInsetAdjustmentBehavior = .always
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)

    let bar = makeToolbar()
    bar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bar)

    // On the phone the toolbar sits above the page. On the car it floats over
    // it: the head unit window measured 467x263 points, and a 56 point bar was
    // taking a fifth of the height away from the video.
    if showsStatus {
      NSLayoutConstraint.activate([
        bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    } else {
      bar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
      bar.layer.cornerRadius = 10
      bar.clipsToBounds = true
      // No constraints on the web view here: viewDidLayoutSubviews sizes it.
      webView.translatesAutoresizingMaskIntoConstraints = true
      NSLayoutConstraint.activate([
        bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
        bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
      ])
    }

    Log.write("loading \(home.absoluteString)")
    webView.load(URLRequest(url: home))

    if showsStatus {
      NotificationCenter.default.addObserver(
        self, selector: #selector(carStateChanged),
        name: .cafariLiteCarConnected, object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(carStateChanged),
        name: .cafariLiteCarDisconnected, object: nil)
    } else {
      // The car window cannot be typed into -- CarPlay offers no keyboard for
      // a web view -- so signing in happens on the phone. Both windows share
      // the app's cookie store, so the car only needs to reload to pick the
      // session up.
      NotificationCenter.default.addObserver(
        self, selector: #selector(accountChanged),
        name: .cafariLiteAccountChanged, object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(sendToCarRequested(_:)),
        name: .cafariLiteSendToCar, object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(handleRemoteCommand(_:)),
        name: .myCarRemoteCommand, object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(settingsChanged),
        name: .cafariLiteSettingsChanged, object: nil)
      NotificationCenter.default.addObserver(
        self, selector: #selector(drivingStateChanged),
        name: CarGate.stateChanged, object: nil)
      if Settings.playOnlyWhenParked { CarGate.shared.start() }
    }
  }

  private func makeToolbar() -> UIView {
    let container = UIStackView()
    container.axis = .horizontal
    container.alignment = .center
    container.spacing = 16
    container.isLayoutMarginsRelativeArrangement = true
    container.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    container.backgroundColor = .secondarySystemBackground

    func button(_ systemName: String, _ action: Selector) -> UIButton {
      let b = UIButton(type: .system)
      b.setImage(UIImage(systemName: systemName), for: .normal)
      b.addTarget(self, action: action, for: .touchUpInside)
      return b
    }

    container.addArrangedSubview(button("chevron.backward", #selector(goBack)))
    container.addArrangedSubview(button("chevron.forward", #selector(goForward)))
    container.addArrangedSubview(button("house", #selector(goHome)))
    container.addArrangedSubview(button("arrow.clockwise", #selector(reload)))
    if showsStatus {
      // Hand whatever the phone is showing to the car window. The car cannot
      // be typed into, so finding something is the phone's job and this is how
      // the result gets across.
      let cast = button("tv", #selector(sendToCar))
      cast.accessibilityLabel = "Send to car screen"
      container.addArrangedSubview(cast)
      let gear = button("gearshape", #selector(showSettings))
      gear.accessibilityLabel = "Settings"
      container.addArrangedSubview(gear)
      let close = button("xmark", #selector(closePhoneBrowser))
      close.accessibilityLabel = "Close phone browser"
      container.addArrangedSubview(close)
    }

    if showsStatus {
      let label = UILabel()
      label.font = .preferredFont(forTextStyle: .footnote)
      label.textColor = .secondaryLabel
      label.textAlignment = .right
      label.adjustsFontSizeToFitWidth = true
      statusLabel = label
      container.addArrangedSubview(label)
      updateStatus()
    }
    return container
  }

  @objc private func goBack() { webView.goBack() }
  @objc private func goForward() { webView.goForward() }
  @objc private func closePhoneBrowser() { dismiss(animated: true) }

  @objc private func handleRemoteCommand(_ notification: Notification) {
    guard !showsStatus, let info = notification.userInfo,
          let type = info["type"] as? String else { return }
    switch type {
    case "navigate":
      guard let raw = info["url"] as? String,
            let url = URL(string: raw),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
      webView.load(URLRequest(url: url))
    case "back":
      webView.goBack()
    case "forward":
      webView.goForward()
    case "home":
      webView.load(URLRequest(url: home))
    case "reload":
      webView.reload()
    case "move":
      let dx = (info["dx"] as? NSNumber)?.doubleValue ?? 0
      let dy = (info["dy"] as? NSNumber)?.doubleValue ?? 0
      evaluateRemote("window.__myCarRemote && window.__myCarRemote.move(\(dx), \(dy));")
    case "tap":
      evaluateRemote("window.__myCarRemote && window.__myCarRemote.tap();")
    case "scroll":
      let dx = (info["dx"] as? NSNumber)?.doubleValue ?? 0
      let dy = (info["dy"] as? NSNumber)?.doubleValue ?? 0
      evaluateRemote("window.__myCarRemote && window.__myCarRemote.scroll(\(dx), \(dy));")
    case "insertText":
      guard let text = info["text"] as? String,
            let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
            let json = String(data: data, encoding: .utf8) else { return }
      evaluateRemote("window.__myCarRemote && window.__myCarRemote.insertText(\(json));")
    case "resetPointer":
      evaluateRemote("window.__myCarRemote && window.__myCarRemote.reset();")
    default:
      break
    }
  }

  private func evaluateRemote(_ javaScript: String) {
    webView.evaluateJavaScript(javaScript) { _, error in
      if let error { Log.write("remote command failed: \(error.localizedDescription)") }
    }
  }
  @objc private func reload() { webView.reload() }
  @objc private func goHome() { webView.load(URLRequest(url: home)) }

  @objc private func showSettings() {
    let sheet = UIAlertController(title: "Car screen", message: nil,
                                  preferredStyle: .actionSheet)
    let nativeOn = Settings.carNativeResolution
    sheet.addAction(UIAlertAction(
      title: (nativeOn ? "✓ " : "") + "Use the car's own resolution",
      style: .default) { _ in
        Settings.carNativeResolution = !nativeOn
        NotificationCenter.default.post(name: .cafariLiteSettingsChanged, object: nil)
      })
    let borderOn = Settings.debugBorder
    sheet.addAction(UIAlertAction(
      title: (borderOn ? "✓ " : "") + "Show the debug border",
      style: .default) { _ in
        Settings.debugBorder = !borderOn
        NotificationCenter.default.post(name: .cafariLiteSettingsChanged, object: nil)
      })
    let parkedOn = Settings.playOnlyWhenParked
    sheet.addAction(UIAlertAction(
      title: (parkedOn ? "✓ " : "") + "Play only when parked",
      style: .default) { _ in
        Settings.playOnlyWhenParked = !parkedOn
        NotificationCenter.default.post(name: .cafariLiteSettingsChanged, object: nil)
      })
    let sidebarOn = Settings.avoidSidebar
    sheet.addAction(UIAlertAction(
      title: (sidebarOn ? "✓ " : "") + "Keep clear of the sidebar",
      style: .default) { _ in
        Settings.avoidSidebar = !sidebarOn
        NotificationCenter.default.post(name: .cafariLiteSettingsChanged, object: nil)
      })
    sheet.addAction(UIAlertAction(title: "Done", style: .cancel))
    sheet.popoverPresentationController?.sourceView = view
    sheet.popoverPresentationController?.sourceRect =
      CGRect(x: view.bounds.midX, y: 60, width: 1, height: 1)
    present(sheet, animated: true)
  }

  @objc private func sendToCar() {
    guard let url = webView.url else { return }
    // Cafari sends the car a VIDEO, not a page. Do the same: when the phone is
    // on a YouTube video, hand the car the bare player for that video instead
    // of the whole site. The car window then holds nothing but the picture, at
    // the panel's own size, with no page layout to crop it.
    let destination = Self.playerURL(for: url) ?? url
    Log.write("sendToCar \(url.absoluteString) -> \(destination.absoluteString)")
    NotificationCenter.default.post(
      name: .cafariLiteSendToCar, object: nil, userInfo: ["url": destination])
    let connected = UIApplication.shared.connectedScenes.contains { scene in
      scene.session.role == cafariLiteCarPlayRole
    }
    statusLabel?.text = connected ? "Sent to the car" : "No car screen to send to"
  }

  /// The bare player for a YouTube link, or nil if this is not one. Handles
  /// the watch, short-link and shorts forms.
  static func playerURL(for url: URL) -> URL? {
    guard let host = url.host?.lowercased() else { return nil }
    var videoID: String?
    if host.contains("youtu.be") {
      videoID = url.pathComponents.dropFirst().first
    } else if host.contains("youtube.com") {
      if url.path.hasPrefix("/shorts/") {
        videoID = url.pathComponents.dropFirst(2).first
      } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
        videoID = items.first { $0.name == "v" }?.value
      }
    }
    guard let id = videoID, !id.isEmpty else { return nil }
    // playsinline keeps it in our window rather than handing it to the system
    // player, which on the car screen would put it somewhere we cannot see.
    return URL(string: "https://www.youtube.com/embed/\(id)?autoplay=1&playsinline=1&rel=0")
  }

  func webView(_ webView: WKWebView,
               createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction,
               windowFeatures: WKWindowFeatures) -> WKWebView? {
    // Open target=_blank links in this browser instead of a new, invisible window.
    if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
      webView.load(URLRequest(url: url))
    }
    return nil
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
               withError error: Error) {
    showLoadFailure(error)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    showLoadFailure(error)
  }

  private func showLoadFailure(_ error: Error) {
    Log.write("load FAILED: \(error.localizedDescription)")
    // A page that does not load used to leave an empty view and no clue.
    let label = UILabel()
    label.text = error.localizedDescription
    label.textColor = .white
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .body)
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
  }

  @objc private func carStateChanged() { updateStatus() }

  @objc private func settingsChanged() {
    loggedCarLayout = false
    view.setNeedsLayout()
    if Settings.playOnlyWhenParked {
      CarGate.shared.start()
    } else {
      CarGate.shared.stop()
    }
    drivingStateChanged()
  }

  @objc private func drivingStateChanged() {
    let blocked = Settings.playOnlyWhenParked && CarGate.shared.isMoving
    blocked ? showDrivingCover() : hideDrivingCover()
  }

  private func showDrivingCover() {
    // Stop the sound as well as the picture: a video the driver can hear is
    // still a video the driver is following.
    webView.evaluateJavaScript(
      "document.querySelectorAll('video').forEach(v => v.pause())", completionHandler: nil)
    guard drivingCover == nil else { return }
    let cover = UIView()
    cover.backgroundColor = .black
    cover.translatesAutoresizingMaskIntoConstraints = false
    let label = UILabel()
    label.text = "Paused while the car is moving"
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .headline)
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    view.addSubview(cover)
    NSLayoutConstraint.activate([
      cover.topAnchor.constraint(equalTo: view.topAnchor),
      cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      cover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 16),
    ])
    drivingCover = cover
    Log.write("car gate: covered the car screen")
  }

  private func hideDrivingCover() {
    guard let cover = drivingCover else { return }
    cover.removeFromSuperview()
    drivingCover = nil
    Log.write("car gate: uncovered the car screen")
  }

  @objc private func sendToCarRequested(_ note: Notification) {
    guard let url = note.userInfo?["url"] as? URL else { return }
    webView.load(URLRequest(url: url))
  }

  @objc private func accountChanged() {
    // Never interrupt something that is playing on the car screen.
    webView.evaluateJavaScript(
      "!!document.querySelector('video') && !document.querySelector('video').paused"
    ) { [weak self] playing, _ in
      if (playing as? Bool) == true { return }
      self?.webView.reload()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    let screen = view.window?.windowScene?.screen
    Log.write("viewDidAppear view=\(view.bounds.size) web=\(webView.bounds.size) "
      + "window=\(view.window?.bounds.size ?? .zero) "
      + "screen=\(screen?.bounds.size ?? .zero) scale=\(screen?.scale ?? 0) "
      + "native=\(screen?.nativeBounds.size ?? .zero)")
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard !showsStatus else { return }  // the phone window uses constraints
    layoutCarWebView()
  }

  // What Cafari does for the car display: take the head unit's OWN resolution
  // and work in it, instead of the point-sized window iOS hands over. The
  // window measured 467x263 points on a 1280x720 panel, so the page was being
  // laid out as if for a phone and the video came out cropped.
  //
  // The web view is given the panel's pixel size as its bounds -- so the page
  // sees a 1280x720 viewport and lays out for it -- then scaled down to fill
  // the window. One page pixel lands on one panel pixel, so nothing is lost.
  private func layoutCarWebView() {
    // The head unit reports its sidebar as a safe-area inset, so the area the
    // page may use is the window minus that -- the same rule Cafari applies to
    // the video it puts on the car. Without it the left edge of the picture
    // sits under the sidebar.
    let bounds = Settings.avoidSidebar ? view.safeAreaLayoutGuide.layoutFrame
                                       : view.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }

    webView.layer.borderColor = UIColor.systemGreen.cgColor
    webView.layer.borderWidth = Settings.debugBorder ? 3 : 0

    guard Settings.carNativeResolution,
          let screen = view.window?.windowScene?.screen else {
      webView.transform = .identity
      webView.frame = bounds
      return
    }
    let native = screen.nativeBounds.size
    // nativeBounds is in the screen's natural orientation; the car panel is
    // landscape, so take the long edge as the width.
    let target = CGSize(width: max(native.width, native.height),
                        height: min(native.width, native.height))
    guard target.width > 0, target.height > 0 else { return }

    webView.transform = .identity
    webView.frame = CGRect(origin: .zero, size: target)
    webView.transform = CGAffineTransform(scaleX: bounds.width / target.width,
                                          y: bounds.height / target.height)
    webView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    if !loggedCarLayout {
      loggedCarLayout = true
      Log.write("car layout native=\(target) area=\(bounds) "
        + "window=\(view.bounds.size) insets=\(view.safeAreaInsets) "
        + "scale=\(screen.scale) sidebar=\(Settings.avoidSidebar)")
    }
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    Log.write("didCommit \(webView.url?.absoluteString ?? "-")")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Log.write("didFinish \(webView.url?.absoluteString ?? "-") web=\(webView.bounds.size)")
    guard showsStatus else { return }  // only the phone window watches for this
    let host = webView.url?.host ?? ""
    if host.contains("accounts.google") || host.contains("accounts.youtube") {
      wasSigningIn = true
      return
    }
    if wasSigningIn && host.contains("youtube") {
      wasSigningIn = false
      NotificationCenter.default.post(name: .cafariLiteAccountChanged, object: nil)
    }
  }

  private func updateStatus() {
    // Whether a car window exists is the only thing worth reporting: it is the
    // difference between the app working and the app being a web browser.
    let connected = UIApplication.shared.connectedScenes.contains { scene in
      scene.session.role == cafariLiteCarPlayRole
    }
    statusLabel?.text = connected ? "On the car screen" : "Car screen not connected"
  }
}
