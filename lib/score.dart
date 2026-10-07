import 'package:tarot_app/models.dart';

class ScoringLogic {
  static double getRequiredPoints(int bouts) {
    if (bouts == 3) return 36.0;
    if (bouts == 2) return 41.0;
    if (bouts == 1) return 51.0;
    return 56.0; // 0 bout
  }

  /// Indique clairement si le preneur a réussi son contrat ou chuté
  static bool didTakerWin({
    required List<Player> players,
    required int takerId,
    int? partnerId,
    List<CardModel> ecartCards = const [],
  }) {
    double scoreAttaque = 0.0;
    int nbBouts = 0;

    for (var p in players) {
      double pts = 0.0;
      for (var c in p.tricksWon) {
        pts += c.points;
      }
      if (p.id == takerId && ecartCards.isNotEmpty) {
        for (var card in ecartCards) {
          pts += card.points;
        }
      }

      if (p.id == takerId || (partnerId != null && p.id == partnerId)) {
        scoreAttaque += pts;
        nbBouts += p.tricksWon.where((c) => c.isBout).length;
      }
    }

    double required = getRequiredPoints(nbBouts);
    return scoreAttaque >= required;
  }

  static Map<String, double> getLiveBalance(
    List<Player> players, 
    int takerId, 
    int? partnerId, {
    bool isPartnerRevealed = true,
    List<CardModel> ecartCards = const [],
  }) {
    double takerTotal = 0.0;
    double defenseTotal = 0.0;
    
    if (players.isEmpty) return {'taker': 0.0, 'defense': 0.0};

    int? effectivePartner = isPartnerRevealed ? partnerId : null;

    int totalCardsWon = 0;
    for (var p in players) {
      totalCardsWon += p.tricksWon.length;
    }

    int cardsPerTrick = players.length;
    int maxTricks = (players.length == 5) ? 15 : 13;
    int totalTricksPlayed = totalCardsWon ~/ cardsPerTrick;

    for (var p in players) {
      double pts = 0.0;
      if (p.tricksWon.isNotEmpty) {
        for (var card in p.tricksWon) { 
          pts += card.points; 
        }
      }
      
      if (p.id == takerId && ecartCards.isNotEmpty) {
        bool isGameFinished = players.every((pl) => pl.hand.isEmpty) || totalTricksPlayed >= maxTricks;
        if (isGameFinished) {
          for (var card in ecartCards) {
            pts += card.points;
          }
        }
      }
      
      if (p.id == takerId || (effectivePartner != null && p.id == effectivePartner)) {
        takerTotal += pts;
      } else {
        defenseTotal += pts;
      }
    }
    return {'taker': takerTotal, 'defense': defenseTotal};
  }

  static Map<int, double> computeFinalGains({
    required List<Player> players,
    required int takerId,
    int? partnerId,
    required BidType? selectedBid,
    int? petitAuBoutWinner,
    Map<int, String>? poignees,
    List<CardModel> ecartCards = const [],
  }) {
    if (selectedBid == null || players.isEmpty) return {};
    
    double takerTotalFinal = 0.0;
    double defenseTotalFinal = 0.0;
    int? effectivePartner = partnerId;

    for (var p in players) {
      double pts = 0.0;
      for (var c in p.tricksWon) {
        pts += c.points;
      }
      if (p.id == takerId && ecartCards.isNotEmpty) {
        for (var card in ecartCards) {
          pts += card.points;
        }
      }
      if (p.id == takerId || (effectivePartner != null && p.id == effectivePartner)) {
        takerTotalFinal += pts;
      } else {
        defenseTotalFinal += pts;
      }
    }

    double scoreAttaque = takerTotalFinal;
    int nbBouts = 0;
    
    for (var p in players) {
      if (p.id == takerId || (partnerId != null && p.id == partnerId)) {
        nbBouts += p.tricksWon.where((c) => c.isBout).length;
      }
    }
    
    double required = getRequiredPoints(nbBouts);
    double diff = scoreAttaque - required;
    
    double base = 25 + diff.abs();
    
    if (petitAuBoutWinner != null) {
      bool sideTaker = (petitAuBoutWinner == takerId || (partnerId != null && petitAuBoutWinner == partnerId));
      if (diff >= 0) {
        base += sideTaker ? 10 : -10;
      } else {
        base += sideTaker ? -10 : 10;
      }
    }
    
    if (diff < 0) base = -base;
    
    int mult = 1;
    switch (selectedBid) {
      case BidType.petite: mult = 1; break;
      case BidType.garde: mult = 2; break;
      case BidType.gardeSans: mult = 4; break;
      case BidType.gardeContre: mult = 6; break;
      default: mult = 1;
    }
    
    double finalBase = base * mult;
    double totalPrimesPoignees = 0;
    
    if (poignees != null) {
      poignees.forEach((pid, type) {
        double valeur = (type == "TRIPLE") ? 50 : (type == "DOUBLE") ? 30 : 20;
        bool isAnnonceurAttaque = (pid == takerId || (partnerId != null && pid == takerId));
        if (diff >= 0) {
          totalPrimesPoignees += isAnnonceurAttaque ? valeur : -valeur;
        } else {
          totalPrimesPoignees += isAnnonceurAttaque ? -valeur : valeur;
        }
      });
    }
    
    double scoreParPart = finalBase + totalPrimesPoignees;
    Map<int, double> results = {};
    int nbPlayers = players.length;
    
    for (var p in players) {
      if (p.id == takerId) {
        if (nbPlayers == 5 && partnerId != null && partnerId != takerId) {
          results[p.id] = scoreParPart * 2;
        } else {
          results[p.id] = scoreParPart * (nbPlayers - 1);
        }
      } else if (nbPlayers == 5 && partnerId != null && p.id == partnerId) {
        results[p.id] = scoreParPart;
      } else {
        results[p.id] = -scoreParPart;
      }
    }
    return results;
  }
}
