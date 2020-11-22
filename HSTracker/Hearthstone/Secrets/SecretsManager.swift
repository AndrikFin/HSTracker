//
//  SecretsManager.swift
//  HSTracker
//
//  Created by Benjamin Michotte on 25/10/17.
//  Copyright © 2017 Benjamin Michotte. All rights reserved.
//

import Foundation
import AwaitKit

class SecretsManager {
    let avengeDelay: Double = 50
    let multipleSecretResolveDelay = 750
    private var _avengeDeathRattleCount = 0
    private var _awaitingAvenge = false
    private var _lastStartOfTurnSecretCheck = 0
    private var entititesInHandOnMinionsPlayed: Set<Entity>  = Set<Entity>()

    private var game: Game
    private(set) var secrets: [Secret] = []
    private var _triggeredSecrets: [Entity] = []
    private var opponentTookDamageDuringTurns: [Int] = []
    
    private var _lastPlayedMinionId: Int = 0
    private var savedSecrets: [String] = []

    var onChanged: (([Card]) -> Void)?

    init(game: Game) {
        self.game = game
    }

    private var freeSpaceOnBoard: Bool { return game.opponentMinionCount < 7 }
    private var freeSpaceInHand: Bool { return game.opponentHandCount < 10 }
    private var handleAction: Bool { return hasActiveSecrets }
    private var isAnyMinionInOpponentsHand: Bool { return entititesInHandOnMinionsPlayed.first(where: { entity in entity.isMinion }) != nil }

    private var hasActiveSecrets: Bool {
        return secrets.count > 0
    }
    
    private func saveSecret(secretName: String) {
        if !secrets.any({ (s) -> Bool in
            s.isExcluded(cardId: secretName)
        }) {
            savedSecrets.append(secretName)
        }
    }

    func exclude(cardId: String, invokeCallback: Bool = true) {
        if cardId.isBlank {
            return
        }

        secrets.forEach {
            $0.exclude(cardId: cardId)
        }

        if invokeCallback {
            onChanged?(getSecretList())
        }
    }

    func exclude(cardIds: [String]) {
        cardIds.enumerated().forEach {
            exclude(cardId: $1, invokeCallback: $0 == cardIds.count - 1)
        }
    }

    func reset() {
        _avengeDeathRattleCount = 0
        _awaitingAvenge = false
        _lastStartOfTurnSecretCheck = 0
        opponentTookDamageDuringTurns.removeAll()
        entititesInHandOnMinionsPlayed.removeAll()
        secrets.removeAll()
    }

    @discardableResult
    func newSecret(entity: Entity) -> Bool {
        if !entity.isSecret || !entity.has(tag: .class) {
            return false
        }

        if entity.hasCardId {
            exclude(cardId: entity.cardId)
        }
        do {
            let secret = try Secret(entity: entity)
            secrets.append(secret)
            logger.info("new secret : \(entity)")
            onNewSecret(secret: secret)
            onChanged?(getSecretList())
            return true
        } catch {
            logger.error("\(error)")
            return false
        }
    }

    @discardableResult
    func removeSecret(entity: Entity) -> Bool {
        guard let secret = secrets.first(where: { $0.entity.id == entity.id }) else {
            logger.info("Secret not found \(entity)")
            return false
        }

        handleFastCombat(entity: entity)
        secrets.remove(secret)
        if secret.entity.hasCardId {
            exclude(cardId: secret.entity.cardId, invokeCallback: false)
            savedSecrets.remove(secret.entity.cardId)
        }
        onChanged?(getSecretList())
        return true
    }

    func toggle(cardId: String) {
        let excluded = secrets.any { $0.isExcluded(cardId: cardId) }
        if excluded {
            secrets.forEach { $0.include(cardId: cardId) }
        } else {
            exclude(cardId: cardId, invokeCallback: false)
        }
    }

    func getSecretList() -> [Card] {
        let gameMode = game.currentGameType
        let format = game.currentFormat

        let opponentEntities = game.opponent.revealedEntities.filter {
            $0.id < 68 && $0.isSecret && $0.hasCardId
        }
        let gameModeHasCardLimit = [GameType.gt_casual, GameType.gt_ranked, GameType.gt_vs_friend, GameType.gt_vs_ai].contains(gameMode)

        let createdSecrets = secrets
            .filter { $0.entity.info.created }
            .flatMap { $0.excluded }
            .filter { !$0.value }
            .map { $0.key }
            .unique()
        let hasPlayedTwoOf: ((_ cardId: String) -> Bool) = { cardId in
            opponentEntities.filter { $0.cardId == cardId && !$0.info.created }.count >= 2
        }
        let adjustCount: ((_ cardId: String, _ count: Int) -> Int) = { cardId, count in
            gameModeHasCardLimit && hasPlayedTwoOf(cardId) && !createdSecrets.contains(cardId) ? 0 : count
        }

        var cards: [Card] = secrets.flatMap { $0.excluded }
            .group { $0.key }
            .compactMap {
                let card = Cards.by(cardId: $0.key)
                card?.count = adjustCount($0.key, $0.value.filter({ !$0.value }).count)
                return card
        }
        
        if let remoteData = RemoteConfig.data {
            if gameMode == .gt_arena {
                let currentSets = remoteData.arena.current_sets.compactMap({ value in
                    CardSet(rawValue: "\(value.lowercased())")
                })
                
                cards = cards.filter { card in
                    currentSets.contains(card.set ?? .invalid)
                }
                
                if remoteData.arena.banned_secrets.count > 0 {
                    cards = cards.filter({ card in
                        !remoteData.arena.banned_secrets.contains(card.id)
                    })
                }
            } else {
                if remoteData.arena.exclusive_secrets.count > 0 {
                    cards = cards.filter({ card in
                        !remoteData.arena.exclusive_secrets.contains(card.id)
                    })
                }
                if format == .standard {
                    let wildSets = CardSet.wildSets()
                    cards = cards.filter({ card in
                        !wildSets.contains(card.set ?? .invalid)
                    })
                }
            }
            
            if gameMode == .gt_pvpdr || gameMode == .gt_pvpdr_paid {
                let currentSets = remoteData.pvpdr.current_sets.compactMap({ value in
                    CardSet(rawValue: "\(value.lowercased())")
                })
                cards = cards.filter({ card in
                    currentSets.contains(card.set ?? .invalid)
                })
                if remoteData.pvpdr.banned_secrets.count > 0 {
                    cards = cards.filter({ card in
                        !remoteData.pvpdr.banned_secrets.contains(card.id)
                    })
                }
            }
        }

        return cards.filter { $0.count > 0 }.sortCardList()
    }

    func handleAttack(attacker: Entity, defender: Entity, fastOnly: Bool = false) {
        guard handleAction else { return }

        if attacker[.controller] == defender[.controller] {
            return
        }

        var exclude: [String] = []

        if freeSpaceOnBoard {
            exclude.append(CardIds.Secrets.Paladin.NobleSacrifice)
        }

        if defender.isHero {
            if !fastOnly && attacker.health >= 1 {
                if freeSpaceOnBoard {
                    exclude.append(CardIds.Secrets.Hunter.BearTrap)
                }

                if (game.entities.values.first(where: { x in
                    x.isInPlay && (x.isHero || x.isMinion) && !x.has(tag: .immune) && x != attacker && x != defender
                    }) != nil) {
                    exclude.append(CardIds.Secrets.Hunter.Misdirection)
                }

                if attacker.isMinion {
                    if game.playerMinionCount > 1 {
                        exclude.append(CardIds.Secrets.Rogue.SuddenBetrayal)
                    }

                    exclude.append(CardIds.Secrets.Mage.FlameWard)
                    exclude.append(CardIds.Secrets.Hunter.FreezingTrap)
                    exclude.append(CardIds.Secrets.Mage.Vaporize)
                    if freeSpaceOnBoard {
                        exclude.append(CardIds.Secrets.Rogue.ShadowClone)
                    }
                }
            }

            if freeSpaceOnBoard {
                exclude.append(CardIds.Secrets.Hunter.WanderingMonster)
            }

            exclude.append(CardIds.Secrets.Mage.IceBarrier)
            exclude.append(CardIds.Secrets.Hunter.ExplosiveTrap)
        } else {
            exclude.append(CardIds.Secrets.Rogue.Bamboozle)
            if !defender.has(tag: .divine_shield) {
                exclude.append(CardIds.Secrets.Paladin.AutodefenseMatrix)
            }
            
            if freeSpaceOnBoard {
                exclude.append(CardIds.Secrets.Mage.SplittingImage)
                exclude.append(CardIds.Secrets.Hunter.PackTactics)
                exclude.append(CardIds.Secrets.Hunter.SnakeTrap)
                exclude.append(CardIds.Secrets.Hunter.VenomstrikeTrap)
            }

            if attacker.isMinion {
                exclude.append(CardIds.Secrets.Hunter.FreezingTrap)
            }
        }
        self.exclude(cardIds: exclude)
    }

    func handleFastCombat(entity: Entity) {
        guard handleAction else { return }

        if !entity.hasCardId || game.proposedAttacker == 0 || game.proposedDefender == 0 {
            return
        }
        if !CardIds.Secrets.fastCombat.contains(entity.cardId) {
            return
        }
        if let attacker = game.entities[game.proposedAttacker],
            let defender = game.entities[game.proposedDefender] {
            handleAttack(attacker: attacker, defender: defender, fastOnly: true)
        }
    }

    func handleMinionPlayed(entity: Entity) {
        guard handleAction else { return }

        var exclude: [String] = []
        
        _lastPlayedMinionId = entity.id

        if !entity.has(tag: .dormant) {
            saveSecret(secretName: CardIds.Secrets.Hunter.Snipe)
            exclude.append(CardIds.Secrets.Hunter.Snipe)
            saveSecret(secretName: CardIds.Secrets.Mage.ExplosiveRunes)
            exclude.append(CardIds.Secrets.Mage.ExplosiveRunes)
            saveSecret(secretName: CardIds.Secrets.Mage.PotionOfPolymorph)
            exclude.append(CardIds.Secrets.Mage.PotionOfPolymorph)
            saveSecret(secretName: CardIds.Secrets.Paladin.Repentance)
            exclude.append(CardIds.Secrets.Paladin.Repentance)
        }

        if freeSpaceOnBoard {
            saveSecret(secretName: CardIds.Secrets.Mage.MirrorEntity)
            exclude.append(CardIds.Secrets.Mage.MirrorEntity)
            saveSecret(secretName: CardIds.Secrets.Rogue.Ambush)
            exclude.append(CardIds.Secrets.Rogue.Ambush)
        }

        if freeSpaceInHand {
            exclude.append(CardIds.Secrets.Mage.FrozenClone)
        }

        //Hidden cache will only trigger if the opponent has a minion in hand.
        //We might not know this for certain - requires additional tracking logic.
        let cardsInOpponentsHand = game.entities.values.filter({ e in
            e.isInHand && e.isControlled(by: game.opponent.id)
        }).compactMap({ e in e })
        for cardInOpponentsHand in cardsInOpponentsHand {
            entititesInHandOnMinionsPlayed.insert(cardInOpponentsHand)
        }

        if isAnyMinionInOpponentsHand {
            exclude.append(CardIds.Secrets.Hunter.HiddenCache)
        }

        self.exclude(cardIds: exclude)
    }

    func handleOpponentMinionDeath(entity: Entity) {
        guard handleAction else { return }

        var exclude: [String] = []
        if freeSpaceInHand {
            exclude.append(CardIds.Secrets.Mage.Duplicate)
            exclude.append(CardIds.Secrets.Paladin.GetawayKodo)
            exclude.append(CardIds.Secrets.Rogue.CheatDeath)
        }
        
        if let opponent_minions_died = game.opponentEntity?[.num_friendly_minions_that_died_this_turn], opponent_minions_died >= 1 {
            exclude.append(CardIds.Secrets.Paladin.HandOfSalvation)
        }

        var numDeathrattleMinions = 0
        if entity.isActiveDeathrattle {
            if let count = CardIds.DeathrattleSummonCardIds[entity.cardId] {
                numDeathrattleMinions = count
            } else if entity.cardId == CardIds.Collectible.Neutral.Stalagg
                && game.opponent.graveyard.any({ $0.cardId == CardIds.Collectible.Neutral.Feugen })
                || entity.cardId == CardIds.Collectible.Neutral.Feugen
                && game.opponent.graveyard.any({ $0.cardId == CardIds.Collectible.Neutral.Stalagg }) {
                numDeathrattleMinions = 1
            }

            if game.entities.map({ $0.value }).any({ $0.cardId == CardIds.NonCollectible.Druid.SouloftheForest_SoulOfTheForestEnchantment
                && $0[.attached] == entity.id }) {
                numDeathrattleMinions += 1
            }
            if game.entities.map({ $0.value }).any({ $0.cardId == CardIds.NonCollectible.Shaman.AncestralSpirit_AncestralSpiritEnchantment
                && $0[.attached] == entity.id }) {
                numDeathrattleMinions += 1
            }
        }

        if let opponentEntity = game.opponentEntity,
            opponentEntity.has(tag: .extra_deathrattles) {
            numDeathrattleMinions *= opponentEntity[.extra_deathrattles] + 1
        }

        handleAvengeAsync(deathRattleCount: numDeathrattleMinions)

        // redemption never triggers if a deathrattle effect fills up the board
        // effigy can trigger ahead of the deathrattle effect, but only if effigy was played before the deathrattle minion
        if game.opponentMinionCount < 7 - numDeathrattleMinions {
            exclude.append(CardIds.Secrets.Paladin.Redemption)
        }

        // TODO: break ties when Effigy + Deathrattle played on the same turn
        exclude.append(CardIds.Secrets.Mage.Effigy)

        self.exclude(cardIds: exclude)
    }
    
    func handlePlayerMinionDeath(entity: Entity) {
        if entity.id == _lastPlayedMinionId && savedSecrets.count > 0 {
            savedSecrets.forEach { savedSecret in
                secrets.forEach { secret in
                    secret.include(cardId: savedSecret)
                }
            }
            
            onChanged?(getSecretList())
        }
    }

    func handleAvengeAsync(deathRattleCount: Int) {
        guard handleAction else { return }

        if _awaitingAvenge {
            return
        }
        
        DispatchQueue.global().async {
            self._awaitingAvenge = true
            self._avengeDeathRattleCount += deathRattleCount
            if self.game.opponentMinionCount != 0 {
                do {
                    try await {
                        Thread.sleep(forTimeInterval: self.avengeDelay)
                    }
                    if self.game.opponentMinionCount - self._avengeDeathRattleCount > 0 {
                        self.exclude(cardId: CardIds.Secrets.Paladin.Avenge)
                    }
                } catch {
                    logger.error("\(error)")
                }
            }
            self._avengeDeathRattleCount = 0
            self._awaitingAvenge = false
        }
    }

    func handleOpponentDamage(entity: Entity) {
        guard handleAction else { return }

        if entity.isHero && entity.isControlled(by: game.opponent.id) {
            if !entity.has(tag: GameTag.immune) {
                exclude(cardId: CardIds.Secrets.Paladin.EyeForAnEye)
                exclude(cardId: CardIds.Secrets.Rogue.Evasion)
                opponentTookDamageDuringTurns.append(game.turnNumber())
            }
        }
    }

    func handleTurnsInPlayChange(entity: Entity, turn: Int) {
        guard handleAction else { return }

        if game.opponentEntity?.isCurrentPlayer ?? false && turn > _lastStartOfTurnSecretCheck {
            _lastStartOfTurnSecretCheck = turn
            if entity.isMinion && entity.isControlled(by: game.opponent.id) {
                exclude(cardId: CardIds.Secrets.Paladin.CompetitiveSpirit)
                if game.opponentMinionCount >= 2 && freeSpaceOnBoard {
                    exclude(cardId: CardIds.Secrets.Hunter.OpenTheCages)
                }
            }
            if !opponentTookDamageDuringTurns.contains(game.turnNumber() - 1) {
                exclude(cardId: CardIds.Secrets.Mage.RiggedFaireGame)
            }
        }
    }
    
    func handlePlayerTurnStart() {
        savedSecrets.removeAll()
    }
    
    func handleOpponentTurnStart() {
        if game.player.cardsPlayedThisTurn.count > 0 {
            exclude(cardId: CardIds.Secrets.Rogue.Plagiarize)
        }
    }
    
    func secretTriggered(entity: Entity) {
        _triggeredSecrets.append(entity)
    }

    func handleCardPlayed(entity: Entity) {
        guard handleAction else { return }
        
        savedSecrets.removeAll()

        var exclude: [String] = []
        
        if freeSpaceOnBoard {
            if let player = game.playerEntity, player.has(tag: .num_cards_played_this_turn) &&
                (player[.num_cards_played_this_turn] >= 3) {
                    exclude.append(CardIds.Secrets.Hunter.RatTrap)
            }
        }
        
        if freeSpaceInHand {
            if let player = game.playerEntity, player.has(tag: .num_cards_played_this_turn) &&
                (player[.num_cards_played_this_turn] >= 3) {
                exclude.append(CardIds.Secrets.Paladin.HiddenWisdom)
            }
        }
        
        if entity.isSpell {
            _triggeredSecrets.removeAll()
            if game.opponentSecretCount > 1 {
                usleep(useconds_t(1000 * multipleSecretResolveDelay))
            }
            
            exclude.append(CardIds.Secrets.Mage.Counterspell)
            
            if _triggeredSecrets.any({ x in x.cardId == CardIds.Secrets.Mage.Counterspell }) {
                self.exclude(cardIds: exclude)
                return
            }

            exclude.append(CardIds.Secrets.Paladin.OhMyYogg)
            
            if game.opponentMinionCount > 0 {
                exclude.append(CardIds.Secrets.Paladin.NeverSurrender)
            }

            if freeSpaceInHand {
                exclude.append(CardIds.Secrets.Rogue.DirtyTricks)
                exclude.append(CardIds.Secrets.Mage.ManaBind)
            }

            if freeSpaceOnBoard {
                // CARD_TARGET is set after ZONE, wait for 50ms gametime before checking
                do {
                    try await {
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    if let target = game.entities[entity[.card_target]],
                        entity.has(tag: .card_target),
                        target.isMinion {
                        exclude.append(CardIds.Secrets.Mage.Spellbender)
                    }
                    exclude.append(CardIds.Secrets.Hunter.CatTrick)
                    exclude.append(CardIds.Secrets.Mage.NetherwindPortal)
                } catch {
                    logger.error("\(error)")
                }
            }

            if game.playerMinionCount > 0 {
                exclude.append(CardIds.Secrets.Hunter.PressurePlate)
            }
        } else if entity.isMinion && game.playerMinionCount > 3 {
            exclude.append(CardIds.Secrets.Paladin.SacredTrial)
        }
        self.exclude(cardIds: exclude)
    }
    
    func onNewSecret(secret: Secret) {
        if secret.entity[GameTag.class] == CardClass.allCases.index(of: .hunter) {
            entititesInHandOnMinionsPlayed.removeAll()
        }
    }

    func handleHeroPower() {
        guard handleAction else { return }
        exclude(cardId: CardIds.Secrets.Hunter.DartTrap)
    }
}
