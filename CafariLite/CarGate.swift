// MyCar Browser -- best-effort parked-state gate for the CarPlay browser.
//
// There is no public CarPlay API that reports the vehicle's gear or exact
// parked state. This gate therefore fails closed: video remains covered until
// several fresh, accurate, low-speed GPS samples are received. GPS is not a
// certified vehicle safety interlock and must never be treated as one.

import CoreLocation
import Foundation

final class CarGate: NSObject, CLLocationManagerDelegate {
  static let shared = CarGate()

  static let stateChanged = Notification.Name("MyCarCarGateChanged")

  /// Unknown or unverified state is treated as moving.
  private(set) var isMoving = true
  private let manager = CLLocationManager()
  private var running = false
  private var stoppedSamples = 0

  /// Below ~1.8 km/h is treated as stationary, subject to location accuracy.
  private let stoppedSpeed: CLLocationSpeed = 0.5
  private let requiredStoppedSamples = 4

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 1
    manager.pausesLocationUpdatesAutomatically = false
  }

  func start() {
    guard !running else { return }
    running = true
    stoppedSamples = 0
    setMoving(true)

    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
    manager.startUpdatingLocation()
    Log.write("car gate started, authorization=\(manager.authorizationStatus.rawValue)")
  }

  func stop() {
    guard running else { return }
    running = false
    manager.stopUpdatingLocation()
    stoppedSamples = 0
    // The caller may stop the gate because the user explicitly disabled it.
    setMoving(true)
    Log.write("car gate stopped")
  }

  private func setMoving(_ moving: Bool) {
    guard moving != isMoving else { return }
    isMoving = moving
    Log.write("car gate: \(moving ? "moving/unknown" : "stationary by GPS")")
    NotificationCenter.default.post(name: CarGate.stateChanged, object: nil)
  }

  func locationManager(_ manager: CLLocationManager,
                       didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      stoppedSamples = 0
      setMoving(true)
      return
    }

    let age = abs(location.timestamp.timeIntervalSinceNow)
    let validFix = age <= 10
      && location.horizontalAccuracy >= 0
      && location.horizontalAccuracy <= 50
      && location.speed >= 0
      && location.speedAccuracy >= 0
      && location.speedAccuracy <= 1.5

    guard validFix else {
      stoppedSamples = 0
      setMoving(true)
      Log.write("car gate: location sample unreliable; keeping screen covered")
      return
    }

    if location.speed > stoppedSpeed {
      stoppedSamples = 0
      setMoving(true)
      return
    }

    stoppedSamples += 1
    if stoppedSamples >= requiredStoppedSamples {
      setMoving(false)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    stoppedSamples = 0
    setMoving(true)
    Log.write("car gate: location error; keeping screen covered: \(error.localizedDescription)")
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Log.write("car gate: authorization now \(manager.authorizationStatus.rawValue)")
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      stoppedSamples = 0
      setMoving(true)
      if running { manager.startUpdatingLocation() }
    case .denied, .restricted:
      stoppedSamples = 0
      setMoving(true)
    case .notDetermined:
      stoppedSamples = 0
      setMoving(true)
    @unknown default:
      stoppedSamples = 0
      setMoving(true)
    }
  }
}
