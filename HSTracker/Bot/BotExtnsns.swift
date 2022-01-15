//
//  BotExtnsns.swift
//  HSTracker
//
//  Created by AO on 30.12.21.
//  Copyright © 2021 Benjamin Michotte. All rights reserved.
//

import Foundation

extension Game {
    var playerMinions: [Entity] {
        return player.board.filter({$0.isMinion && [.fighter, .protector, .caster].contains($0.card.role)}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var availalbeMinions: [Entity] {
        return player.board.filter({$0.isMinion}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var enemyMinions: [Entity] {
        return opponent.board.filter({$0.isMinion}).sorted(by: { $0.zonePosition < $1.zonePosition })
    }
    
    var playerIsReady: Bool {
        let playerStates = availalbeMinions.compactMap({$0.has(tag:.lettuce_ability_tile_visual_self_only)})
        return playerStates.count > 0 && !playerStates.contains(false)
    }
    
    var enemiesReady: Bool {
        let enemyStates = enemyMinions.compactMap({$0.has(tag:.lettuce_ability_tile_visual_all_visible)})
        return enemyStates.count > 0 && !enemyStates.contains(false)
    }
    
    var playerViews: [NSView] {
        return windowManager.playerBoardOverlay.view.minions
    }
    
    var enemyViews: [NSView] {
        return windowManager.opponentBoardOverlay.view.minions
    }
}

typealias MapInfo = [Int: [MapLevelType]]
extension MapInfo {
    
    enum MysteryPosition {
        case left, right
    }
    
    var srtartPoint: NSPoint {
        (mysteryPosition ?? .left) == .left ? .mapFrom : .mapTo
    }
    
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
