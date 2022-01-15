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
import IOKit
import IOKit.pwr_mgt

class Bot {
    var core: CoreManager {
        return AppDelegate.instance().coreManager
    }
    
    static var hearthStoneApp: NSRunningApplication? {
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "unity.Blizzard Entertainment.Hearthstone" })
    }
    
    init() {
        subscribeToEvents()
        
        let reasonForActivity = "Reason for activity" as CFString
        var assertionID: IOPMAssertionID = 0
        var success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                   IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                   reasonForActivity,
                                                   &assertionID )
        if success == kIOReturnSuccess {
            // Add the work you need to do without the system sleeping here.
            
            success = IOPMAssertionRelease(assertionID);
            // The system will be able to sleep again.
        }
        
//        Timer.scheduledTimer(withTimeInterval: maxIdleTimeInterval, repeats: true) { timer in
//            let modeIdle = fabs(self.gameModeChangeDate.timeIntervalSince(Date())) > self.maxIdleTimeInterval
//            let fightIdle = fabs(self.stepChangeDate.timeIntervalSince(Date())) > self.maxIdleTimeInterval
//            if modeIdle && [.lettuce_map, .lettuce_bounty_board, .lettuce_bounty_team_select, .invalid].contains(self.core.game.currentMode) {
//                self.start()
//            }
//            if fightIdle && [.gameplay, .invalid].contains(self.core.game.currentMode) {
//                self.start()
//            }
//        }
    }
    
    var pingDate: Date = Date()
    var prevStep: Step = .invalid
    var stepChangeDate: Date = Date.distantPast
    var prevGameMode: Mode = .invalid
    var gameModeChangeDate: Date = Date.distantPast
    
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
            
            if self.core.game.step == .main_action {
                if Date().timeIntervalSince(self.pingDate) > 0.5 {
                    self.log("ping")
                }
                self.pingDate = Date()
            }
        }
    }
    
    func cleanUp() {
        stopAllTimers()
        clickSpamTimer?.invalidate()
        paused = false
        analyzing = false
        selectingLevel = false
        checkingMapState = false
        mapInfo = nil
    }
    
    let maxIdleTimeInterval: TimeInterval = 30
    
    func modeDidChange() {
        log("mode: \(core.game.currentMode ?? .invalid)")
        gameModeChangeDate = Date()
        
        if [.lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode ?? .invalid) {
            mapInfo = nil
            delay(0.4, type: .map) {
                CGEvent.letfClick(position: .chooseButton) {
                    self.delay(0.4, type: .map) {
                        self.checkCurrentStateAndProcess()
                    }
                }
            }
        }
        
        if ![Mode.lettuce_map, .lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode) {
            stopTimers(.map)
            selectingLevel = false
            analyzing = false
            checkingMapState = false
            if core.game.currentMode != .gameplay {
                mapInfo = nil
            }
        }
        
        if core.game.currentMode != .lettuce_map {
            readyButtonState = .none
        }
        
        if core.game.currentMode != .gameplay {
            stopTimers(.fight)
        }
        
        if core.game.currentMode == .lettuce_map {
            stopTimers(.fight)
            checkMapState()
        }
        
        if core.game.currentMode == .gameplay {
            preFight()
        }
    }
    
    func stepDidChange() {
        log("step: \(core.game.step)")
        stepChangeDate = Date()
        gameModeChangeDate = Date()
        if core.game.step == .final_gameover {
            spam(block: {
                CGEvent.letfClick(position: .disconnectOKButton)
            }, condition: {
                self.core.game.currentMode != .gameplay
            }, completion: { _ in
                self.checkMapState()
            })
        }
        if core.game.step == .main_action && prevStep == .main_pre_action && core.game.currentMode == .gameplay {
            preFight()
        }
    }
    
    func stopTimers(_ type: DelayType) {
        log("stop timers: \(type)")
        var timers = timersFor(type)
        timers.forEach{$0.invalidate()}
        timers.removeAll()
        clickSpamTimer?.invalidate()
    }
    
    func stopAllTimers() {
        DelayType.allCases.forEach({ self.stopTimers($0) })
    }
    
    var playerMinions: [Entity] {
        return core.game.player.board.filter({$0.isMinion && [0, 1, 2].contains($0.card.role)}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var allPlayerMinions: [Entity] {
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
    
    typealias MapInfo = [Int: [MapLevelType]]
    var mapInfo: MapInfo? {
        didSet {
            if mapInfo == nil {
                log("mapInfo: is nil")
            }
        }
    }
    func processMapInfo(_ info: MapInfo) {
        info.prettyDescription()
    }
    
    func chooseFirstBonus(completion: @escaping (()->Void)) {
        CGEvent.letfClick(position: .firstBonusButton, delay: 0.4) {
            CGEvent.letfClick(position: .bonusTakeButton, delay: 0.4) {
                completion()
            }
        }
    }
    
    func chooseFirstVisitor(completion: @escaping (()->Void)) {
        CGEvent.letfClick(position: .firstVisitor, delay: 0.4) {
            CGEvent.letfClick(position: .mysteryChooseButton, delay: 0.4) {
                CGEvent.letfClick(position: .mapTo, delay: 1) {
                    completion()
                }
            }
        }
    }
    
    func openBoxes(completion: @escaping (()->Void)) {
        stopTimers(.map)
        
        delay(0.4, type: .map) {
            CGEvent.letfClick(position: .boxesButtons[0])
            self.delay(0.4, type: .map) {
                CGEvent.letfClick(position: .boxesButtons[1])
                self.delay(0.4, type: .map) {
                    CGEvent.letfClick(position: .boxesButtons[2])
                    self.delay(0.4, type: .map) {
                        CGEvent.letfClick(position: .boxesButtons[3])
                        self.delay(0.4, type: .map) {
                            CGEvent.letfClick(position: .boxesButtons[4])
                            self.delay(1, type: .map) {
                                CGEvent.letfClick(position: .bonusDoneButton)
                                self.delay(4, type: .map) {
                                    CGEvent.letfClick(position: .finalScreenButton)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
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
    
    func processReadyButton(completion: @escaping ((Bool)->Void)) {
        ImageRecognitionHelper.analyzeReadyButton { strings in
            self.prevReadyButtonState = self.readyButtonState
            self.readyButtonState = .none
            for string in strings {
                let state = ReadyButtonState.closestTypeTo(string)
                if state != .none {
                    self.readyButtonState = state
                }
            }
            completion(self.readyButtonState != self.prevReadyButtonState)
        }
    }
    
    var isCheckingCurretnLevelOnMistery = false
    func checkCurrentLevelOnMistery(completion: @escaping ((Bool)->Void)) {
        guard !isCheckingCurretnLevelOnMistery else { return }
        self.isCheckingCurretnLevelOnMistery = true
        log("check if level contains mystery")
        func stride(point: NSPoint) {
            guard self.core.game.currentMode == .lettuce_map && self.isCheckingCurretnLevelOnMistery else { return }
            var finished = false
            if mapInfo?.mysteryPosition ?? .left == .left {
                finished = point.x >= NSPoint.mapTo.x
            } else {
                finished = point.x <= NSPoint.mapFrom.x
            }
            
            guard !finished else {
                isCheckingCurretnLevelOnMistery = false
                completion(false)
                return
            }
            CGEvent.move(position: point, delay: 0.2) {
                ImageRecognitionHelper.DetecktMapCircles() { pointStrings in
                    guard self.core.game.currentMode == .lettuce_map && self.isCheckingCurretnLevelOnMistery else { return }
                    let type: MapLevelType = .invalid
                    for string in pointStrings {
                        if string.count > 6, let loopType = MapLevelType(string: string), loopType != .invalid {
                            self.log("string \(string)")
                            if type == .mystery {
                                self.isCheckingCurretnLevelOnMistery = false
                                completion(true)
                                return
                            }
                            break
                        }
                    }
                    stride(point: self.nextStepPoint(point))
                }
            }
        }
        stride(point: self.nextStepPoint(self.mapInfo?.mysteryPosition ?? .left == .left ? .mapFrom : .mapTo))
    }
    
    
    
    var checkingMapState = false
    func checkMapState() {
        guard !checkingMapState else { return }
        log("Mirror merc mapInfo: \(String(describing: MirrorHelper.getMercenariesMapInfo()))")
        checkingMapState = true
        log("check map state")
        ImageRecognitionHelper.recognizeGlobalText { strings in
            self.checkingMapState = false
            guard self.core.game.currentMode == .lettuce_map else { return }
            self.log("recognized map state: \(strings)")
            
            if let _ = strings.first(where: { jaroWinkler($0, "Victor") > 0.95 || jaroWinkler($0, "Victors") > 0.95 || jaroWinkler($0, "Victory") > 0.95}) {
                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
                    self.delay(10) {
                        self.openBoxes {
                            self.gameModeChangeDate = Date()
                            self.checkMapState()
                        }
                    }
                }
            } else if let _ = strings.first(where: { jaroWinkler($0, "Bounty Complete!") > 0.95 }) {
                CGEvent.letfClick(position: .finalScreenButton, delay: 0.4) {
                    self.gameModeChangeDate = Date()
                    self.checkMapState()
                    return
                }
            }else if let _ = strings.first(where: { jaroWinkler($0, "Click to continue") > 0.95 }) {
                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
                    self.gameModeChangeDate = Date()
                    self.checkMapState()
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick a Visitor") > 0.95 }) {
                self.chooseFirstVisitor {
                    self.delay(0.4, type: .map) {
                        self.gameModeChangeDate = Date()
                        self.checkMapState()
                    }
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick One Treasure") > 0.95 || jaroWinkler($0, "Keep or Replace Treasure") > 0.95 }) {
                self.chooseFirstBonus {
                    self.delay(0.4, type: .map) {
                        self.gameModeChangeDate = Date()
                        self.checkMapState()
                    }
                }
                return
            } else if strings.first(where: { jaroWinkler($0, "View Party") > 0.95 }) != nil {
                if self.mapInfo == nil {
                    self.delay(0.4, type: .map) {
                        self.analyzeMap {_ in
                            self.gameModeChangeDate = Date()
                            self.checkMapState()
                        }
                    }
                } else {
                    self.selectFirstAvailableLeve {
                        self.log("pressing on choose button")
                        CGEvent.letfClick(position: .chooseButton, delay: 0.4)
                        var delay = 0.4
                        if [.warp, .pickUp, .reveal, .visit].contains(self.readyButtonState) {
                            delay = 5
                        }
                        self.delay(delay, type: .map) {
                            CGEvent.letfClick(position: .testButton, delay: 0.4)
                            self.currentLevel += 1
                            self.gameModeChangeDate = Date()
                            self.checkMapState()
                        }
                    }
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Battle Spoils") > 0.95 || jaroWinkler($0, "CLOSE") > 0.95 }) {
                self.log("pressing on ok button on Battle Spoils")
                CGEvent.letfClick(position: .chooseButton, delay: 0.4)
                self.delay(0.4, type: .map) {
                    self.checkMapState()
                }
            }
            
            else if strings.count <= 4 {
                self.delay(0.4, type: .map) {
                    self.checkMapState()
                }
            }
        }
    }
    
    func checkAvalalbeTypes(completion: (()->Void)) {
        
    }
    
    let steps: CGFloat = 6
    var step: CGFloat {
        return (NSPoint.mapTo.x - NSPoint.mapFrom.x) / steps
    }
    
    var currentLevel = 0 {
        didSet {
            log("current level: \(currentLevel)")
        }
    }
    
    func selectFirstAvailableLeve(completion: @escaping (()->Void)) {
        var scrollTop = false
        func findLevel() {
            selectCurrentLevel {
                if self.readyButtonState == .none {
                    CGEvent.scroll(top: scrollTop) {
                        scrollTop = true
                        findLevel()
                    }
                } else {
                    completion()
                    return
                }
            }
        }
        findLevel()
    }
    
    var selectingLevel = false
    func selectCurrentLevel(completion: @escaping (()->Void)) {
        guard !selectingLevel && !analyzing else { return }
        assert(Thread.isMainThread)
        selectingLevel = true
        stopTimers(.map)
        log("checking for current level")
        
        checkCurrentLevelOnMistery { mystery in
            self.processReadyButton { _ in
                assert(Thread.isMainThread)
                if self.readyButtonState != .none && !mystery {
                    self.selectingLevel = false
                    completion()
                    return
                } else if self.readyButtonState != .none && mystery {
                    if self.readyButtonState == .visit {
                        self.selectingLevel = false
                        completion()
                        return
                    }
                }
                let mysteryPosition = self.mapInfo?.mysteryPosition ?? .left
                
                func stride(point: NSPoint) {
                    guard self.core.game.currentMode == .lettuce_map && self.selectingLevel else { return }
                    assert(Thread.isMainThread)
                    var finished = false
                    if mysteryPosition == .left {
                        finished = point.x >= NSPoint.mapTo.x
                    } else {
                        finished = point.x <= NSPoint.mapFrom.x
                    }
                    
                    guard !finished else {
                        self.selectingLevel = false
                        completion()
                        return
                    }
                    CGEvent.letfClick(position: point, delay: 0.2) {
                        self.processReadyButton { changed in
                            if self.readyButtonState != .none && !mystery {
                                self.selectingLevel = false
                                completion()
                                return
                            } else if self.readyButtonState != .none && mystery {
                                if self.readyButtonState == .visit {
                                    self.selectingLevel = false
                                    completion()
                                    return
                                }
                            }
                        }
                        stride(point: self.nextStepPoint(point))
                    }
                }
                stride(point: mysteryPosition == .left ? .mapFrom : .mapTo)
            }
        }
    }
    
    func nextStepPoint(_ point: NSPoint) -> NSPoint {
        if mapInfo?.mysteryPosition ?? .left == .left {
            return NSPoint(x: point.x + self.step, y: NSPoint.mapFrom.y)
        } else {
            return NSPoint(x: point.x - self.step, y: NSPoint.mapFrom.y)
        }
    }
    
    var analyzing = false
    func analyzeMap(completion: @escaping ((MapInfo)->Void)) {
        guard !analyzing && !selectingLevel else { return }
        analyzing = true
        log("analyzing map")
        stopTimers(.map)
        var mapTypes: MapInfo = [:]
        
        CGEvent.scroll(top: false) {
            func scrollAndAnalyze() {
                guard self.core.game.currentMode == .lettuce_map && self.analyzing else { return }
                self.log("map row \(mapTypes.count )")
                let sortedTypes = mapTypes.sorted(by: {$0.key < $1.key })
                let flatTypes = mapTypes.values.flatMap({$0})
                if sortedTypes.count >= 7 ||
                    (sortedTypes.count >= 2 && sortedTypes[sortedTypes.count - 1] == sortedTypes[sortedTypes.count - 2]) ||
                (sortedTypes.count > 0 && sortedTypes.last?.value.isEmpty == true) ||
                    flatTypes.contains(.mystery) ||
                    flatTypes.contains(.mysteriousStranger) ||
                    flatTypes.contains(.hotPotato) ||
                    flatTypes.contains(.portal){
                    self.mapInfo = mapTypes
                    self.log("map complete \(mapTypes.prettyDescription())")
                    self.analyzing = false
                    completion(mapTypes)
                    return
                }
                CGEvent.scroll(value: mapTypes.count == 0 ? 0 : 4) {
                    mapTypes.updateValue([MapLevelType](), forKey: mapTypes.count)
                    let mysteryPosition = self.mapInfo?.mysteryPosition ?? .left
                    
                    func analyse(point: NSPoint) {
                        guard self.core.game.currentMode == .lettuce_map && self.analyzing else { return }
                        var finished: Bool
                        if mysteryPosition == .left {
                            finished = point.x >= NSPoint.mapTo.x
                        } else {
                            finished = point.x <= NSPoint.mapFrom.x
                        }
                        
                        guard !finished else {
                            scrollAndAnalyze()
                            return
                        }
                        CGEvent.move(position: point, delay: 0.2) {
                            ImageRecognitionHelper.DetecktMapCircles() { pointStrings in
                                guard self.core.game.currentMode == .lettuce_map && self.analyzing else { return }
                                var type: MapLevelType = .invalid
                                for string in pointStrings {
                                    if string.count >= 6, let loopType = MapLevelType(string: string), loopType != .invalid {
                                        self.log("string \(string)")
                                        type = loopType
                                        break
                                    }
                                }
                                
                                if type != .invalid, mapTypes[mapTypes.count - 1]?.last ?? .invalid != type {
                                    print(type)
                                    mapTypes[mapTypes.count - 1]?.append(type)
                                }
                                analyse(point: self.nextStepPoint(point))
                            }
                        }
                    }
                    analyse(point: mysteryPosition == .left ? .mapFrom : .mapTo)
                }
            }
            scrollAndAnalyze()
        }
    }
    
    func subscribeToEvents() {
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            
            if event.modifierFlags.isSuperset(of: [.option, .command]) {
                switch event.type {
                case .leftMouseDown:
                    self?.log("mouse down proportion: \(event.locationInWindow.toEuqlid.proportionalPoint)")
                    self?.log("mouse down: \(event.locationInWindow)")
                    self?.log("mouse down hs: \(event.locationInWindow.toHSPoint)")
                    self?.log("mouse down hs: \(ImageRecognitionHelper.avarageColor(event.locationInWindow.toEuqlid))")
                    ImageRecognitionHelper.DetecktMapCircles() { strings in
                        self?.log("\(strings)")
                    }
                case .keyDown:
                    switch event.keyCode {
                    case 1: self?.start()
                    case 0: self?.checkMapState()
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
    weak var clickSpamTimer: Timer?
    
    func spam(doOnce: (()->Void)? = nil,
              block: (()->Void)? = nil,
              condition: @escaping (()->Bool),
              completion: ((Bool)->Void)? = nil,
              maxTime: TimeInterval? = nil,
              interval: TimeInterval = 0.4) {
        doOnce?()
        var maxDate: Date?
        if let maxTime = maxTime {
            maxDate = Date().addingTimeInterval(maxTime)
        }
        
        clickSpamTimer?.invalidate()
        clickSpamTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                              repeats: true,
                                              block: { [weak self] timer in
            var expired = false
            if let date = maxDate, date < Date() {
                self?.log(" expired: \(date.timeIntervalSince(Date()))")
                expired = true
            }
            defer {
                if expired { self?.clickSpamTimer?.invalidate() }
            }
            
            if self?.paused == true { return }
            if condition() || expired {
                self?.clickSpamTimer?.invalidate()
                DispatchQueue.main.async {
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
        
        gameModeChangeDate = Date()
//        openApp()
        
        cleanUp()
        
        checkCurrentStateAndProcess()
    }
    
    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "unity.Blizzard Entertainment.Hearthstone") else { return }
        
        let path = "/bin"
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [path]
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: configuration,
                                           completionHandler: nil)
    }
    
    func checkCurrentStateAndProcess() {
        if [.lettuce_bounty_board, .lettuce_bounty_team_select].contains(core.game.currentMode ?? .invalid) {
            delay(0.4, type: .map) {
                CGEvent.letfClick(position: .chooseButton) {
                    self.delay(0.4, type: .map) {
                        self.checkCurrentStateAndProcess()
                    }
                }
            }
        }
        
        if core.game.currentMode == .invalid {
            CGEvent.letfClick(position: .disconnectOKButton, delay: 0.4) {
                self.delay(0.4, type: .map) {
                    self.checkCurrentStateAndProcess()
                }
            }
        }
    }
    
    func preFight() {
        guard core.game.currentMode == .gameplay else { return }
        log("Prefight")
        spam (block: {
            CGEvent.letfClick(position: .readyButton)
        }, condition: {
            self.enemiesReady
        }, completion: { _ in
            self.delay(1, type: .fight) {
                self.fight()
            }
        })
    }
    
    var fightTimers: [Timer] = []
    var clickTimers: [Timer] = []
    var mapTimers: [Timer] = []
    
    enum DelayType: CaseIterable {
        case fight, click, map
    }
    
    func timersFor(_ type: DelayType) -> [Timer] {
        switch type {
        case .fight: return fightTimers
        case .click: return clickTimers
        case .map: return mapTimers
        }
    }
    
    func delay(_ sec: TimeInterval, type: DelayType = .fight, completion: @escaping (()->Void)) {
        assert(Thread.isMainThread)
        var mutTimers = timersFor(type)
        mutTimers.append(Timer.scheduledTimer(withTimeInterval: sec, repeats: false, block: { timer in
            completion()
            timer.invalidate()
        }))
    }
    
    func fight() {
        log("Fight")
        
        var playerIndex: Int?
        
        for (index, minion) in allPlayerMinions.enumerated() {
            if !minion.has(tag: .lettuce_ability_tile_visual_self_only) {
                playerIndex = index
                self.log("\(minion.card.role)")
                break
            }
        }
        
        guard let index = playerIndex else {
            if enemiesReady || playerMinions.isEmpty {
                spam(block: { CGEvent.letfClick(position: .readyButton, delay: 0.5)},
                     condition: { self.core.game.step == .main_pre_action },
                     completion: { _ in self.preFight() })
            }
            return
        }
        
        let playerPosition = playerViews[index].frame.center.playerScreenCenter
        let enemyPosition = enemyViews.first?.frame.center.enemyScreenCenter ?? .zero
        
        spam(doOnce: {
            CGEvent.letfClick(position: playerPosition, delay: 0.4) {
                CGEvent.letfClick(position: .firstSkill, delay: 0.4)
            }
        }, condition: {
            self.allPlayerMinions[index].has(tag: .lettuce_ability_tile_visual_self_only)
        }, completion: { success in
            self.log("skill chosen success: \(success)")
            
            if !success {
                CGEvent.letfClick(position: enemyPosition, delay: 0.4) {
                    self.delay(0.4) {
                        self.fight()
                    }
                }
            } else {
                self.delay(0.4) {
                    self.fight()
                }
            }
        }, maxTime: 1,
             interval: 0.1)
        
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

extension Bot.MapInfo {
    
    var mysteryLevel: Int? {
        var mystery: Int?
        
        for typs in self {
            if typs.value.contains(.mystery) || typs.value.contains(.mysteriousStranger) {
                mystery = typs.key
                break
            }
        }
        
        return mystery
    }
    
    var mysteryPosition: MysteryPosition? {
        if let mysteryLevel = mysteryLevel, let mysteryIndex = self[mysteryLevel]?.firstIndex(of: .mystery) ?? self[mysteryLevel]?.firstIndex(of: .mysteriousStranger) {
            switch (self[mysteryLevel]?.count ?? 0) {
            case 0: return nil
            case 1: return .left
            case 2: return mysteryIndex > 0 ? .right : .left
            case 3: return mysteryIndex > 1 ? .right : .left
            case 4: return mysteryIndex > 2 ? .right : .left
            default: return nil
            }
        }
        return nil
    }
}
