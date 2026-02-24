//
//  PhoneCameraManager.swift
//  Smart Glasses
//
//  Phone camera fallback when Meta glasses are not connected
//

import Combine
import Foundation
import AVFoundation
import UIKit

/// Manages the phone's built-in camera as a fallback scanning source
@MainActor
class PhoneCameraManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isRunning: Bool = false
    @Published var latestFrameImage: UIImage?
    @Published var permissionGranted: Bool = false

    // MARK: - Capture Session

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.smartglasses.phonecamera")

    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        checkPermission()
    }

    // MARK: - Permission

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            requestPermission()
        default:
            permissionGranted = false
        }
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.permissionGranted = granted
            }
        }
    }

    // MARK: - Session Control

    func startSession() {
        guard permissionGranted else {
            checkPermission()
            return
        }

        guard !isRunning else { return }

        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
            Task { @MainActor in
                self?.isRunning = true
            }
        }
    }

    func stopSession() {
        guard isRunning else { return }

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            Task { @MainActor in
                self?.isRunning = false
                self?.latestFrameImage = nil
            }
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        guard captureSession.inputs.isEmpty else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // Add back camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Add video output for continuous frames
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Add photo output for high-res capture
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        // Enable auto-focus for document scanning
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {
            print("[PhoneCamera] Failed to configure camera: \(error)")
        }
    }

    // MARK: - Photo Capture

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isRunning else {
            completion(nil)
            return
        }

        photoCaptureCompletion = completion

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = photoOutput.isHighResolutionCaptureEnabled
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        Task { @MainActor in
            self.latestFrameImage = uiImage
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhoneCameraManager: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.photoCaptureCompletion?(nil)
                self.photoCaptureCompletion = nil
            }
            return
        }

        Task { @MainActor in
            print("[PhoneCamera] Photo captured: \(image.size.width)x\(image.size.height)")
            self.photoCaptureCompletion?(image)
            self.photoCaptureCompletion = nil
        }
    }
}
