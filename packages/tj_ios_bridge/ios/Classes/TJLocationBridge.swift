import Flutter
import CoreLocation
import UIKit

final class TJLocationBridge: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
    private var sink: FlutterEventSink?
    private var requested = false
    private var observers: [NSObjectProtocol] = []
    private lazy var manager: CLLocationManager = {
        let value = CLLocationManager()
        value.delegate = self
        value.desiredAccuracy = kCLLocationAccuracyBest
        value.distanceFilter = 1
        value.headingFilter = 1
        value.pausesLocationUpdatesAutomatically = true
        return value
    }()

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.requested == true else { return }
            self?.resume(requestPermission: false)
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        requested = false
        pause()
        sink = nil
        return nil
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            requested = true
            let args = call.arguments as? [String: Any]
            resume(requestPermission: args?["requestPermission"] as? Bool ?? true)
            result(nil)
        case "stop":
            requested = false
            pause()
            result(nil)
        case "appSettings", "locationSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
            } else { result(nil) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func status(_ value: String) { sink?(["type": "status", "status": value]) }

    private func resume(requestPermission: Bool) {
        guard requested, UIApplication.shared.applicationState != .background else { return }
        guard CLLocationManager.locationServicesEnabled() else { status("disabled"); return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status("denied")
            if requestPermission { manager.requestWhenInUseAuthorization() }
        case .denied, .restricted:
            status("deniedForever")
        case .authorizedAlways, .authorizedWhenInUse:
            status("waiting")
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        @unknown default:
            status("error")
        }
    }

    private func pause() {
        guard requested || sink != nil else { return }
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if requested { resume(requestPermission: false) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requested, UIApplication.shared.applicationState != .background,
              let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let age = Date().timeIntervalSince(fix.timestamp) * 1000
        guard age >= 0, age <= 15000 else { status("stale"); return }
        sink?(["type": "fix", "lat": fix.coordinate.latitude, "lon": fix.coordinate.longitude,
               "accuracy": fix.horizontalAccuracy, "ageMs": Int(age)])
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard requested, UIApplication.shared.applicationState != .background else { return }
        // True north matches the geodesic bearing used by the Dart direction UI.
        let value = heading.trueHeading
        let reliable = heading.headingAccuracy >= 0 && heading.headingAccuracy <= 30 && value >= 0
        sink?(["type": "heading", "heading": value >= 0 ? value : heading.magneticHeading,
               "reliable": reliable])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requested else { return }
        if let error = error as? CLError {
            status(error.code == .denied ? "deniedForever" : "stale")
        } else { status("error") }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
