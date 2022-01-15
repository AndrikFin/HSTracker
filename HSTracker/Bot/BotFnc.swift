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
    
    func testSerial() {
        for i in stride(from: 100, to: 0, by: -1) {
            addBlock(.delay(TimeInterval(1)))
            addBlock(BlockOperation { log("\(i)")} )
        }
        addBlock(.delay(10))
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
        
        processState()
    }
    
    func processState() {
        guard self.operationQueue.isFinished else { return }
        addBlock { _ in
            DispatchQueue.main.async {
                self.prefightIfNeeded()
                self.fightIfNeeded()
                self.finishFightIfNeeded()
                self.moveToMapIfNeeded()
                self.analyseMapIfNeeded()
                self.selectLevelIfNeeded()
            }
        }
    }
    
    //MARK: - Map
    
    func pickTreasureIfNeeded() {
        guard core.game.currentMode == .lettuce_map && screenState == .pickOneTreasure else { return }
        
        addBlock { _ in
            self.click(position: .firstBonusButton)
            self.delay(time: 0.2)
            self.click(position: .bonusTakeButton)
            self.delay(time: 0.2)
            self.addBlock { _ in
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
        addBlock { _ in
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
            self.addBlock(.scroll(top: false))
            self.addBlock(.delay(0.2))
            self.addBlock { _ in
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
        
        ImageRecognitionHelper.analyzeReadyButton { values in
            log("option to select: \(values)")
            self.readyButtonState = .none
            for value in values {
                let state = ReadyButtonState.closestTypeTo(value.0)
                if state != .none {
                    self.readyButtonState = state
                    
                    if state == .visit || state == .lordBanehollow {
                        self.click(position: .chooseButton)
                        self.delay(time: 4)
                        self.addBlock { _ in
                            self.selectingLevel = false
                        }
                        return
                    }
                }
            }
            self.addBlock { _ in
                self.analyseRow(point: .mapFrom) { type, finished in
                    log("select analyzing for mystery type: \(String(describing: type)) finished: \(finished)")
                    type.map{ currentRowTypes.append($0) }
                    if finished {
                        self.addBlock { _ in
                            self.loopThroughLevels(containsMystery: currentRowTypes.filter({$0.isMystery}).count > 0)
                        }
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
                self.cleanUp(keepMap: true)
                self.selectingLevel = false
                return
            }
            
            if finished {
                hasMystery = false
            }
            self.addBlock { _ in
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
                                self.addBlock { _ in
                                    self.cleanUp(keepMap: true)
                                    self.processState()
                                }
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    
    func selectBoss() {
        addBlock(.click(.bossIcon))
        addBlock(.delay(0.2))
        addBlock(.click(.chooseButton))
    }
    
    
    var screenState: StateByTextType = .undefined
    func checkScreenState() {
        guard operationQueue.isFinished else { return }
        
        addBlock(BotFnc.globalTextType { state, point  in
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
                self.addBlock { _ in
                    self.processState()
                }
            case .battleSpoils: self.click(position: .finalScreenButton)
            case .lockIn:
                guard self.core.game.currentMode == .lettuce_bounty_team_select else { return }
                self.addBlock { _ in
                    self.delay(time: 0.1)
                    self.click(position: .lockInButton)
                }
            }
        })
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
    
    func addBlock(_ exCode: @escaping ((OperationQueue?)->Void)) {
        operationQueue.waitAndAddBlock { [weak operationQueue] in
            exCode(operationQueue)
        }
    }
    
    //MARK: - Fight
    
    var operationQueue: OperationQueue = .serialOpertaionQueue()
    
    func finishFightIfNeeded() {
        guard core.game.step == .final_gameover && core.game.currentMode == .gameplay else { return }
        log("finishFight")
        
        click(position: .testButton)
        delay(time: 0.4)
        addBlock { _ in
            self.cleanUp(keepMap: true)
            self.processState()
        }
    }
    
    func prefightIfNeeded() {
        guard core.game.currentMode == .gameplay && !core.game.enemiesReady && core.game.step == .main_action else { return }
        log("prefight")
        
        addBlock(.delay(0.4))
        if !self.core.game.enemiesReady {
            self.addBlock(.click(.readyButton))
            self.addBlock(.delay(0.2))
            self.addBlock { _ in
                self.processState()
            }
        } else {
            self.addBlock(.delay(0.2))
            self.addBlock { _ in
                self.processState()
            }
        }
    }
    
    var inFight = false
    func fightIfNeeded() {
        guard operationQueue.isFinished && !inFight else { return }
        if core.game.currentMode == .gameplay && core.game.enemiesReady && core.game.playerIsReady && core.game.step == .main_action {
            log("All players are ready")
            self.inFight = false
            addBlock(.click(.readyButton))
            addBlock(.delay(0.4))
            addBlock { _ in
                self.processState()
            }
            return
        }
        guard core.game.currentMode == .gameplay && core.game.enemiesReady && !core.game.playerIsReady && core.game.step == .main_action else {
            self.inFight = false
            return
        }
        log("Fight")
        inFight = true
        
        addBlock { opQ in
            DispatchQueue.main.async {
                let playerIndex = self.core.game.availalbeMinions.firstIndex(where: { !$0.has(tag: .lettuce_ability_tile_visual_self_only) })
                log("Player index: \(String(describing: playerIndex))")
                
                guard let index = playerIndex else {
                    self.inFight = false
                    self.processState()
                    return
                }
                
                let playerMinion = self.core.game.availalbeMinions[index]
                log("Player role: \(playerMinion.card.role), \(playerMinion.card.jsonRepresentation["mercenariesRole"] as? Int ?? 0)")
                
                let enemyIndex = self.core.game.enemyMinions.firstIndex(where: { $0.card.role.critFrom == playerMinion.card.role}) ?? self.core.game.enemyMinions.firstIndex(where: { $0.card.role.critTo == playerMinion.card.role}) ?? 0
                
                let playerPosition = self.core.game.playerViews[index].frame.center.playerScreenCenter
                let enemyPosition = self.core.game.enemyViews[enemyIndex].frame.center.enemyScreenCenter
                self.addBlock { _ in
                    self.delay(time: 1)
                    self.click(position: .firstSkill)
                    self.delay(time: 0.3)
                    
                    self.addBlock { _ in
                        if !self.core.game.availalbeMinions[index].has(tag: .lettuce_ability_tile_visual_self_only) {
                            self.addBlock(.click(enemyPosition))
                            self.addBlock(.delay(0.3))
                        }
                        
                        self.addBlock { _ in
                            if !self.core.game.availalbeMinions[index].has(tag: .lettuce_ability_tile_visual_self_only) {
                                self.addBlock(.click(playerPosition))
                                self.addBlock(.delay(0.3))
                            }
                            
                            self.addBlock(.delay(0.3))
                            self.addBlock { _ in
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
