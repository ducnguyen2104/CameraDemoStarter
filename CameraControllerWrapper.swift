//
//  CameraControllerWrapper.swift
//  AV Foundation
//
//  Created by CPU11613 on 12/12/18.
//  Copyright © 2018 Pranjal Satija. All rights reserved.
//

import Foundation
class CameraControllerSelector {
    class func cameraController() -> CameraController {
        if #available(iOS 10, *) {
            return CameraController10()
        }
        return CameraController9()
    }
}
