//
//  Extensions.swift
//  HSTracker
//
//  Created by AO on 17.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import AppKit

extension NSPoint {
    static var playerWindow: NSWindow {
        return AppDelegate.instance().coreManager.game.windowManager.playerBoardOverlay.view.window!
    }
    
    static var enemyWindow: NSWindow {
        return AppDelegate.instance().coreManager.game.windowManager.opponentBoardOverlay.view.window!
    }
    
    var playerScreenCenter: NSPoint {
        return NSPoint.playerWindow.convertPoint(toScreen: self).toEuqlid
    }
    
    var enemyScreenCenter: NSPoint {
        return NSPoint.enemyWindow.convertPoint(toScreen: self).toEuqlid
    }
    
    var toHSPoint: NSPoint {
        return self.toEuqlid
    }
    
    static var hsInfo: [String: Any]? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        return infoList.first(where: {($0[kCGWindowOwnerName as String] as? String) == "Hearthstone"})
    }
    
    static var fullScreen: Bool {
        if let frame = hsInfo?[kCGWindowBounds as String] as? [String: Any] {
            let represFrame = NSRect(dictionaryRepresentation: frame as CFDictionary) ?? .zero
            return represFrame.height < 50
        }
        return false
    }
    
    static var frame: NSRect {
        var saveFrame = NSRect.zero
        if let frame = hsInfo?[kCGWindowBounds as String] as? [String: Any] {
            let represFrame = NSRect(dictionaryRepresentation: frame as CFDictionary) ?? .zero
            if fullScreen {
                if represFrame.origin.x >= NSScreen.screens.first?.frame.size.width ?? 0 {
                    saveFrame = NSScreen.screens.last?.frame ?? .zero
                } else {
                    saveFrame = NSScreen.screens.first?.frame ?? .zero
                }
            }
            else {
                saveFrame = represFrame
            }
        }
        
        return saveFrame
    }
    
    static var mapTo: NSPoint {
        return NSPoint(x: 0.07, y: 0.08).toScreenPoint
    }
    
    static var mapFrom: NSPoint {
        return NSPoint(x: -0.5, y: -0.07).toScreenPoint
    }
    
    static var bonusDoneButton: NSPoint {
        return NSPoint(x: 0.15, y: 0.30).toScreenPoint
    }
    
    static var readyButton: NSPoint {
        return NSPoint(x: 0.53, y: 0.0).toScreenPoint
    }
    
    static var chooseButton: NSPoint {
        return NSPoint(x: 0.46, y: 0.34).toScreenPoint
    }
    
    static var firstSkill: NSPoint {
        return NSPoint(x: -0.16, y: -0.03).toScreenPoint
    }
    
    static var secondSkill: NSPoint {
        return NSPoint(x: -0.00, y: -0.03).toScreenPoint
    }
    
    static var thirdSkill: NSPoint {
        return NSPoint(x: 0.16, y: -0.03).toScreenPoint
    }
    
    static var testButton: NSPoint {
        return NSPoint(x: -0.64, y: 0.38).toScreenPoint
    }
    
    var proportionalPoint: NSPoint {
        let x = (x - (NSPoint.frame.origin.x + NSPoint.frame.size.width / 2)) / NSPoint.frame.size.height
        let y = (y - (NSPoint.frame.origin.y + NSPoint.frame.size.height / 2)) / NSPoint.frame.size.height
        
        return NSPoint(x: x, y: y)
    }
    
    var toScreenPoint: NSPoint {
        let x = NSPoint.frame.origin.x + NSPoint.frame.size.width / 2 + x * NSPoint.frame.size.height
        let y = NSPoint.frame.origin.y + NSPoint.frame.size.height / 2 + y * NSPoint.frame.size.height
        
        return NSPoint(x: x, y: y)
    }
    
    var toEuqlid: NSPoint {
        return NSPoint(x: x, y: screen.frame.size.height - y)
    }
    
    var screen: NSScreen {
        if x >= NSScreen.screens.first?.frame.size.width ?? 0 {
            return NSScreen.screens.last!
        } else {
            return NSScreen.screens.first!
        }
    }
    
    var toMonitor: NSPoint {
        if x >= NSScreen.screens.first?.frame.width ?? 0 {
            let converted = self.toEuqlid
            return NSPoint(x: x, y: converted.y + 400)
        }
        
        return self.toEuqlid
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        CGDirectDisplayID(deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! UInt)
    }
}

class SerialOperationQueue: OperationQueue {
    static var queue = DispatchQueue(label: "bot.serial")
    
    static var shared: SerialOperationQueue = {
        let queue = SerialOperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    var operationsArray: [BlockOperation] = []
    
    override var underlyingQueue: DispatchQueue? {
        set {
            
        } get {
            return SerialOperationQueue.queue
        }
    }
}

extension CGEvent {
    
    static var isClicking = false
    
    class func letfClick(position: NSPoint, delay: TimeInterval = 0.05, completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && isClicking == false && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else { return }
        
        isClicking = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState),
                    mouseType: .leftMouseDown,
                    mouseCursorPosition: position,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState),
                        mouseType: .leftMouseUp,
                        mouseCursorPosition: position,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isClicking = false
                    completion?()
                }
            }
        }
    }
    
    class func move(position: NSPoint, delay: TimeInterval = 0.05, completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && isClicking == false && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState),
                    mouseType: .mouseMoved,
                    mouseCursorPosition: position,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion?()
            }
        }
    }
    
    class func scroll(completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && isClicking == false && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else { return }
        
        DispatchQueue.main.async {
            CGEvent(scrollWheelEvent2Source: nil,
                    units: CGScrollEventUnit.pixel,
                    wheelCount: 1,
                    wheel1: Int32(NSPoint.frame.size.height) / 18,
                    wheel2: 0,
                    wheel3: 0)?.post(tap: .cghidEventTap)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion?()
            }
        }
    }
}

extension Game {
    var step: Step {
        return  Step(rawValue: gameEntity?[.step] ?? 0) ?? .invalid
    }
}

extension NSRect {
    var center: NSPoint {
        return NSPoint(x: midX, y: midY)
    }
}

extension NSView {
    var center: NSPoint {
        return frame.center
    }
}

extension Card {
    var role: Int {
        return jsonRepresentation["mercenariesRole"] as? Int ?? 0
    }
}

fileprivate let badChars = CharacterSet.alphanumerics.inverted
extension String {
    var uppercasingFirst: String {
        return prefix(1).uppercased() + dropFirst()
    }

    var lowercasingFirst: String {
        return prefix(1).lowercased() + dropFirst()
    }

    var camelized: String {
        guard !isEmpty else {
            return ""
        }

        let parts = self.components(separatedBy: badChars)

        let first = String(describing: parts.first!).lowercasingFirst
        let rest = parts.dropFirst().map({String($0).uppercasingFirst})

        return ([first] + rest).joined(separator: "")
    }
}
