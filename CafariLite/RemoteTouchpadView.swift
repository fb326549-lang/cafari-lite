import UIKit

/// A simple relative trackpad. One finger moves the remote pointer; a tap
/// clicks at the current pointer position; two fingers scroll the remote page.
final class RemoteTouchpadView: UIView {
  var onMove: ((CGFloat, CGFloat) -> Void)?
  var onTap: (() -> Void)?
  var onScroll: ((CGFloat, CGFloat) -> Void)?

  private enum GestureMode {
    case idle
    case pointer
    case scroll
  }

  private var mode: GestureMode = .idle
  private var lastPoint: CGPoint?
  private var lastCentroid: CGPoint?
  private var didMove = false
  private let hintLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    isMultipleTouchEnabled = true
    backgroundColor = UIColor(red: 0.075, green: 0.10, blue: 0.15, alpha: 1)
    layer.cornerRadius = 18
    layer.borderWidth = 1
    layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    clipsToBounds = true

    hintLabel.text = "觸控板\n一指移動・輕點選取・雙指捲動"
    hintLabel.textColor = UIColor.white.withAlphaComponent(0.62)
    hintLabel.textAlignment = .center
    hintLabel.numberOfLines = 2
    hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
    hintLabel.isUserInteractionEnabled = false
    hintLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hintLabel)
    NSLayoutConstraint.activate([
      hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
  }

  private func centroid(of points: [CGPoint]) -> CGPoint {
    guard !points.isEmpty else { return .zero }
    let sum = points.reduce(CGPoint.zero) { partial, point in
      CGPoint(x: partial.x + point.x, y: partial.y + point.y)
    }
    return CGPoint(x: sum.x / CGFloat(points.count),
                   y: sum.y / CGFloat(points.count))
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    let allTouches = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? Array(touches)
    let points = allTouches.map { $0.location(in: self) }

    if allTouches.count >= 2 {
      mode = .scroll
      lastCentroid = centroid(of: points)
      lastPoint = nil
      didMove = false
    } else if let point = points.first {
      mode = .pointer
      lastPoint = point
      lastCentroid = nil
      didMove = false
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    let allTouches = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? Array(touches)
    let points = allTouches.map { $0.location(in: self) }

    if allTouches.count >= 2 {
      let current = centroid(of: points)
      if let previous = lastCentroid {
        let dx = current.x - previous.x
        let dy = current.y - previous.y
        if abs(dx) + abs(dy) > 1 {
          didMove = true
          onScroll?(dx / max(bounds.width, 1), dy / max(bounds.height, 1))
        }
      }
      lastCentroid = current
      mode = .scroll
      return
    }

    guard let current = points.first else { return }
    if let previous = lastPoint {
      let dx = current.x - previous.x
      let dy = current.y - previous.y
      if abs(dx) + abs(dy) > 1 {
        didMove = true
        onMove?(dx / max(bounds.width, 1), dy / max(bounds.height, 1))
      }
    }
    lastPoint = current
    mode = .pointer
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    if mode == .pointer && !didMove {
      onTap?()
    }
    resetGesture()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    resetGesture()
  }

  private func resetGesture() {
    mode = .idle
    lastPoint = nil
    lastCentroid = nil
    didMove = false
  }
}
