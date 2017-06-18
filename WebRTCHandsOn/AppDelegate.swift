//
//  AppDelegate.swift
//  WebRTCHandsOn
//
//  Created by Takumi Minamoto on 2017/05/27.
//  Copyright © 2017 tnoho. All rights reserved.
//

import UIKit
import WebRTC

@UIApplicationMain
class AppDelesgate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        RTCInitializeSSL()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
        RTCCleanupSSL()
    }


}

