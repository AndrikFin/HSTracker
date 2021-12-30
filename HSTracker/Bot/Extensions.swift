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
    
    static var boxesButtons: [NSPoint] {
        return [NSPoint(x: 0.03, y:  -0.19).toScreenPoint,
                NSPoint(x: 0.32, y:  -0.06).toScreenPoint,
                NSPoint(x: 0.26, y:  0.26).toScreenPoint,
                NSPoint(x: -0.2, y:  0.28).toScreenPoint,
                NSPoint(x: -0.27, y:  -0.08).toScreenPoint,
        ]
    }
    
    static var disconnectOKButton: NSPoint {
        return NSPoint(x: 0.00, y: 0.11).toScreenPoint
    }
    
    static var bonusDoneButton: NSPoint {
        return NSPoint(x: 0.02, y: 0.05).toScreenPoint
    }
    
    static var finalScreenButton: NSPoint {
        return NSPoint(x: 0.00, y: 0.31).toScreenPoint
    }
    
    static var firstVisitor: NSPoint {
        return NSPoint(x: -0.29, y: 0.06).toScreenPoint
    }
    
    static var mysteryChooseButton: NSPoint {
        return NSPoint(x: -0.02, y: 0.2).toScreenPoint
    }
    
    static var bossButton: NSPoint {
        return NSPoint(x: -0.18, y: -0.26).toScreenPoint
    }
    
    static var mapTo: NSPoint {
        return NSPoint(x: 0.17, y: -0.04).toScreenPoint
    }
    
    static var mapFrom: NSPoint {
        return NSPoint(x: -0.52, y: -0.04).toScreenPoint
    }
    
    static var firstBonusButton: NSPoint {
        return NSPoint(x: -0.13, y: 0.00).toScreenPoint
    }
    
    static var bonusTakeButton: NSPoint {
        return NSPoint(x: 0.15, y: 0.30).toScreenPoint
    }
    
    static var readyButton: NSPoint {
        return NSPoint(x: 0.53, y: -0.02).toScreenPoint
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
        return NSPoint(x: -0.4, y: 0.3).toScreenPoint
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

extension CGEvent {
    
    static var bot: Bot {
        return AppDelegate.instance().bot
    }
    
    class func letfClick(position: NSPoint, delay: TimeInterval = 0.05, completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else {
            return
        }
        
        DispatchQueue.main.async {
            bot.delay(delay, type: .click) {
                CGEvent(mouseEventSource: CGEventSource.init(stateID: .combinedSessionState),
                        mouseType: .leftMouseDown,
                        mouseCursorPosition: position,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                
                bot.delay(0.05, type: .click) {
                    CGEvent(mouseEventSource: CGEventSource.init(stateID: .combinedSessionState),
                            mouseType: .leftMouseUp,
                            mouseCursorPosition: position,
                            mouseButton: .left)?.post(tap: .cghidEventTap)
                    bot.delay(0.05, type: .click) {
                        completion?()
                    }
                }
            }
        }
    }
    
    class func move(position: NSPoint, delay: TimeInterval = 0.05, completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else {
            return
        }
        
        DispatchQueue.main.async {
            bot.delay(delay, type: .click) {
                CGEvent(mouseEventSource: CGEventSource.init(stateID: .combinedSessionState),
                        mouseType: .mouseMoved,
                        mouseCursorPosition: position,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                
                bot.delay(0.05, type: .click) {
                    completion?()
                }
            }
        }
    }
    
    class func scroll(top: Bool = true, value: Int = 4, completion: (()->Void)? = nil) {
        guard !AppDelegate.instance().bot.paused && NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })?.isActive == true else {
            return
        }
        
        DispatchQueue.main.async {
            let event = CGEvent(scrollWheelEvent2Source: nil,
                                units: CGScrollEventUnit.pixel,
                                wheelCount: 1,
                                wheel1: 0,
                                wheel2: 0,
                                wheel3: 0)
            event?.setIntegerValueField(CGEventField.scrollWheelEventDeltaAxis1, value: top ? Int64(value) : -1000)
            DispatchQueue.main.asyncAfter(deadline: .now() + (top ? 0 : 0.4)) {
                event?.post(tap: .cghidEventTap)
            }
            
            bot.delay(0.1, type: .click) {
                DispatchQueue.main.asyncAfter(deadline: .now() + (top ? 0 : 2)) {
                    completion?()
                }
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

extension Dictionary where Key == Int, Value == [MapLevelType] {
    func prettyDescription() {
        let sorted = sorted(by: { $0.key > $1.key })
        
        sorted.forEach { keyValue in
            print("\(keyValue.value.compactMap({ $0.rawValue }))")
        }
    }
}
