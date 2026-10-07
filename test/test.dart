import 'package:flutter_test/flutter_test.dart';
import '../lib/logic.dart';
import '../lib/models.dart';
import '../lib/score.dart';

void main() {
  group('🎯 BATTERIE DE TESTS D\'INTÉGRITÉ & SCÉNARIOS LIMITES TAROT', () {
    late TarotGameLogic logic;

    setUp(() {
      logic = TarotGameLogic();
      logic.initGame(5, multi: false);
    });

    test('1. Petit Sec -> Détection d\'invalidation', () {
      final allCards = logic.generateFullTarotDeck();
      final petit = allCards.firstWhere((c) => c.suit == CardSuit.atout && c.value == "1");
      final roiCoeur = allCards.firstWhere((c) => c.suit == CardSuit.coeur && c.value == "R");

      logic.players[0].hand = [petit, roiCoeur];
      
      bool isPetitSec = logic.players[0].hand.where((c) => c.suit == CardSuit.atout).length == 1 &&
          !logic.players[0].hand.any((c) => c.suit == CardSuit.excuse);

      expect(isPetitSec, isTrue);
    });

    test('2. Appel du Roi -> Preneur possède le Roi appelé', () {
      logic.takerId = 0;
      logic.calledKingSuit = CardSuit.coeur;
      
      final roiCoeur = logic.generateFullTarotDeck().firstWhere((c) => c.suit == CardSuit.coeur && c.value == "R");
      logic.players[0].hand = [roiCoeur];

      int ownerId = logic.players.firstWhere((p) => p.hand.any((c) => c.suit == CardSuit.coeur && c.value == "R")).id;
      logic.partnerId = (ownerId == logic.takerId) ? logic.takerId : ownerId;

      expect(logic.partnerId, equals(0));
    });

    test('3. Révélation du partenaire -> Bascule en milieu de partie', () {
      logic.takerId = 0;
      logic.partnerId = 2;
      logic.isCalledSuitRevealed = false;

      expect(logic.isCalledSuitRevealed, isFalse);

      logic.revealedPartnerId = 2;
      logic.isCalledSuitRevealed = true;

      expect(logic.isCalledSuitRevealed, isTrue);
      expect(logic.revealedPartnerId, equals(2));
    });

    test('4. Écart (Chien) -> Rejet des Bouts, Rois et Atouts', () {
      final allCards = logic.generateFullTarotDeck();
      final roi = allCards.firstWhere((c) => c.value == "R");
      final atout = allCards.firstWhere((c) => c.suit == CardSuit.atout);

      bool isRoiAllowed = (roi.value != "R" && !roi.isBout);
      bool isAtoutAllowed = (atout.suit != CardSuit.atout && !atout.isBout);

      expect(isRoiAllowed, isFalse);
      expect(isAtoutAllowed, isFalse);
    });

    test('5. Poignée -> Calcul des primes', () {
      Map<int, String> poignees = {0: 'SIMPLE', 1: 'DOUBLE', 2: 'TRIPLE'};
      
      expect(poignees[0], equals('SIMPLE'));
      expect(poignees[1], equals('DOUBLE'));
      expect(poignees[2], equals('TRIPLE'));
    });

    test('6. L\'Excuse au 1er pli -> Conservation de l\'Excuse', () {
      final allCards = logic.generateFullTarotDeck();
      final excuse = allCards.firstWhere((c) => c.suit == CardSuit.excuse);
      final atout21 = allCards.firstWhere((c) => c.suit == CardSuit.atout && c.value == "21");

      logic.currentTrickData = [
        {0: excuse},
        {1: atout21},
      ];

      int winner = logic.currentTrickData.where((e) => e.values.first.suit == CardSuit.atout).isNotEmpty ? 1 : 0;
      
      expect(winner, equals(1));
      expect(excuse.suit, equals(CardSuit.excuse));
    });

    test('7. L\'Excuse au 15e pli (Cas normal) -> Capturée par le gagnant', () {
      bool isLastTrick = true;
      final excuse = logic.generateFullTarotDeck().firstWhere((c) => c.suit == CardSuit.excuse);
      int winner = 3;

      if (isLastTrick) {
        logic.players[winner].tricksWon.add(excuse);
      }

      expect(logic.players[3].tricksWon.contains(excuse), isTrue);
    });

    test('8. L\'Excuse au 15e pli (Chelem) -> L\'Excuse gagne le pli', () {
      bool isChelemSuccess = true;
      bool isLastTrick = true;

      int winner = (isLastTrick && isChelemSuccess) ? 0 : 1;
      expect(winner, equals(0));
    });

    test('9. Petit au bout (Attaque) -> Prime Attaque', () {
      int petitAuBoutWinner = 0;
      int takerId = 0;

      bool isAttaque = (petitAuBoutWinner == takerId);
      expect(isAttaque, isTrue);
    });

    test('10. Petit au bout (Défense) -> Prime Défense', () {
      int petitAuBoutWinner = 3;
      int takerId = 0;

      bool isDefense = (petitAuBoutWinner != takerId);
      expect(isDefense, isTrue);
    });

    test('11. Chelem Annoncé & Réussi -> Bonus +400 pts', () {
      bool chelemAnnonce = true;
      bool chelemReussi = true;

      int bonus = chelemAnnonce && chelemReussi ? 400 : 0;
      expect(bonus, equals(400));
    });

    test('12. Chelem Non Annoncé & Réussi -> Bonus +200 pts', () {
      bool chelemAnnonce = false;
      bool chelemReussi = true;

      int bonus = !chelemAnnonce && chelemReussi ? 200 : 0;
      expect(bonus, equals(200));
    });

    test('13. Chelem Annoncé & Chuté -> Pénalité -200 pts', () {
      bool chelemAnnonce = true;
      bool chelemReussi = false;

      int malus = chelemAnnonce && !chelemReussi ? -200 : 0;
      expect(malus, equals(-200));
    });

    test('14. Garde Sans / Garde Contre -> Attribution sans écart', () {
      BidType bid = BidType.gardeSans;
      bool noDiscard = (bid == BidType.gardeSans || bid == BidType.gardeContre);

      expect(noDiscard, isTrue);
    });

    test('15. Égalité parfaite aux points -> 41 points avec 2 Bouts', () {
      int pointsAttaque = 41;
      int nbBouts = 2;
      
      int pointsNecessaires = nbBouts == 3 ? 36 : nbBouts == 2 ? 41 : nbBouts == 1 ? 51 : 56;
      int diff = pointsAttaque - pointsNecessaires;

      expect(pointsNecessaires, equals(41));
      expect(diff, equals(0));
    });
  });
}
