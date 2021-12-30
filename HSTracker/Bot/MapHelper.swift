//
//  MapHelper.swift
//  HSTracker
//
//  Created by AO on 25.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation

class MapHelper {
    
    let steps: CGFloat = 6
    var step: CGFloat {
        return (NSPoint.mapTo.x - NSPoint.mapFrom.x) / steps
    }
    
    var bot: Bot {
        return AppDelegate.instance().bot
    }
    
    typealias MapInfo = [Int: [MapLevelType]]
    var mapInfo: MapInfo?
    func processMapInfo(_ info: MapInfo) {
        info.prettyDescription()
    }
    
    var checkingMapState = false
    func checkMapState() {
        guard !checkingMapState else { return }
        checkingMapState = true
        log("check map state")
        ImageRecognitionHelper.recognizeGlobalText { strings in
            self.checkingMapState = false
            guard self.bot.core.game.currentMode == .lettuce_map else { return }
            log("recognized map state: \(strings)")
            
            if let _ = strings.first(where: { jaroWinkler($0, "Victor") > 0.95 || jaroWinkler($0, "Victors") > 0.95 }) {
                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
                    self.bot.openBoxes {
                        self.checkMapState()
                    }
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Click to continue") > 0.95 }) {
                CGEvent.letfClick(position: .mapTo, delay: 0.4) {
                    self.checkMapState()
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick a Visitor") > 0.95 }) {
                self.chooseFirstVisitor {
                    self.delay(0.4, type: .map) {
                        self.checkMapState()
                    }
                }
                return
            } else if let _ = strings.first(where: { jaroWinkler($0, "Pick One Treasure") > 0.95 || jaroWinkler($0, "Keep or Replace Treasure") > 0.95 }) {
                self.chooseFirstBonus {
                    self.delay(0.4, type: .map) {
                        self.checkMapState()
                    }
                }
                return
            } else if strings.first(where: { jaroWinkler($0, "View Party") > 0.95 }) != nil {
                if self.mapInfo == nil {
                    self.delay(0.4, type: .map) {
                        self.analizeMap {_ in
                            self.checkMapState()
                        }
                    }
                } else {
                    self.selectCurrentLevel {
                        self.log("pressing on choose button")
                        CGEvent.letfClick(position: .chooseButton, delay: 0.4)
                        self.delay(0.4, type: .map) {
                            self.checkMapState()
                        }
                    }
                }
                return
            }
        }
    }
    
    var selectingLevel = false
    func selectCurrentLevel(completion: @escaping (()->Void)) {
        guard !selectingLevel else { return }
        selectingLevel = true
        stopTimers(.map)
        log("checking for current level")
        
        processReadyButton { _ in
            if self.readyButtonState != .none {
                self.selectingLevel = false
                completion()
                return
            }
            CGEvent.scroll(top: false) {
                func scrollAndAnalyze(scroll: Int) {
                    guard self.core.game.currentMode == .lettuce_map else { return }
                    CGEvent.scroll() {
                        let mysteryPosition = self.mapInfo?.mysteryPosition ?? .left
                        
                        func stride(point: NSPoint) {
                            var finished = scroll > 10
                            if mysteryPosition == .left {
                                finished = point.x >= NSPoint.mapTo.x
                            } else {
                                finished = point.x <= NSPoint.mapFrom.x
                            }
                            
                            guard !finished else {
                                scrollAndAnalyze(scroll: scroll + 1)
                                return
                            }
                            CGEvent.letfClick(position: point, delay: 0.1) {
                                self.processReadyButton { changed in
                                    if changed {
                                        if self.mapInfo?.mysteryLevel == scroll {
                                            if self.readyButtonState == .visit {
                                                self.selectingLevel = false
                                                completion()
                                                return
                                            }
                                        } else {
                                            self.selectingLevel = false
                                            completion()
                                            return
                                        }
                                    }
                                    stride(point: self.nextStepPoint(point))
                                }
                            }
                        }
                        stride(point: mysteryPosition == .left ? .mapFrom : .mapTo)
                    }
                }
                scrollAndAnalyze(scroll: 0)
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
    func analizeMap(completion: @escaping ((MapInfo)->Void)) {
        guard !analyzing else { return }
        analyzing = true
        log("analyzing map")
        stopTimers(.map)
        var mapTypes: MapInfo = [:]
        
        CGEvent.scroll(top: false) {
            func scrollAndAnalyze() {
                guard self.core.game.currentMode == .lettuce_map else { return }
                self.log("map row \(self.mapInfo?.values.count ?? 0)")
                if (mapTypes.count > 0 && mapTypes.sorted(by: {$0.key < $1.key }).last?.value.isEmpty == true) || mapTypes.values.flatMap({$0}).contains(.mystery) ||
                    mapTypes.values.flatMap({$0}).contains(.mysteriousStranger) ||
                    mapTypes.values.flatMap({$0}).contains(.hotPotato) {
                    self.mapInfo = mapTypes
                    self.log("map complete \(mapTypes.prettyDescription())")
                    self.analyzing = false
                    completion(mapTypes)
                    return
                }
                CGEvent.scroll() {
                    mapTypes.updateValue([MapLevelType](), forKey: mapTypes.count)
                    let mysteryPosition = self.mapInfo?.mysteryPosition ?? .left
                    
                    func analyse(point: NSPoint) {
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
                        CGEvent.move(position: point, delay: 0.1) {
                            ImageRecognitionHelper.DetecktMapCircles(position: point.toEuqlid.toHSPoint) { pointStrings in
                                var type: MapLevelType = .invalid
                                for string in pointStrings {
                                    if string.count > 6, let loopType = MapLevelType(string: string), loopType != .invalid {
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
    
    var readyButtonState: ReadyButtonState = .none
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
}

enum MysteryPosition {
    case left, right
}

extension Bot.MapInfo {
    
    var mysteryLevel: Int? {
        var mystery: Int?
        
        for typs in self {
            for value in typs.value {
                if [.mystery, .mysteriousStranger].contains(value)
                    mystery = typs.key
                    break
            }
        }
        
        return mystery
    }
    
    var mysteryPosition: MysteryPosition? {
        if let mysteryLevel = mysteryLevel, let mysteryIndex = self[mysteryLevel]?.firstIndex(of: .mystery) {
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
