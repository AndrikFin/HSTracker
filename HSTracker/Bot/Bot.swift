//
//  Bot.swift
//  HSTracker
//
//  Created by AO on 17.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import AppKit
import WebKit

class Bot {
    var operationQueue: SerialOperationQueue {
        return SerialOperationQueue.shared
    }
    
    var core: CoreManager {
        return AppDelegate.instance().coreManager
    }
    
    static var hearthStoneApp: NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })
    }
    
    init() {
        subscribeToEvents()
    }
    
    @objc func handleNot(not: Any) {
        print(not)
    }
    
    var pingDate: Date = Date()
    var prevStep: Step = .invalid
    func updateState() {
        if prevStep != core.game.step { self.stepDidChange() }
        prevStep = core.game.step
        if core.game.step == .main_action {
            if Date().timeIntervalSince(pingDate) > 0.5 {
                log("ping")
            }
            pingDate = Date()
        }
    }
    
    func log(_ string: String) {
        print("👑 \(Date()) \(string)")
    }
    
    func stepDidChange() {
        log("step: \(core.game.step)")
    }
    
    var playerMinions: [Entity] {
        return core.game.player.board.filter({$0.isMinion}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var enemyMinions: [Entity] {
        return core.game.opponent.board.filter({$0.isMinion}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var enemiesReady: Bool {
        let enemyStates = enemyMinions.compactMap({$0.has(tag:.lettuce_ability_tile_visual_all_visible)})
        return enemyStates.count > 0 && !enemyStates.contains(false)
    }
    
    var playerViews: [NSView] {
        return core.game.windowManager.playerBoardOverlay.view.minions
    }
    
    var enemyViews: [NSView] {
        return core.game.windowManager.opponentBoardOverlay.view.minions
    }
    
    func analizeMap(completion: @escaping (([Int: [MapLevelType]])->Void)) {
        let steps: CGFloat = 6
        
        let startX = NSPoint.mapFrom.x
        let endX = NSPoint.mapTo.x
        let distance = endX - startX
        let step = distance / steps
        
        var mapTypes: [Int: [MapLevelType]] = [:]
        
        let scrolls = 5
        
        func scrollAndAnalyze(scroll: Int) {
            guard scroll <= scrolls else {
                completion(mapTypes)
                return
            }
            CGEvent.scroll() {
                mapTypes.updateValue([MapLevelType](), forKey: scroll)
                func analyse(point: NSPoint) {
                    guard point.x <= endX else {
                        scrollAndAnalyze(scroll: scroll + 1)
                        return
                    }
                    CGEvent.move(position: point, delay: 0.5) {
                        ImageRecognitionHelper.makeScreenshot(position: point.toEuqlid.toHSPoint) { pointStrings in
                            let type = MapLevelType(string: pointStrings.first ?? "")
                            if type != .invalid && mapTypes[scroll]?.last != type {
                                mapTypes[scroll]?.append(type)
                            }
                            print(pointStrings)
                            analyse(point: NSPoint(x: point.x + step, y: NSPoint.mapFrom.y))
                        }
                    }
                }
                analyse(point: NSPoint.mapFrom)
            }
        }
        scrollAndAnalyze(scroll: 0)
    }
    
    func subscribeToEvents() {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            
            if event.modifierFlags.isSuperset(of: [.option, .command]) {
                switch event.type {
                case .leftMouseDown:
                    self?.log("mouse down proportion: \(event.locationInWindow.toEuqlid.proportionalPoint)")
                    self?.log("mouse down: \(event.locationInWindow)")
                    self?.log("mouse down hs: \(event.locationInWindow.toHSPoint)")
                    ImageRecognitionHelper.makeScreenshot(position: event.locationInWindow.toHSPoint) { string in
                        self?.log(string.description)
                    }
                case .keyDown:
                    switch event.keyCode {
                    case 1: self?.start()
                    case 0: self?.analizeMap {
                        self?.log($0.sorted(by: {$0.key < $1.key}).description)
                    }
                    case 35: self?.pause()
                    default: break
                    }
                default: break
                }
            }
        }
    }
    
    func pause() {
        paused.toggle()
    }
    
    var paused: Bool = false
    weak var clickSpamTimer: Timer? {
        didSet {
            if clickSpamTimer == nil {
                clickSpamTimerMaxDate = nil
            }
        }
    }
    var clickSpamTimerMaxDate: Date?
    
    func spam(doOnce: (()->Void)? = nil,
              block: (()->Void)? = nil,
              condition: @escaping (()->Bool),
              completion: ((Bool)->Void)? = nil,
              maxTime: TimeInterval? = nil,
              interval: TimeInterval = 0.4) {
        doOnce?()
        if let maxTime = maxTime {
            clickSpamTimerMaxDate = Date().addingTimeInterval(maxTime)
        } else {
            clickSpamTimerMaxDate = nil
        }
        clickSpamTimer?.invalidate()
        clickSpamTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                              repeats: true,
                                              block: { [weak self] timer in
            var expired = false
            if let date = self?.clickSpamTimerMaxDate, date < Date() {
                self?.log(" expired: \(date.timeIntervalSince(Date()))")
                expired = true
            }
            defer {
                if expired { self?.clickSpamTimer?.invalidate() }
            }
            
            if self?.paused == true { return }
            if condition() || expired {
                self?.clickSpamTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    completion?(!expired)
                }
            } else {
                block?()
            }
        })
    }
    //MAKR: - Game
    func start() {
        log("Start")
        
        spam(block: {
            CGEvent.letfClick(position: .chooseButton)
        },
             condition: {
            self.core.game.currentMode == .gameplay
        }, completion: { _ in
            self.preFight()
        }, interval: 0.1)
    }
    
    func preFight() {
        log("Prefight")
        spam (block: {
            CGEvent.letfClick(position: .readyButton)
        }, condition: {
            return self.enemiesReady
        }, completion: { _ in
            self.fight()
        })
    }
    
    func fight() {
        log("Fight")
        
        var playerIndex: Int?
        
        for (index, minion) in playerMinions.enumerated() {
            if !minion.has(tag: .lettuce_ability_tile_visual_self_only) {
                playerIndex = index
                self.log("\(minion.card.role)")
                break
            }
        }
        
        guard let index = playerIndex else {
            spam(block: { CGEvent.letfClick(position: .readyButton, delay: 0.5)},
                 condition: { !self.enemiesReady },
                 completion: { _ in self.preFight() })
            return
        }
        
        let playerPosition = playerViews[index].frame.center.playerScreenCenter
        let enemyPosition = enemyViews.first?.frame.center.enemyScreenCenter ?? .zero
        
        spam(doOnce: {
            CGEvent.letfClick(position: playerPosition) {
                CGEvent.letfClick(position: .firstSkill, delay: 0.5)
            }
        }, condition: {
            self.playerMinions[index].has(tag: .lettuce_ability_tile_visual_self_only)
        }, completion: { success in
            self.log("skill chosen success: \(success)")
            
            if !success {
                CGEvent.letfClick(position: enemyPosition, delay: 0.5) {
                    self.fight()
                }
            } else {
                self.fight()
            }
        }, maxTime: 1)
        
        //        let clickDate = Date()
        
        
        
        //        CGEvent.letfClick(position: .firstSkill) {
        //            CGEvent.letfClick(position: self.core.game.windowManager.playerBoardOverlay.window?.convertPoint(toScreen: self.playerViews.first?.frame.center ?? .zero) ?? .zero) {
        //                CGEvent.letfClick(position: self.core.game.windowManager.playerBoardOverlay.window?.convertPoint(toScreen: self.playerViews.first?.frame.center ?? .zero) ?? .zero) {
        //
        //                }
        //            }
        //        }
    }
}
