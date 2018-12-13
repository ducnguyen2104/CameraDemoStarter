//
//  CameraController.swift
//  AV Foundation
//
//  Created by CPU11613 on 12/12/18.
//  Copyright © 2018 Pranjal Satija. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol CameraController: class {
    var flashMode: AVCaptureDevice.FlashMode {get set}
    var currentCameraPos: CameraPosition? {get set}
    func prepare(completionHandler: @escaping (Error?) -> Void)
    func displayPreview(on view: UIView) throws
    func switchCamera() throws
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void)
    func toggleFlash()
}

@available(iOS 10.0, *)
class CameraController10: NSObject, CameraController {
    
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var rearCamera: AVCaptureDevice?
    var currentCameraPos: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var rearCameraInput: AVCaptureDeviceInput?
    var photoOutput: AVCapturePhotoOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var flashMode = AVCaptureDevice.FlashMode.off
    
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        func createCaptureSession() {
            print("create capture session 10")
            self.captureSession = AVCaptureSession()
        }
        func configureCaptureDevices() throws {
            print("config capture devices 10")
            let session = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
            
            let cameras = session.devices.flatMap{$0}
            guard !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable }
            
            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
                
                if camera.position == .back {
                    self.rearCamera = camera
                    
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    camera.flashMode = AVCaptureDevice.FlashMode.off
                    camera.unlockForConfiguration()
                }
            }
        }
        func configureDeviceInputs() throws {
            print("config device inputs 10")
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing}
            
            if let rearCamera = self.rearCamera {
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                if captureSession.canAddInput(self.rearCameraInput!) {
                    captureSession.addInput(self.rearCameraInput!)
                }
                self.currentCameraPos = .rear
            }
                
            else if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) {
                    captureSession.addInput(self.frontCameraInput!)
                } else {
                    throw CameraControllerError.invalidInputs
                }
                self.currentCameraPos = .front
            }
                
            else {
                throw CameraControllerError.noCamerasAvailable
            }
        }
        func configurePhotoOutput() throws {
            print("config photo output 10")
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing}
            
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecJPEG])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput!) {
                captureSession.addOutput(self.photoOutput!)
            }
            
            captureSession.startRunning()
            
        }
        
        DispatchQueue(label: "Prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
            }
                
            catch {
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
            }
        }
    }
    
    func displayPreview(on view: UIView) throws {
        print("display preview 10")
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing}
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    func switchCamera() throws {
        guard let currentCameraPosition = currentCameraPos, let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        
        captureSession.beginConfiguration()
        
        func switchToFrontCamera() throws {
            let inputs = captureSession.inputs
            guard !inputs.isEmpty, let rearCameraInput = self.rearCameraInput, inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else {
                    throw CameraControllerError.invalidOperation
            }
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
            }
            else {
                throw CameraControllerError.invalidOperation
            }
        }
        func switchToRearCamera() throws {
            let inputs = captureSession.inputs
            guard !inputs.isEmpty, let frontCameraInput = self.frontCameraInput,
            inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else {
                    throw CameraControllerError.invalidOperation
            }
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
            }
            else {
                throw CameraControllerError.invalidOperation
            }
        }
        
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera()
        case .rear:
            try switchToFrontCamera()
        }
        
        captureSession.commitConfiguration()
    }
    
    func captureImage(completion:@escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession, captureSession.isRunning else {
            completion(nil, CameraControllerError.captureSessionIsMissing); return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
    
    func toggleFlash() {
        if let camera = self.rearCamera {
            switch self.flashMode {
            case .off:
                self.flashMode = .on
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.on
                camera.unlockForConfiguration()
            case .on:
                self.flashMode = .off
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.off
                camera.unlockForConfiguration()
            default:
                self.flashMode = .off
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.off
                camera.unlockForConfiguration()
            }
        }
    }
}

@available(iOS 9.0, *)
class CameraController9: NSObject, CameraController {
    
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var rearCamera: AVCaptureDevice?
    var currentCameraPos: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var rearCameraInput: AVCaptureDeviceInput?
    var photoOutput: AVCaptureStillImageOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var flashMode = AVCaptureDevice.FlashMode.off
    
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        func createCaptureSession() {
            print("create capture session 9")
            self.captureSession = AVCaptureSession()
        }
        func configureCaptureDevices() throws {
            print("config capture devices 9")
            let cameras = AVCaptureDevice.devices(for: AVMediaType.video)
            
            guard !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable }
            
            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
                
                if camera.position == .back {
                    self.rearCamera = camera
                    
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    camera.unlockForConfiguration()
                }
            }
        }
        func configureDeviceInputs() throws {
            print("config device inputs 9")
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing}
            
            if let rearCamera = self.rearCamera {
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                if captureSession.canAddInput(self.rearCameraInput!) {
                    captureSession.addInput(self.rearCameraInput!)
                }
                self.currentCameraPos = .rear
            }
                
            else if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) {
                    captureSession.addInput(self.frontCameraInput!)
                } else {
                    throw CameraControllerError.invalidInputs
                }
                self.currentCameraPos = .front
            }
                
            else {
                throw CameraControllerError.noCamerasAvailable
            }
        }
        func configurePhotoOutput() throws {
            print("config photo output 9")
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing}
            
            self.photoOutput = AVCaptureStillImageOutput()
            self.photoOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            
            if captureSession.canAddOutput(self.photoOutput!) {
                captureSession.addOutput(self.photoOutput!)
            }
            
            captureSession.startRunning()
        }
        
        DispatchQueue(label: "Prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
            }
                
            catch {
                DispatchQueue.main.async {
                    completionHandler(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func displayPreview(on view: UIView) throws {
        print("display preview 9")
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing}
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    func switchCamera() throws {
        guard let currentCameraPosition = currentCameraPos, let captureSession = self.captureSession, captureSession.isRunning else {
            throw CameraControllerError.captureSessionIsMissing
        }
        
        captureSession.beginConfiguration()
        
        func switchToFrontCamera() throws {
            let inputs = captureSession.inputs
            guard !inputs.isEmpty, let rearCameraInput = self.rearCameraInput, inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else {
                    throw CameraControllerError.invalidOperation
            }
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                
                self.currentCameraPos = .front
            }
            else {
                throw CameraControllerError.invalidOperation
            }
        }
        func switchToRearCamera() throws {
            let inputs = captureSession.inputs
            guard !inputs.isEmpty, let frontCameraInput = self.frontCameraInput,
                inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else {
                    print("guard error")
                    throw CameraControllerError.invalidOperation
            }
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                
                self.currentCameraPos = .rear
            }
            else {
                print("add input error")
                throw CameraControllerError.invalidOperation
            }
        }
        
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera()
        case .rear:
            try switchToFrontCamera()
        }
        
        captureSession.commitConfiguration()
    }
    
    func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        self.photoCaptureCompletionBlock = completion
        if let videoConnection = photoOutput?.connection(with: AVMediaType.video) {
            photoOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: {(sampleBuffer, error) -> Void in
                if sampleBuffer != nil {
                    guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer!) else {
                        return (self.photoCaptureCompletionBlock?(nil, CameraControllerError.invalidInputs))!
                    }
                    guard let dataProvider = CGDataProvider(data: imageData as CFData) else {
                        return (self.photoCaptureCompletionBlock?(nil, CameraControllerError.invalidInputs))!
                    }
                    guard let cgImageRef = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent) else {
                        return (self.photoCaptureCompletionBlock?(nil, CameraControllerError.invalidInputs))!
                    }
                    let image = UIImage(cgImage: cgImageRef, scale: 1.0, orientation: UIImageOrientation.right)
                    self.photoCaptureCompletionBlock?(image, nil)
                }
                else {
                    self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
                }
            })
        }
    }
    
    func toggleFlash() {
        if let camera = self.rearCamera {
            switch self.flashMode {
            case .off:
                self.flashMode = .on
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.on
                camera.unlockForConfiguration()
            case .on:
                self.flashMode = .off
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.off
                camera.unlockForConfiguration()
            default:
                self.flashMode = .off
                try? camera.lockForConfiguration()
                camera.flashMode = AVCaptureDevice.FlashMode.off
                camera.unlockForConfiguration()
            }
        }
    }
}

enum CameraControllerError: Swift.Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case invalidInputs
    case invalidOperation
    case noCamerasAvailable
    case unknown
}

public enum CameraPosition {
    case front
    case rear
}

@available(iOS 10.0, *)
extension CameraController10: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                            previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                        resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?,
                        error: Swift.Error?
                        ) {
        if let error = error {
            self.photoCaptureCompletionBlock?(nil, error)
        }
        
        else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
        let image = UIImage(data: data) {
            self.photoCaptureCompletionBlock?(image, nil)
        }
        else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}

//@available(iOS 9.0, *)
//extension CameraController9: AVCaptureDelegate {
//
//    public func photoOutput(_ captureOutput: AVCaptureStillImageOutput,
//                            didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
//                            previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
//                            resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?,
//                            error: Swift.Error?
//        ) {
//        if let error = error {
//            self.photoCaptureCompletionBlock?(nil, error)
//        }
//
//        else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
//            let image = UIImage(data: data) {
//            self.photoCaptureCompletionBlock?(image, nil)
//        }
//        else {
//            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
//        }
//    }
//}
