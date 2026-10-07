import 'package:tarot_app/models.dart';

class TarotAI {
  // --- MÉMOIRE VIVE CONTENUE ---
  static Map<int, Set<CardSuit>> chicanesGlobales = {};
  static List<CardModel> cartesTombees = [];

  static void resetMemory(int playerCount) {
    chicanesGlobales = {for (int i = 0; i < playerCount; i++) i: {}};
    cartesTombees = [];
  }

  static void analyzeTrick(List<Map<int, CardModel>> trick, CardSuit leadSuit) {
    for (var entry in trick) {
      if (entry.isEmpty) continue;
      int pid = entry.keys.first;
      CardModel card = entry.values.first;
      cartesTombees.add(card);
      
      // Détection des chicanes
      if (card.suit != leadSuit && card.suit != CardSuit.atout && card.suit != CardSuit.excuse) {
        chicanesGlobales[pid]?.add(leadSuit);
      }
    }
  }

  // --- LOGIQUE D'ENCHÈRE (SÉCURISÉE) ---
  static BidType decideBid(Player p) {
    int atouts = p.hand.where((c) => c.suit == CardSuit.atout).length;
    double points = p.hand.fold(0.0, (prev, c) => prev + c.points);
    int bouts = p.hand.where((c) => c.isBout).length;

    if ((atouts >= 10 && bouts >= 1) || (atouts >= 8 && bouts >= 2) || (atouts >= 7 && bouts == 3)) {
      return BidType.garde;
    }
    
    if (bouts >= 2 && (atouts >= 6 || points > 40)) return BidType.petite;
    if (bouts == 1 && (atouts >= 8 || (atouts >= 6 && points >= 45))) return BidType.petite;
    if (bouts == 0 && atouts >= 11) return BidType.petite;
    
    return BidType.pass;
  }

  // --- VALIDATION STRICTE DES RÈGLES DU TAROT (FILTRAGE DES CARTES) ---
  static List<CardModel> getStrictlyValidPlayableCards(
    List<CardModel> hand, 
    CardSuit? leadSuit, 
    List<Map<int, CardModel>> currentTrick, {
    CardSuit? calledKing,
  }) {
    if (hand.isEmpty) return [];

    // 👑 RÈGLE SPÉCIALE : Premier tour d'entame de la couleur du roi appelé
    if (currentTrick.isEmpty && calledKing != null) {
      bool calledSuitPlayed = cartesTombees.any((c) => c.suit == calledKing);
      if (!calledSuitPlayed) {
        bool hasKing = hand.any((c) => c.suit == calledKing && c.value == "R");
        if (!hasKing) {
          List<CardModel> valid = hand.where((c) => c.suit != calledKing).toList();
          var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
          if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
          return valid;
        } else {
          List<CardModel> valid = hand.where((c) => c.suit != calledKing || (c.suit == calledKing && c.value == "R")).toList();
          var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
          if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
          return valid;
        }
      }
    }
    
    CardSuit? activeLeadSuit = leadSuit;
    
    if (activeLeadSuit == null && currentTrick.isNotEmpty) {
      for (var entry in currentTrick) {
        if (entry.isEmpty) continue;
        var cardInTrick = entry.values.first;
        if (cardInTrick.suit != CardSuit.excuse) {
          activeLeadSuit = cardInTrick.suit;
          break;
        }
      }
    }

    if (activeLeadSuit == null || activeLeadSuit == CardSuit.excuse) {
      return List.from(hand);
    }

    // 🔒 CORRECTION : Si l'atout est demandé/mené, on applique immédiatement l'obligation de monter
    if (activeLeadSuit == CardSuit.atout) {
      List<CardModel> trumps = hand.where((c) => c.suit == CardSuit.atout).toList();
      if (trumps.isNotEmpty) {
        int maxTrumpPower = 0;
        for (var e in currentTrick) {
          if (e.isNotEmpty && e.values.first.suit == CardSuit.atout) {
            if (e.values.first.power > maxTrumpPower) {
              maxTrumpPower = e.values.first.power;
            }
          }
        }

        if (maxTrumpPower > 0) {
          var higherTrumps = trumps.where((c) => c.power > maxTrumpPower).toList();
          if (higherTrumps.isNotEmpty) {
            List<CardModel> valid = List.from(higherTrumps);
            var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
            if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
            return valid; // 🔒 Obligation absolue de surcoupe à l'atout
          }
        }

        List<CardModel> valid = List.from(trumps);
        var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
        if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
        return valid;
      }
      return List.from(hand);
    }

    // 1. Règle de la couleur demandée
    List<CardModel> colorCards = hand.where((c) => c.suit == activeLeadSuit).toList();
    if (colorCards.isNotEmpty) {
      List<CardModel> valid = List.from(colorCards);
      var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
      if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
      return valid;
    }

    // 2. Obligation stricte de couper et de monter à l'atout si possible
    List<CardModel> trumps = hand.where((c) => c.suit == CardSuit.atout).toList();
    if (trumps.isNotEmpty) {
      int maxTrumpPower = 0;
      for (var e in currentTrick) {
        if (e.isNotEmpty && e.values.first.suit == CardSuit.atout) {
          if (e.values.first.power > maxTrumpPower) {
            maxTrumpPower = e.values.first.power;
          }
        }
      }

      if (maxTrumpPower > 0) {
        var higherTrumps = trumps.where((c) => c.power > maxTrumpPower).toList();
        if (higherTrumps.isNotEmpty) {
          List<CardModel> valid = List.from(higherTrumps);
          var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
          if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
          return valid; // 🔒 Obligation absolue de surcoupe
        }
      }

      List<CardModel> valid = List.from(trumps);
      var excuse = hand.where((c) => c.suit == CardSuit.excuse).firstOrNull;
      if (excuse != null && !valid.contains(excuse)) valid.add(excuse);
      return valid;
    }

    // 3. Défausse libre (Pisser)
    return List.from(hand);
  }

  // --- LE CERVEAU : DÉCISION DE LA CARTE ---
  static CardModel decideCardToPlay({
    required List<CardModel> playableCards,
    CardSuit? leadSuit,
    CardSuit? calledKing,
    required int myId,
    int? tId,
    int? pId,
    required List<Map<int, CardModel>> currentTrick,
    required int totalTricksPlayed,
    required int totalPlayers,
  }) {
    final List<CardModel> strictCards = getStrictlyValidPlayableCards(
      playableCards, leadSuit, currentTrick, calledKing: calledKing
    );
    List<CardModel> candidates = strictCards.isNotEmpty ? strictCards : playableCards;

    if (candidates.isEmpty) return generateFallbackDeck().first;
    if (candidates.length == 1) return candidates.first;

    final bool isLastTrick = totalTricksPlayed >= (totalPlayers == 5 ? 14 : totalPlayers == 4 ? 17 : 23);

    // -----------------------------------------------------------------------
    // 🃏 RÈGLE ABSOLUE : L'EXCUSE NE DOIT JAMAIS ÊTRE JOUÉE AU DERNIER PLI[cite: 4]
    // -----------------------------------------------------------------------
    if (isLastTrick && candidates.length > 1) {
      var sansExcuse = candidates.where((c) => c.suit != CardSuit.excuse).toList();
      if (sansExcuse.isNotEmpty) {
        candidates = sansExcuse; 
      }
    }

    if (tId == null) {
      return candidates.first;
    }

    final bool isTakerSide = (myId == tId || (pId != null && myId == pId));
    final bool isEndGame = totalTricksPlayed > 13;
    final bool isKingRevealed = (pId != null || calledKing == null);
    
    CardModel? bestOnTable;
    int? currentWinnerId;
    if (currentTrick.isNotEmpty) {
      bestOnTable = _getBestOnTable(currentTrick, leadSuit);
      if (bestOnTable != null) {
        try {
          currentWinnerId = currentTrick.firstWhere((e) => e.values.first == bestOnTable).keys.first;
        } catch (_) {
          currentWinnerId = null;
        }
      }
    }

    bool allyIsMaster = false;
    if (currentWinnerId != null) {
      bool winnerIsTakerSide = (currentWinnerId == tId || (pId != null && currentWinnerId == pId));
      allyIsMaster = (isTakerSide == winnerIsTakerSide);
    }

    // --- CHASSE AU ROI APPELÉ DÈS LE 2E PLI ---
    if (currentTrick.isEmpty && totalTricksPlayed >= 1 && !isKingRevealed && !isTakerSide) {
      var atoutsChasse = candidates.where((c) => c.suit == CardSuit.atout && c.value != "1").toList();
      if (atoutsChasse.isNotEmpty) {
        atoutsChasse.sort((a, b) => b.power.compareTo(a.power));
        return atoutsChasse.first;
      }
    }

    // --- GESTION TACTIQUE DE L'EXCUSE (Pli lourd, pli de merde ou économie d'atouts) ---
    CardModel? excuse = candidates.where((c) => c.suit == CardSuit.excuse).firstOrNull;
    if (excuse != null && currentTrick.isNotEmpty && !isLastTrick) {
      double trickPointsOnTable = currentTrick.fold(0.0, (sum, e) => sum + e.values.first.points);
      
      // Si le pli est lourd (beaucoup de points) ou qu'on risque de gaspiller un bel atout sur un pli indéfendable
      if (!allyIsMaster && (trickPointsOnTable >= 3.0 || bestOnTable?.suit == CardSuit.atout)) {
        return excuse;
      }
      if (isTakerSide && leadSuit != null && !candidates.any((c) => c.suit == leadSuit) && !isEndGame) {
        return excuse;
      }
    }

    bool willBeCutByDefense = false;
    if (leadSuit != null && isTakerSide) {
      for (int i = 0; i < totalPlayers; i++) {
        if (currentTrick.any((e) => e.containsKey(i)) || i == myId) continue;
        bool isEnemy = (i != tId && (pId == null || i != pId));
        if (isEnemy && chicanesGlobales[i]?.contains(leadSuit) == true) {
          willBeCutByDefense = true;
          break;
        }
      }
    }

    // --- PROTECTION DU PETIT D'ATOUT ---
    CardModel? petit = candidates.where((c) => c.suit == CardSuit.atout && c.value == "1").firstOrNull;
    if (petit != null) {
      bool forced = candidates.length == 1;
      if (!forced && !isLastTrick) {
        if (!allyIsMaster || bestOnTable == null) {
          var backup = candidates.where((c) => c != petit).toList();
          if (backup.isNotEmpty) {
            if (excuse != null && !isLastTrick) return excuse;
            backup.sort((a, b) => a.power.compareTo(b.power));
            return backup.first;
          }
        }
      }
    }

    // --- ENTAME (PREMIER À JOUER) AVEC ÉCONOMIE DES GROSSES CARTES ---
    if (currentTrick.isEmpty) {
      if (petit != null && excuse != null && !isLastTrick) return excuse;
      
      if (isTakerSide && totalTricksPlayed < 6) {
        var trumps = candidates.where((c) => c.suit == CardSuit.atout && c != petit).toList();
        if (trumps.length >= 4) {
          trumps.sort((a, b) => b.power.compareTo(a.power));
          return trumps.first;
        }
      }

      var colorCards = candidates.where((c) => c.suit != CardSuit.atout && c.suit != CardSuit.excuse).toList();
      if (colorCards.isNotEmpty) {
        // 🔒 Si le roi n'est pas révélé et qu'on est en défense, on planque nos grosses cartes[cite: 4]
        if (!isKingRevealed && !isTakerSide) {
          var weakCards = colorCards.where((c) => c.points < 2.5).toList();
          if (weakCards.isNotEmpty) {
            weakCards.sort((a, b) => a.points.compareTo(b.points));
            return weakCards.first;
          }
        }

        colorCards.sort((a, b) => a.power.compareTo(b.power));
        
        if (isTakerSide && isEndGame) {
          var smallCards = colorCards.where((c) => c.points < 1.5).toList();
          if (smallCards.isNotEmpty) return smallCards.first;
        }

        var safeChoices = colorCards.where((card) {
          for (int i = 0; i < totalPlayers; i++) {
            if (i == myId) continue;
            bool isEnemy = isTakerSide ? (i != tId && (pId == null || i != pId)) : (i == tId || (pId != null && i == pId));
            if (isEnemy && chicanesGlobales[i]?.contains(card.suit) == true) return false;
          }
          return true;
        }).toList();

        if (safeChoices.isNotEmpty) return safeChoices.first;
        return colorCards.last;
      }
    }

    // --- GESTION DES PLIS DÉJÀ ENTAMÉS ---
    if (bestOnTable != null) {
      var winningCards = candidates.where((c) => _canWin(c, bestOnTable!, leadSuit)).toList();
      
      if (winningCards.isNotEmpty) {
        winningCards.sort((a, b) => a.power.compareTo(b.power));
        
        if (winningCards.first == petit && !isLastTrick && winningCards.length > 1) {
          return winningCards[1];
        }
        
        if (isTakerSide && winningCards.first.suit == CardSuit.atout && bestOnTable.points < 1.0 && !isEndGame) {
           var throwAway = candidates.where((c) => c.suit != CardSuit.atout).toList();
           if (throwAway.isNotEmpty) {
             throwAway.sort((a, b) => a.points.compareTo(b.points));
             return throwAway.first;
           }
        }

        return winningCards.first;
      } else {
        var atoutsDispo = candidates.where((c) => c.suit == CardSuit.atout).toList();
        if (atoutsDispo.isNotEmpty) {
          var atoutsSansPetit = atoutsDispo.where((c) => c != petit).toList();
          if (atoutsSansPetit.isNotEmpty) {
            atoutsSansPetit.sort((a, b) => a.power.compareTo(b.power));
            return atoutsSansPetit.first; 
          }
          return atoutsDispo.first;
        }

        var defausses = candidates.where((c) => c.suit != CardSuit.atout && c.suit != CardSuit.excuse).toList();
        if (defausses.isNotEmpty) {
          defausses.sort((a, b) => a.points.compareTo(b.points));
          return defausses.first; 
        }
      }
    }

    // --- CHARGEMENT DE POINTS SI L'ALLIÉ GAGNE LE PLI ---
    if (allyIsMaster) {
      if (isLastTrick && petit != null) return petit;
      if (!willBeCutByDefense) {
        candidates.sort((a, b) => b.points.compareTo(b.points));
        return candidates.first;
      }
    }

    // --- RECOURS ---
    List<CardModel> choices = List.from(candidates);
    if (choices.length > 1 && petit != null) choices.remove(petit);
    
    choices.sort((a, b) => a.points.compareTo(b.points));
    if (choices.isNotEmpty && choices.first.suit == CardSuit.atout && choices.length > 1) {
      choices.sort((a, b) => b.power.compareTo(b.power));
    }

    return choices.isEmpty ? candidates.first : choices.first;
  }

  static CardModel? _getBestOnTable(List<Map<int, CardModel>> trick, CardSuit? lead) {
    if (trick.isEmpty) return null;
    CardModel best = trick.first.values.first;
    for (var i = 1; i < trick.length; i++) {
      if (trick[i].isEmpty) continue;
      CardModel current = trick[i].values.first;
      if (_canWin(current, best, lead)) best = current;
    }
    return best;
  }

  static bool _canWin(CardModel challenger, CardModel currentBest, CardSuit? lead) {
    if (challenger.suit == CardSuit.excuse) return false;
    if (currentBest.suit == CardSuit.atout) {
      if (challenger.suit != CardSuit.atout) return false;
      return challenger.power > currentBest.power;
    }
    if (challenger.suit == CardSuit.atout) return true;
    if (challenger.suit != lead) return false;
    return challenger.power > currentBest.power;
  }

  static bool shouldCallKing(List<CardModel> hand) {
    return hand.where((c) => c.suit == CardSuit.atout).length > 6;
  }

  static List<CardModel> generateFallbackDeck() {
    return [CardModel(id: 999, suit: CardSuit.excuse, value: "Excuse", power: 0, points: 4.5, isBout: true, assetPath: "")];
  }
}
