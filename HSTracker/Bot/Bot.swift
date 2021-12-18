//
//  Bot.swift
//  HSTracker
//
//  Created by AO on 17.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import AppKit

class Bot {
    
    lazy var operationQueue: SerialOperationQueue = {
        let queue = SerialOperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    var core: CoreManager {
        return AppDelegate.instance().coreManager
    }
    
    static var hearthStoneApp: NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })
    }
    
    class func mouseClick(position: CGPoint, button: CGEventType = .leftMouseDown) {
        let sema = DispatchSemaphore(value: 0)
        
        
        
        DispatchQueue.main.async {
            let currentApp = NSWorkspace.shared.runningApplications.first(where: { $0.isActive })
            let currentPosition = NSEvent.mouseLocation
            print("👑 mouse position: \(currentPosition)")
            print("👑 AppID: \(cuString(describing: rrentApp?.bundleIdentifier)"))
            
            Task {
                
            }
            Bot.hearthStoneApp?.activate(options: .activateIgnoringOtherApps)
            
            
            let delay = 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let source = CGEventSource.init(stateID: .hidSystemState)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: button == .leftMouseDown ? .left : .right)?.post(tap: .cghidEventTap)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: button == .leftMouseDown ? .left : .right)?.post(tap: .cghidEventTap)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: button == .leftMouseDown ? .left : .right)?.post(tap: .cghidEventTap)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: currentPosition.toMonitor, mouseButton: CGMouseButton.left)?.post(tap: .cghidEventTap)
                        if currentApp?.bundleIdentifier != "com.apple.finder" && currentApp != hearthStoneApp {
                            currentApp?.activate(options: .activateIgnoringOtherApps)
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                CGEvent(mouseEventSource: CGEventSource.init(stateID: .hidSystemState), mouseType: .leftMouseDown, mouseCursorPosition: currentPosition.toMonitor, mouseButton: button == .leftMouseDown ? .left : .right)?.post(tap: .cghidEventTap)
                                sema.signal()
                            }
                        } else {
                            sema.signal()
                        }
                    }
                }
            }
        }
        
        sema.wait()
    }
    
    init() {
        subscribeToEvents()
    }
    
    func subscribeToEvents() {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            
            if event.modifierFlags.isSuperset(of: [.option, .command]) {
                switch event.type {
                case .leftMouseDown:
                    print("👑 mouse down: \(event.locationInWindow)")
                    print("👑 mouse down proportion: \(event.locationInWindow.proportionalPoint)")
                case .keyDown:
                    switch event.keyCode {
                    case 1: self?.start()
                    default: break
                    }
                default: break
                }
            }
        }
    }
    
    func start() {        
        Task {
            await Bot.wait(for: 3)
            Bot.mouseClick(position: .chooseButton)
            await Bot.wait(for: 3)
            Bot.mouseClick(position: .chooseButton)
        }
    }
    
   class func wait(for sec: TimeInterval) async {
        return await withUnsafeContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + sec) {
                continuation.resume()
            }
        }
    }
}

class SerialOperationQueue: OperationQueue {
    var queue = DispatchQueue(label: "bot.serial")
    
    override var underlyingQueue: DispatchQueue? {
        set {
            
        } get {
            return queue
        }
    }
}
