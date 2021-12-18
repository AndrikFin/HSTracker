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
    static var window: NSWindow {
        return AppDelegate.instance().coreManager.game.windowManager.playerBoardOverlay.view.window!
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
    
    static var readyButton: NSPoint {
        return NSPoint(x: 0.53, y: 0.0).toScreenPoint
    }
    
    static var chooseButton: NSPoint {
        return NSPoint(x: 0.42, y: 0.22).toScreenPoint
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
