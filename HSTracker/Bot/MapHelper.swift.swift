//
//  MapHelper.swift.swift
//  HSTracker
//
//  Created by AO on 2.01.22.
//  Copyright © 2022 Benjamin Michotte. All rights reserved.
//

import Foundation

extension BotFnc {
    enum StateByTextType {
        case undefined, victory, bountyComplete, clickToContinue, pickVisitor, pickOneTreasure, viewParty, battleSpoils, lockIn, felwoodBounties, chooseParty, taskObtained
        
        static func from(_ strings: [(String, NSPoint)]) -> (StateByTextType, NSPoint)? {
            if let type = strings.firstConfident(["Victor", "Victors", "Victory"]) {
                return (.victory, type.1)
            } else if let type = strings.firstConfident(["Bounty Complete!"]) {
                return (.bountyComplete, type.1)
            } else  if let type = strings.firstConfident(["Click to continue"]) {
                return (.clickToContinue, type.1)
            } else if let type = strings.firstConfident(["Pick a Visitor"]) {
                return (.pickVisitor, type.1)
            } else if let type = strings.firstConfident(["Pick One Treasure", "Keep or Replace Treasure"]) {
                return (.pickOneTreasure, type.1)
            } else if let type = strings.firstConfident(["Lock In"]) {
                return (.lockIn, type.1)
            } else if let type = strings.firstConfident(["Battle Spoils", "CLOSE"]) {
                return (.battleSpoils, type.1)
            } else if let type = strings.firstConfident(["View Party"]) {
                return (.viewParty, type.1)
            } else if let type = strings.firstConfident(["Felwood Bounties"]) {
                return (.felwoodBounties, type.1)
            } else if let type = strings.firstConfident(["Choose a Party"]) {
                return (.chooseParty, type.1)
            } else if let type = strings.firstConfident(["Task obtained"]) {
                return (.taskObtained, type.1)
            }
            
            return nil
            
        }
    }
    
    var steps: CGFloat {
        return 6
    }
    var step: CGFloat {
        return (NSPoint.mapTo.x - NSPoint.mapFrom.x) / steps + 1
    }
    
    func analyzeMap(completion: @escaping (()->Void)) {
        guard mapInfo == nil && core.game.currentMode == .lettuce_map && analizingMap else { return }
        log("analyzing map")
        mapInfo = [:]
        
        addBlock(.scroll(top: false))
        addBlock{ _ in
            self.scrollAndAnalyze(completion: completion)
        }
    }
    
    func scrollAndSelect(loop: Int, callback: @escaping ((Bool, Int)->Void)) {
        guard self.core.game.currentMode == .lettuce_map && mapComplete else { return }
        
        self.analyseRow(point: self.mapInfo?.srtartPoint ?? .zero, type: .select) {type, finished in
            if finished {
                callback(true, loop)
                self.addBlock(.scroll())
                self.delay(time: 0.2)
                self.addBlock { op in
                    self.scrollAndSelect(loop: loop + 1, callback: callback)
                }
            } else {
                callback(false, loop)
            }
        }
    }
    
    enum AnalyzeType {
        case select, detect
    }
    
    func analyseRow(point: NSPoint, type: AnalyzeType = .detect, callback: @escaping ((MapLevelType?, Bool)->Void)) {
        guard self.core.game.currentMode == .lettuce_map else { return }
        guard point.x >= NSPoint.mapFrom.x && point.x <= NSPoint.mapTo.x else {
            callback(nil, true)
            return
        }
        
        addBlock(.move(position: point))
        addBlock(.delay(0.05))
        addBlock { _ in
            if type == .detect {
                self.addBlock {_ in
                    ImageRecognitionHelper.DetecktMapCircles { strings in
                        for string in strings {
                            if let loopType = MapLevelType(string: string.0), loopType != .invalid {
                                callback(loopType, false)
                                break
                            }
                        }
                        self.analyseRow(point: self.nextStepPoint(point, type: type), type: type, callback: callback)
                    }
                }
            } else {
                self.delay(time: 0.05)
                self.addBlock(.click(point))
                self.addBlock { _ in
                    callback(nil, false)
                    self.analyseRow(point: self.nextStepPoint(point, type: type),type: type, callback: callback)
                }
                    
            }
        }
    }
    
    var mapComplete: Bool {
        if let sortedTypes = mapInfo?.sorted(by: {$0.key < $1.key }),
           let flatTypes = mapInfo?.values.flatMap({$0}),
           (sortedTypes.count >= 7 ||
            (sortedTypes.count >= 2 && sortedTypes[sortedTypes.count - 1] == sortedTypes[sortedTypes.count - 2]) ||
            flatTypes.contains(.mystery) ||
            flatTypes.contains(.mysteriousStranger) ||
            flatTypes.contains(.hotPotato) ||
            flatTypes.contains(.portal)) {
            return true
        }
        return false
    }
    
    func scrollAndAnalyze(completion: @escaping (()->Void)) {
        guard self.core.game.currentMode == .lettuce_map && mapInfo != nil && analizingMap else { return }
        
        log("map row \(mapInfo?.count ?? 0)")
        if mapComplete {
            completion()
            return
        }
        
        addBlock { _ in
            let count = self.mapInfo?.count ?? 0
            self.mapInfo?.updateValue([], forKey: count - 1)
            self.analyseRow(point: .mapFrom) {type, finished in
                if finished {
                    if !self.mapComplete {
                        self.addBlock(.scroll())
                    }
                    self.addBlock { _ in
                        self.scrollAndAnalyze(completion: completion)
                    }
                } else if let type = type, type != .invalid, self.mapInfo?[count - 1]?.last ?? .invalid != type {
                    self.mapInfo?[count - 1]?.append(type)
                }
            }
        }
    }
    
    func nextStepPoint(_ point: NSPoint, type: AnalyzeType) -> NSPoint {
        if type == .detect {
            return NSPoint(x: point.x + self.step, y: NSPoint.mapFrom.y)
        } else {
            if mapInfo?.mysteryPosition ?? .left == .left {
                return NSPoint(x: point.x + self.step, y: NSPoint.mapFrom.y)
            } else {
                return NSPoint(x: point.x - self.step, y: NSPoint.mapFrom.y)
            }
        }
    }
    
    class func globalTextType(callback: @escaping ((StateByTextType, NSPoint)->Void)) -> BlockOperation {
        //        log("check global text")
        
        return Operation.blockWithSema { sem in
            ImageRecognitionHelper.recognizeGlobalText { strings in
                sem.signal()
                if let type = StateByTextType.from(strings) {
                    callback(type.0, type.1)
                    return
                }
                callback(.undefined, .zero)
            }
        }
    }
    
    //    func checkMapState() {
    //        guard !checkingMapState else { return }
    //        log("Mirror merc mapInfo: \(String(describing: MirrorHelper.getMercenariesMapInfo()))")
    //        checkingMapState = true
    //        log("check map state")
    //        ImageRecognitionHelper.recognizeGlobalText { strings in
    //            self.checkingMapState = false
    //            guard self.core.game.currentMode == .lettuce_map else { return }
    //            self.log("recognized map state: \(strings)")
    //
    //            if let _ = strings.first(where: { jaroWinkler($0, "Victor") > 0.95 || jaroWinkler($0, "Victors") > 0.95 || jaroWinkler($0, "Victory") > 0.95}) {
    //                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
    //                    self.delay(10) {
    //                        self.openBoxes {
    //                            self.gameModeChangeDate = Date()
    //                            self.checkMapState()
    //                        }
    //                    }
    //                }
    //            } else if let _ = strings.first(where: { jaroWinkler($0, "Bounty Complete!") > 0.95 }) {
    //                CGEvent.letfClick(position: .finalScreenButton, delay: 0.4) {
    //                    self.gameModeChangeDate = Date()
    //                    self.checkMapState()
    //                    return
    //                }
    //            }else if let _ = strings.first(where: { jaroWinkler($0, "Click to continue") > 0.95 }) {
    //                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
    //                    self.gameModeChangeDate = Date()
    //                    self.checkMapState()
    //                }
    //                return
    //            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick a Visitor") > 0.95 }) {
    //                self.chooseFirstVisitor {
    //                    self.delay(0.4, type: .map) {
    //                        self.gameModeChangeDate = Date()
    //                        self.checkMapState()
    //                    }
    //                }
    //                return
    //            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick One Treasure") > 0.95 || jaroWinkler($0, "Keep or Replace Treasure") > 0.95 }) {
    //                self.chooseFirstBonus {
    //                    self.delay(0.4, type: .map) {
    //                        self.gameModeChangeDate = Date()
    //                        self.checkMapState()
    //                    }
    //                }
    //                return
    //            } else if strings.first(where: { jaroWinkler($0, "View Party") > 0.95 }) != nil {
    //                if self.mapInfo == nil {
    //                    self.delay(0.4, type: .map) {
    //                        self.analyzeMap {_ in
    //                            self.gameModeChangeDate = Date()
    //                            self.checkMapState()
    //                        }
    //                    }
    //                } else {
    //                    self.selectFirstAvailableLeve {
    //                        self.log("pressing on choose button")
    //                        CGEvent.letfClick(position: .chooseButton, delay: 0.4)
    //                        var delay = 0.4
    //                        if [.warp, .pickUp, .reveal, .visit].contains(self.readyButtonState) {
    //                            delay = 5
    //                        }
    //                        self.delay(delay, type: .map) {
    //                            CGEvent.letfClick(position: .testButton, delay: 0.4)
    //                            self.currentLevel += 1
    //                            self.gameModeChangeDate = Date()
    //                            self.checkMapState()
    //                        }
    //                    }
    //                }
    //                return
    //            } else if let _ = strings.first(where: { jaroWinkler($0, "Battle Spoils") > 0.95 || jaroWinkler($0, "CLOSE") > 0.95 }) {
    //                self.log("pressing on ok button on Battle Spoils")
    //                CGEvent.letfClick(position: .chooseButton, delay: 0.4)
    //                self.delay(0.4, type: .map) {
    //                    self.checkMapState()
    //                }
    //            }
    //
    //            else if strings.count <= 4 {
    //                self.delay(0.4, type: .map) {
    //                    self.checkMapState()
    //                }
    //            }
    //        }
    //    }
}

