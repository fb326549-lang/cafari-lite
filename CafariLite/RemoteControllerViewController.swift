import UIKit

/// iPhone companion interface for the CarPlay browser.
final class RemoteControllerViewController: UIViewController, UITextFieldDelegate {
  private let connectionLabel = UILabel()
  private let addressField = UITextField()
  private let textField = UITextField()
  private let touchpad = RemoteTouchpadView()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor { trait in
      trait.userInterfaceStyle == .dark ? .black : UIColor(white: 0.97, alpha: 1)
    }
    title = "MyCar Browser"
    buildInterface()
    wireTouchpad()

    NotificationCenter.default.addObserver(
      self, selector: #selector(updateConnection),
      name: .cafariLiteCarConnected, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(updateConnection),
      name: .cafariLiteCarDisconnected, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(updateConnection),
      name: CarGate.stateChanged, object: nil)

    if Settings.playOnlyWhenParked {
      CarGate.shared.start()
    }
    updateConnection()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateConnection()
  }

  private func buildInterface() {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 13
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
    ])

    let heading = UIStackView()
    heading.axis = .horizontal
    heading.alignment = .center
    heading.distribution = .equalSpacing

    let titleLabel = UILabel()
    titleLabel.text = "MyCar Browser"
    titleLabel.font = .systemFont(ofSize: 23, weight: .bold)
    heading.addArrangedSubview(titleLabel)

    connectionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    connectionLabel.textColor = .secondaryLabel
    connectionLabel.text = "檢查車機連線…"
    heading.addArrangedSubview(connectionLabel)
    stack.addArrangedSubview(heading)

    let addressRow = UIStackView()
    addressRow.axis = .horizontal
    addressRow.spacing = 8
    addressField.borderStyle = .roundedRect
    addressField.placeholder = "輸入網址或 YouTube 搜尋關鍵字"
    addressField.autocapitalizationType = .none
    addressField.autocorrectionType = .no
    addressField.keyboardType = .URL
    addressField.returnKeyType = .go
    addressField.clearButtonMode = .whileEditing
    addressField.delegate = self
    addressField.translatesAutoresizingMaskIntoConstraints = false
    addressRow.addArrangedSubview(addressField)
    addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    addressField.heightAnchor.constraint(equalToConstant: 44).isActive = true

    let goButton = makeButton("前往", action: #selector(openAddress))
    goButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
    addressRow.addArrangedSubview(goButton)
    stack.addArrangedSubview(addressRow)

    let controls = UIStackView()
    controls.axis = .horizontal
    controls.spacing = 8
    controls.distribution = .fillEqually
    controls.addArrangedSubview(makeButton("返回", action: #selector(goBack)))
    controls.addArrangedSubview(makeButton("前進", action: #selector(goForward)))
    controls.addArrangedSubview(makeButton("首頁", action: #selector(goHome)))
    controls.addArrangedSubview(makeButton("重整", action: #selector(reloadPage)))
    stack.addArrangedSubview(controls)

    let padHeader = UIStackView()
    padHeader.axis = .horizontal
    padHeader.alignment = .center
    padHeader.distribution = .equalSpacing
    let padTitle = UILabel()
    padTitle.text = "遠端觸控板"
    padTitle.font = .systemFont(ofSize: 16, weight: .semibold)
    padHeader.addArrangedSubview(padTitle)
    let padTip = UILabel()
    padTip.text = "像筆電觸控板一樣操作"
    padTip.font = .systemFont(ofSize: 11)
    padTip.textColor = .secondaryLabel
    padHeader.addArrangedSubview(padTip)
    stack.addArrangedSubview(padHeader)

    touchpad.translatesAutoresizingMaskIntoConstraints = false
    touchpad.heightAnchor.constraint(equalToConstant: 265).isActive = true
    stack.addArrangedSubview(touchpad)

    let keyboardHeader = UILabel()
    keyboardHeader.text = "文字輸入"
    keyboardHeader.font = .systemFont(ofSize: 15, weight: .semibold)
    stack.addArrangedSubview(keyboardHeader)

    let textRow = UIStackView()
    textRow.axis = .horizontal
    textRow.spacing = 8
    textField.borderStyle = .roundedRect
    textField.placeholder = "先在車機點選搜尋框，再在這裡輸入"
    textField.autocorrectionType = .no
    textField.returnKeyType = .send
    textField.delegate = self
    textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
    textRow.addArrangedSubview(textField)
    let sendButton = makeButton("送出", action: #selector(sendText))
    sendButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
    textRow.addArrangedSubview(sendButton)
    stack.addArrangedSubview(textRow)

    let footer = UIStackView()
    footer.axis = .horizontal
    footer.spacing = 8
    footer.distribution = .fillEqually
    footer.addArrangedSubview(makeButton("手機瀏覽／登入", action: #selector(openPhoneBrowser)))
    footer.addArrangedSubview(makeButton("重設游標", action: #selector(resetPointer)))
    stack.addArrangedSubview(footer)

    let note = UILabel()
    note.text = "建議停車時使用。部分網頁的播放／全螢幕按鈕可能要求車機直接觸控。"
    note.textColor = .secondaryLabel
    note.font = .systemFont(ofSize: 11)
    note.numberOfLines = 2
    note.textAlignment = .center
    stack.addArrangedSubview(note)
  }

  private func makeButton(_ title: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.backgroundColor = UIColor.secondarySystemBackground
    button.layer.cornerRadius = 10
    button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func wireTouchpad() {
    touchpad.onMove = { [weak self] dx, dy in
      self?.send(["type": "move", "dx": Double(dx * 1.45), "dy": Double(dy * 1.45)])
    }
    touchpad.onTap = { [weak self] in
      self?.send(["type": "tap"])
    }
    touchpad.onScroll = { [weak self] dx, dy in
      self?.send(["type": "scroll", "dx": Double(dx), "dy": Double(dy)])
    }
  }

  private func send(_ command: [String: Any]) {
    NotificationCenter.default.post(name: .myCarRemoteCommand, object: nil, userInfo: command)
  }

  @objc private func updateConnection() {
    let connected = UIApplication.shared.connectedScenes.contains {
      $0.session.role == cafariLiteCarPlayRole
    }
    connectionLabel.text = connected ? "● 車機已連線" : "○ 尚未連接車機"
    connectionLabel.textColor = connected ? .systemGreen : .secondaryLabel
  }

  @objc private func openAddress() {
    guard let raw = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else { return }
    addressField.resignFirstResponder()

    let destination: URL?
    if let components = URLComponents(string: raw),
       let scheme = components.scheme?.lowercased(),
       (scheme == "https" || scheme == "http"),
       let url = components.url {
      destination = url
    } else if raw.contains(".") && !raw.contains(" ") {
      destination = URL(string: "https://" + raw)
    } else {
      var components = URLComponents(string: "https://m.youtube.com/results")
      components?.queryItems = [URLQueryItem(name: "search_query", value: raw)]
      destination = components?.url
    }

    guard let url = destination,
          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
    send(["type": "navigate", "url": url.absoluteString])
  }

  @objc private func sendText() {
    guard let text = textField.text, !text.isEmpty else { return }
    send(["type": "insertText", "text": text])
    textField.text = ""
    textField.resignFirstResponder()
  }

  @objc private func goBack() { send(["type": "back"]) }
  @objc private func goForward() { send(["type": "forward"]) }
  @objc private func goHome() { send(["type": "home"]) }
  @objc private func reloadPage() { send(["type": "reload"]) }
  @objc private func resetPointer() { send(["type": "resetPointer"]) }

  @objc private func openPhoneBrowser() {
    let browser = BrowserViewController(showsStatus: true)
    browser.modalPresentationStyle = .fullScreen
    present(browser, animated: true)
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === addressField {
      openAddress()
    } else {
      sendText()
    }
    return true
  }
}
