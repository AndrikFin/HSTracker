//
//  BotFnc.swift
//  HSTracker
//
//  Created by AO on 30.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation
import SwiftUI

func log(_ value: Any) {
    print("👑 \(Date()) \(value)")
}

class BotFnc {
    enum ReadyButtonState: String, CaseIterable {
        case none, play, reveal, visit, warp, pickUp, spudME2
        
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
    var ping: Date = Date.distantPast
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
                self.checkScreenState()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: Events.space_changed), object: nil, queue: nil) { not in
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
    
    func cleanUp() {
        operationQueue.cancel()
        operationQueue = .serialOpertaionQueue()
        analizingMap = false
        selectingLevel = false
        paused = false
        mapInfo = nil
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
    
    func testSerial() {
        for i in stride(from: 100, to: 0, by: -1) {
            operationQueue.addBlock(.delay(TimeInterval(1)))
            operationQueue.addBlock(BlockOperation { log("\(i)")} )
        }
        operationQueue.addBlock(.delay(10))
        operationQueue.waitUntilAllOperationsAreFinished()
        log("all operations finished")
    }
    
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
        
        if prevGameMode == .lettuce_map && currentMode == .lettuce_bounty_board {
            cleanUp()
        }
        
        switch currentMode {
        case .gameplay:
            analizingMap = false
            selectingLevel = false
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
        
        processState()
    }
    
    func processState() {
        //        guard self.operationQueue.isFinished else { return }
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
        
        operationQueue.waitAndAddBlock {
            self.click(position: .firstBonusButton)
            self.delay(time: 0.2)
            self.click(position: .bonusTakeButton)
            self.delay(time: 0.2)
            self.operationQueue.waitAndAddBlock{
                self.processState()
            }
        }
    }
    
    func pickVisitor() {
        guard core.game.currentMode == .lettuce_map && screenState == .pickOneTreasure else { return }
        
            self.click(position: .firstVisitor)
            self.delay(time: 0.2)
            self.click(position: .mysteryChooseButton)
            self.delay(time: 0.2)
            self.operationQueue.waitAndAddBlock{
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
        analizingMap = true
        
        analyzeMap {
            self.analizingMap = false
            self.operationQueue.addBlock(.scroll(top: false))
            self.operationQueue.addBlock(.delay(0.2))
            self.operationQueue.addBlock {
                self.operationQueue.cancel()
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
        operationQueue.waitAndAddBlock {
            self.analyseRow(point: .mapFrom) { type, finished in
                log("select analyzing for mystery type: \(String(describing: type)) finished: \(finished)")
                type.map{ currentRowTypes.append($0) }
                if finished {
                    self.operationQueue.waitAndAddBlock {
                        self.loopThroughLevels(containsMystery: currentRowTypes.filter({$0.isMystery}).count > 0)
                    }
                }
            }
        }
    }
    
    func loopThroughLevels(containsMystery: Bool) {
        guard selectingLevel else { return }
        var hasMystery = containsMystery
        self.scrollAndSelect(loop: 0) { finished, loop in
            log("loop: \(loop)")
            if loop > 7 {
                self.operationQueue.cancel()
                self.selectBoss()
                return
            }
            if finished {
                hasMystery = false
            }
            self.operationQueue.waitAndAddBlock {
                ImageRecognitionHelper.analyzeReadyButton { values in
                    log("option to select: \(values)")
                    self.readyButtonState = .none
                    for value in values {
                        let state = ReadyButtonState.closestTypeTo(value.0)
                        if state != .none {
                            self.readyButtonState = state
                            
                            if (!containsMystery && state != .none) || (hasMystery && state == .visit) {
                                self.click(position: .chooseButton)
                                self.delay(time: 4)
                                self.selectingLevel = false
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    
    func selectBoss() {
        operationQueue.addBlock(.click(.bossIcon))
        operationQueue.addBlock(.delay(0.2))
        operationQueue.addBlock(.click(.chooseButton))
    }
    
    
    var screenState: StateByTextType = .undefined
    func checkScreenState() {
        guard operationQueue.isFinished else { return }
        
        operationQueue.addBlock(BotFnc.globalTextType { state, point  in
            if self.screenState != state {
                self.screenState = state
                self.screenStateDidChange()
            }
            switch state {
            case .undefined:
                break
            case .victory: self.openBoxes()
            case .felwoodBounties, .chooseParty: self.moveToMapIfNeeded()
                break
            case .bountyComplete: self.click(position: .finalScreenButton)
                break
            case .clickToContinue:
                break
            case .pickVisitor:
                break
            case .pickOneTreasure: self.pickTreasureIfNeeded()
            case .viewParty: self.processState()
            case .battleSpoils: self.click(position: .finalScreenButton)
            case .lockIn:
                guard self.core.game.currentMode == .lettuce_bounty_team_select else { return }
                self.operationQueue.addBlock {
                    self.operationQueue.cancel()
                    self.operationQueue.addBlock(.delay(0.1))
                    self.operationQueue.addBlock(.click(.lockInButton))
                }
            }
        })
    }
    
    func openBoxes() {
        for i in 0...4 {
            delay(time: 0.2)
            click(position: CGPoint.boxesButtons[i])
        }
        
        delay(time: 0.2)
        click(position: .bonusDoneButton)
        click(position: .finalScreenButton)
    }
    
    func screenStateDidChange() {
        log("state did change \(self.screenState)")
    }
    
    func delay(time: TimeInterval) {
        operationQueue.waitAndAddBlock(.delay(time))
    }
    
    func click(position: NSPoint) {
        operationQueue.waitAndAddBlock(.click(position))
    }
    
    //MARK: - Fight
    
    var operationQueue: OperationQueue = .serialOpertaionQueue()
    
    func finishFightIfNeeded() {
        guard core.game.step == .final_gameover && core.game.currentMode == .gameplay else { return }
        log("finishFight")
        
        click(position: .testButton)
        delay(time: 0.4)
        operationQueue.addBlock {
            self.operationQueue.cancel()
            self.processState()
        }
    }
    
    func prefightIfNeeded() {
        guard core.game.currentMode == .gameplay && !core.game.enemiesReady && core.game.step == .main_action else { return }
        log("prefight")
        
        operationQueue.addBlock(.delay(0.4))
        if !self.core.game.enemiesReady {
            self.operationQueue.addBlock(.click(.readyButton))
            self.operationQueue.addBlock(.delay(0.2))
            self.operationQueue.addBlock {
                self.processState()
            }
        } else {
            self.operationQueue.addBlock(.delay(0.2))
            self.operationQueue.addBlock {
                self.processState()
            }
        }
    }
    
    var inFight = false
    func fightIfNeeded() {
        guard operationQueue.isFinished && !inFight else { return }
        inFight = true
        
        if core.game.currentMode == .gameplay && core.game.enemiesReady && core.game.playerIsReady && core.game.step == .main_action {
            log("All players are ready")
            operationQueue.cancel()
            operationQueue.addBlock(.click(.readyButton))
            operationQueue.addBlock(.delay(0.4))
            operationQueue.addBlock {
                self.inFight = false
                self.processState()
            }
            return
        }
        guard core.game.currentMode == .gameplay && core.game.enemiesReady && !core.game.playerIsReady && core.game.step == .main_action else {
            self.inFight = false
            return
        }
        log("Fight")
        
        let playerIndex = core.game.availalbeMinions.firstIndex(where: { !$0.has(tag: .lettuce_ability_tile_visual_self_only) })
        log("Player index: \(String(describing: playerIndex))")
        
        guard let index = playerIndex else {
            self.inFight = false
            self.processState()
            return
        }
        
        let playerMinion = core.game.availalbeMinions[index]
        log("Player role: \(playerMinion.card.role), \(playerMinion.card.jsonRepresentation["mercenariesRole"] as? Int ?? 0)")
        
        let enemyIndex = core.game.enemyMinions.firstIndex(where: { $0.card.role.critFrom == playerMinion.card.role}) ?? core.game.enemyMinions.firstIndex(where: { $0.card.role.critTo == playerMinion.card.role}) ?? 0
        
        let playerPosition = core.game.playerViews[index].frame.center.playerScreenCenter
        let enemyPosition = core.game.enemyViews[enemyIndex].frame.center.enemyScreenCenter
        
        delay(time: 0.5)
        click(position: .firstSkill)
        delay(time: 0.3)
        
        operationQueue.addBlock {
            if !playerMinion.has(tag: .lettuce_ability_tile_visual_self_only) {
                self.operationQueue.addBlock(.click(enemyPosition))
                self.operationQueue.addBlock(.delay(0.3))
            }
            
            self.operationQueue.addBlock {
                if !playerMinion.has(tag: .lettuce_ability_tile_visual_self_only) {
                    self.operationQueue.addBlock(.click(playerPosition))
                    self.operationQueue.addBlock(.delay(0.3))
                }
                
                self.operationQueue.addBlock(.delay(0.3))
                self.operationQueue.addBlock {
                    self.inFight = false
                    self.processState()
                }
            }
        }
    }
}

//var serialQueue = DispatchQueue(label: "com.bot.queue")
