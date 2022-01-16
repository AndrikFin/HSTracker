//
//  BotFnc.swift
//  HSTracker
//
//  Created by AO on 30.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import SwiftUI
import XCTest

func log(_ value: Any) {
    print("👑 \(Date()) \(value)")
}

class BotFnc {
    enum ReadyButtonState: String, CaseIterable {
        case none, play, reveal, visit, warp, pickUp, spudME2, lordBanehollow
        
        static func closestTypeTo(_ string: String) -> ReadyButtonState {
            return ReadyButtonState.allCases.first(where: {
                return jaroWinkler($0.rawValue, string.camelized) > 0.95
            }) ?? .none
        }
    }
    
    var readyButtonState: ReadyButtonState = .none {
        didSet {
            log("\(readyButtonState)")
        }
    }
    var prevReadyButtonState: ReadyButtonState = .none
    
    var core: CoreManager {
        return AppDelegate.instance().coreManager
    }
    
    static var hearthStoneApp: NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })
    }
    
    var prevStep: Step = .invalid
    var stepChangeDate: Date = Date.distantPast
    var prevGameMode: Mode = .invalid
    var ping: Date = Date()
    var paused: Bool = false {
        didSet {
            if paused {
                operationQueue.progress.pause()
            } else {
                operationQueue.progress.resume()
            }
        }
    }
    
    init() {
        subscribeToEvents()
        checkScreenState()
        operationQueue.progress.cancellationHandler = {
            self.operationQueue.progress.totalUnitCount = 0
        }
        
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            DispatchQueue.main.async {
                if fabs(self.ping.timeIntervalSinceNow) > 60 * 5 {
                    self.cleanUp()
                }
                self.checkScreenState()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: Events.space_changed), object: nil, queue: nil) { not in
            self.cleanUp(keepMap: true)
            self.processState()
        }
    }
    
    var mapInfo: MapInfo? {
        didSet {
            if mapInfo == nil {
                log("mapInfo: is nil")
            }
        }
    }
    
    func updateState() {
        DispatchQueue.main.async {
            if self.prevStep != self.core.game.step {
                self.prevStep = self.core.game.step
                self.stepDidChange()
            }
            if self.prevGameMode != self.core.game.currentMode ?? .invalid {
                self.prevGameMode = self.core.game.currentMode ?? .invalid
                self.modeDidChange()
            }
        }
    }
    
    func cleanUp(keepMap: Bool = false) {
        operationQueue.cancel()
        operationQueue = .serialOpertaionQueue()
        analizingMap = false
        selectingLevel = false
        paused = false
        inFight = false
        if !keepMap {
            mapInfo = nil
        }
    }
    
    func subscribeToEvents() {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            
            if event.modifierFlags.isSuperset(of: [.option, .command]) {
                switch event.type {
                case .leftMouseDown:
                    log("mouse down proportion: \(event.locationInWindow.toEuqlid.proportionalPoint)")
                    log("mouse down: \(event.locationInWindow)")
                    log("mouse down hs: \(event.locationInWindow.toHSPoint)")
                    log("mouse down hs: \(ImageRecognitionHelper.avarageColor(event.locationInWindow.toEuqlid))")
                    ImageRecognitionHelper.DetecktMapCircles() { strings in
                        log("\(strings)")
                    }
                case .keyDown:
                    switch event.keyCode {
                    case 1:
                        self?.cleanUp()
                        self?.processState()
                    case 0:
                        self?.selectLevelIfNeeded()
                    case 35: self?.paused.toggle()
                    default: break
                    }
                default: break
                }
            }
        }
    }
    
    //MARK: - lifecycle
    
    func modeDidChange() {
        log("mode: \(core.game.currentMode ?? .invalid)")
        ping = Date()
        operationQueue.cancel()
        processState()
        
        let currentMode = core.game.currentMode ?? .invalid
        
        if currentMode != .gameplay {
            inFight = false
        }
        
        if ![.gameplay, .lettuce_map].contains(currentMode) {
            mapInfo = nil
        }
        
        switch currentMode {
        case .gameplay:
            analizingMap = false
            selectingLevel = false
            if !inFight {
                cleanUp(keepMap: true)
            }
        default: break
        }
        
        //        if [.lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode ?? .invalid) {
        //            mapInfo = nil
        //            delay(0.4) {
        //                CGEvent.letfClick(position: .chooseButton) {
        //                    self.delay(0.4, type: .map) {
        //                        self.checkCurrentStateAndProcess()
        //                    }
        //                }
        //            }
        //        }
        //
        //        if ![Mode.lettuce_map, .lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode) {
        //            stopTimers(.map)
        //            selectingLevel = false
        //            analyzing = false
        //            checkingMapState = false
        //            if core.game.currentMode != .gameplay {
        //                mapInfo = nil
        //            }
        //        }
        //
        //        if core.game.currentMode != .lettuce_map {
        //            readyButtonState = .none
        //        }
        //
        //        if core.game.currentMode != .gameplay {
        //            stopTimers(.fight)
        //        }
        //
        //        if core.game.currentMode == .lettuce_map {
        //            stopTimers(.fight)
        //            checkMapState()
        //        }
        //
        //        if core.game.currentMode == .gameplay {
        //            preFight()
        //        }
    }
    
    func stepDidChange() {
        log("step: \(core.game.step)")
        stepChangeDate = Date()
        ping = Date()
        
        if self.core.game.step == .main_combat {
            self.cleanUp(keepMap: true)
        }
        processState()
    }
    
    func processState() {
        guard self.operationQueue.isFinished else { return }
            DispatchQueue.main.async {
                self.prefightIfNeeded()
                self.fightIfNeeded()
                self.finishFightIfNeeded()
                self.moveToMapIfNeeded()
                self.analyseMapIfNeeded()
                self.selectLevelIfNeeded()
        }
    }
    
    //MARK: - Map
    
    func pickTreasureIfNeeded() {
        guard core.game.currentMode == .lettuce_map && screenState == .pickOneTreasure else { return }
        
        addBlock {
            self.click(position: .firstBonusButton)
            self.delay(time: 0.2)
            self.click(position: .bonusTakeButton)
            self.delay(time: 0.2)
            self.addBlock {
                self.processState()
            }
        }
    }
    
    func pickVisitor() {
        guard core.game.currentMode == .lettuce_map && screenState == .pickVisitor else { return }
        click(position: .firstVisitor)
        delay(time: 0.2)
        click(position: .mysteryChooseButton)
        delay(time: 0.2)
        addBlock {
            self.processState()
        }
    }
    
    func moveToMapIfNeeded() {
        guard [.lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode) else { return }
        
        if core.game.currentMode == .lettuce_bounty_board {
            click(position: .bountySixButton)
            delay(time: 0.2)
        }
        click(position: .chooseButton)
        delay(time: 0.2)
    }
    
    var analizingMap = false
    func analyseMapIfNeeded() {
        guard core.game.currentMode == .lettuce_map && screenState == .viewParty && mapInfo == nil && !analizingMap else { return }
        cleanUp(keepMap: true)
        analizingMap = true
        analyzeMap {
            self.analizingMap = false
            self.delay(time: 0.2)
            self.addBlock(.scroll(top: false))
            self.addBlock {
                self.processState()
            }
        }
    }
    
    var selectingLevel = false
    func selectLevelIfNeeded() {
        guard !selectingLevel && core.game.currentMode == .lettuce_map && screenState == .viewParty && mapComplete && !analizingMap else { return }
        selectingLevel = true
        var currentRowTypes: [MapLevelType] = []
        log("going to select raw")
        
        addBlock(.readyButtonText() { states in
            log("option to select: \(states)")
            self.readyButtonState = .none
            for state in states {
                if state != .none {
                    self.readyButtonState = state
                    self.selectingLevel = false
                    self.selectActiveLevel()
                    return
                }
            }
            
            self.addBlock {
                guard self.selectingLevel else { return }
                self.analyseRow(point: .mapFrom) { type, finished in
                    guard self.selectingLevel else { return }
                    log("select analyzing for mystery type: \(String(describing: type)) finished: \(finished)")
                    type.map{ currentRowTypes.append($0) }
                    if finished {
                        self.addBlock {
                            guard self.selectingLevel else { return }
                            self.loopThroughLevels(containsMystery: currentRowTypes.filter({$0.isMystery}).count > 0)
                        }
                    }
                }
            }
        })
    }
    
    func loopThroughLevels(containsMystery: Bool) {
        guard selectingLevel else { return }
        var hasMystery = containsMystery
        self.scrollAndSelect(loop: 0) { finished, loop in
            guard self.selectingLevel else { return }
            log("loop: \(loop)")
            if loop > 7 {
                self.selectingLevel = false
                return
            }
            
            if finished {
                hasMystery = false
            }
            
            self.addBlock(.readyButtonText() { states in
                guard self.selectingLevel else { return }
                log("option to select: \(states)")
                self.readyButtonState = .none
                for state in states {
                    if state != .none {
                        self.readyButtonState = state
                        
                        if (!containsMystery && state != .none) || (hasMystery && state == .visit) {
                            self.selectingLevel = false
                            self.operationQueue.cancel()
                            self.selectActiveLevel()
                            return
                        }
                    }
                }
            })
        }
    }
    
    func selectActiveLevel() {
        click(position: .chooseButton)
        delay(time: 2)
        click(position: .chooseButton)
        delay(time: 4)
        addBlock {
            self.processState()
        }
    }
    
    func selectBoss() {
        click(position: .bossIcon)
        delay(time: 0.2)
        click(position: .chooseButton)
    }
    
    
    var screenState: StateByTextType = .undefined
    func checkScreenState() {
        guard operationQueue.isFinished else { return }
        
        addBlock(.globalTextType(callback: { state, _ in
            if self.screenState != state {
                self.screenState = state
                self.screenStateDidChange()
            }
            switch state {
            case .undefined: break
            case .taskObtained:
                self.click(position: .mapFrom)
            case .victory:
                self.delay(time: 1)
                self.openBoxes()
            case .felwoodBounties, .chooseParty: self.moveToMapIfNeeded()
            case .bountyComplete: self.click(position: .finalScreenButton)
            case .clickToContinue: break
            case .pickVisitor: self.pickVisitor()
            case .pickOneTreasure: self.pickTreasureIfNeeded()
            case .viewParty:
                self.delay(time: 1)
                self.addBlock {
                    self.processState()
                }
            case .consolationCoins:
                self.click(position: .finalScreenButton)
                self.delay(time: 0.2)
                self.addBlock {
                    self.processState()
                }
            case .battleSpoils: self.click(position: .finalScreenButton)
            case .lockIn:
                guard self.core.game.currentMode == .lettuce_bounty_team_select else { return }
                self.addBlock {
                    self.delay(time: 0.1)
                    self.click(position: .lockInButton)
                }
            }
        }))
    }
    
    func openBoxes() {
        operationQueue.cancel()
        for i in 0...4 {
            delay(time: 0.2)
            click(position: .boxesButtons[i])
        }
        
        delay(time: 0.5)
        click(position: .bonusDoneButton)
        click(position: .finalScreenButton)
    }
    
    func screenStateDidChange() {
        log("state did change \(self.screenState)")
    }
    
    func delay(time: TimeInterval) {
        addBlock(.delay(time))
    }
    
    func click(position: NSPoint) {
        addBlock(.click(position))
    }
    
    func addBlock(_ block: BlockOperation) {
        operationQueue.waitAndAddBlock(block)
    }
    
    func addBlock(_ exCode: @escaping (()->Void)) {
        operationQueue.waitAndAddBlock {
            exCode()
        }
    }
    
    //MARK: - Fight
    
    var operationQueue: OperationQueue = .serialOpertaionQueue()
    
    func finishFightIfNeeded() {
        guard core.game.step == .final_gameover && core.game.currentMode == .gameplay && !inFight else { return }
        log("finishFight")
        
        click(position: .testButton)
        delay(time: 0.4)
        addBlock {
            self.processState()
        }
    }
    
    func prefightIfNeeded() {
        addBlock {
            guard self.core.game.currentMode == .gameplay && !self.core.game.enemiesReady && self.core.game.step == .main_action && !self.inFight else { return }
            log("prefight")
            
            self.delay(time: 0.4)
            self.addBlock {
                if !self.core.game.enemiesReady {
                    self.click(position: .readyButton)
                    self.delay(time: 0.2)
                    self.addBlock {
                        self.processState()
                    }
                } else {
                    self.delay(time: 0.2)
                    self.addBlock {
                        self.processState()
                    }
                }
            }
        }
    }
    
    var firstUnreadyIndex: Int? {
        return self.core.game.availalbeMinions.firstIndex(where: { !$0.ready })
    }
    
    func firstEnemyIndexForRole(role: Card.MercenaryRole) -> Int {
        return self.core.game.enemyMinions.firstIndex(where: { $0.card.role.critFrom == role}) ?? self.core.game.enemyMinions.firstIndex(where: { $0.card.role.critTo == role}) ?? 0
    }
    
    func playerPosition(index: Int) -> NSPoint {
        let sem = DispatchSemaphore(value: 0)
        var position: NSPoint = .zero
        DispatchQueue.main.async {
            position = self.core.game.playerViews[index].frame.center.playerScreenCenter
            sem.signal()
        }
        sem.wait()
        return position
    }
    
    var enemyPosition: NSPoint {
        let sem = DispatchSemaphore(value: 0)
        var position: NSPoint = .zero
        DispatchQueue.main.async {
            let role = self.core.game.availalbeMinions.first(where: { !$0.ready })?.card.role ?? .none
            position = self.core.game.enemyViews[self.firstEnemyIndexForRole(role: role)].frame.center.enemyScreenCenter
            sem.signal()
        }
        sem.wait()
        return position
    }
    
    var inFight = false
    func fightIfNeeded() {
        addBlock {
            if self.core.game.currentMode == .gameplay && self.core.game.enemiesReady && self.core.game.playerIsReady && self.core.game.step == .main_action && self.inFight {
                log("All players are ready")
                self.click(position: .readyButton)
                self.delay(time: 0.4)
                self.addBlock {
                    self.operationQueue.cancel()
                    self.inFight = false
                    self.processState()
                }
                return
            }
            guard self.core.game.currentMode == .gameplay && self.core.game.enemiesReady && !self.core.game.playerIsReady && self.core.game.step == .main_action else {
                self.addBlock {
                    self.operationQueue.cancel()
                    self.processState()
                }
                return
            }
            guard !self.inFight else { return }
            log("Fight")
            self.addBlock {
                self.inFight = true
            }
            
            self.addBlock {
                guard self.inFight else { return }
                
                guard let index = self.firstUnreadyIndex else {
                    self.inFight = false
                    self.processState()
                    return
                }
                let playerPosition = self.playerPosition(index: index)
                log("Player index: \(String(describing: self.firstUnreadyIndex))")
                
                let checkConditon:(()->Bool) = {
                    guard self.inFight && !self.core.game.availalbeMinions[index].ready else {
                        self.inFight = false
                        self.cleanUp(keepMap: true)
                        self.processState()
                        return false
                    }
                    return true
                }
                
                let fightDelay = 0.5
                self.addBlock {
                    self.delay(time: fightDelay)
                    self.click(position: .firstSkill)
                    self.delay(time: fightDelay)
                    
                    self.addBlock {
                        guard checkConditon() else { return }
                        self.click(position: self.enemyPosition)
                        self.delay(time: fightDelay)
                        
                        self.addBlock {
                            guard checkConditon() else { return }
                            self.click(position: playerPosition)
                            self.delay(time: fightDelay)
                            self.addBlock{
                                self.inFight = false
                                self.processState()
                            }
                        }
                    }
                }
            }
        }
    }
}

//var serialQueue = DispatchQueue(label: "com.bot.queue")
