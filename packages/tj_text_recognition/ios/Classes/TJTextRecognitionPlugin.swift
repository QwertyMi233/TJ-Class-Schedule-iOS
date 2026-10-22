import Foundation
import Flutter
import Vision
import ImageIO

enum TJImageTextRecognizer {
    static func recognize(url: URL, cpuOnly: Bool = false) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "TJImageTextRecognizer", code: 1)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter(supported.contains)
        // CI simulators can use the CPU; real devices use Vision's default device selection.
        if cpuOnly { request.usesCPUOnly = true }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

public final class TJTextRecognitionPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "offline_course_schedule/text_recognition", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(TJTextRecognitionPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "recognizeFile" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String, !path.isEmpty else {
            result(FlutterError(code: "invalid_image", message: "无法读取图片", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try TJImageTextRecognizer.recognize(url: URL(fileURLWithPath: path))
                DispatchQueue.main.async { result(text) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "recognition_failed", message: "图片文字识别失败", details: nil))
                }
            }
        }
    }
}
