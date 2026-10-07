// --- SDK DART ---
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

// --- PACKAGES FLUTTER & TIERS ---
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

// --- FICHIERS LOCAUX ---
import 'models.dart';
import 'ia.dart';
import 'remote_logger.dart';
import 'score.dart';
import 'permissions_service.dart';
import 'geo_service.dart';
import 'audio_service.dart';
import 'tarot_audit_system.dart' hide CardSuit;
import 'token_manager.dart';

// Clé globale pour accéder au BuildContext pour les pop-ups de permissions
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class TarotGameLogic extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  // --- SYSTÈMES DE GESTION DYNAMIQUE ET PERMISSIONS ---
  int currentTableEntryFee = 200; 
  int totalGamesCompleted = 0;    

  TarotGameLogic() {
    _initAudio();
  }

  void _initAudio() async {
    await AudioService.instance.initAudio();
  }

  Future<void> _playCardSound() async {
    await AudioService.instance.playSfx('sounds/carte1.mp3');
  }

  Future<void> playBackgroundTrack1() async {
    await AudioService.instance.playBackgroundMusic('sounds/music_track_1.mp3');
  }

  Future<void> playBackgroundTrack2() async {
    await AudioService.instance.playBackgroundMusic('sounds/music_track_2.mp3');
  }

  Future<void> stopBackgroundMusic() async {
    await AudioService.instance.toggleMusic(false);
  }

  void _logSpy(String tag, String message, {int? playerSlot, Map<String, dynamic>? extraData}) {
    final now = DateTime.now().toUtc();
    final ms = now.millisecond.toString().padLeft(3, '0');
    final timeStr = "${now.toIso8601String().split('.').first}.$ms";
    
    debugPrint("🕵️‍♂️ [ESPION_LOG][$timeStr][$tag] ${playerSlot != null ? 'Slot $playerSlot | ' : ''}$message ${extraData != null ? '| Extra: $extraData' : ''}");
  }

  Future<void> signInWithGoogle() async {
    try {
      callMessage = "Connexion à Google...";
      notifyListeners();
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? 'http://localhost:5000' : 'io.supabase.flutter://google-auth',
        queryParams: {'access_type': 'offline', 'prompt': 'consent'},
      );
    } catch (e) {
      callMessage = "Erreur : $e";
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    callMessage = "Déconnecté";
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  Future<bool> deductEntryFee({int? entryFee}) async {
    final fee = entryFee ?? currentTableEntryFee;
    currentTableEntryFee = fee;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return true;
      }

      bool success = await TokenManager.debitStake(fee);
      if (!success) {
        callMessage = "Jetons insuffisants ! Il te faut $fee jetons.";
        notifyListeners();
        return false;
      }

      notifyListeners();
      return true;
    } catch (e) {
      callMessage = "Erreur de connexion au portefeuille jetons.";
      notifyListeners();
      return false;
    }
  }

  Future<void> syncPlayerLocation() async {
    try {
      Position? position = await GeoService.getCurrentLocation();
      if (position != null && _supabase.auth.currentUser != null) {
        await _supabase.from('profiles').update({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'last_active': DateTime.now().toIso8601String(),
        }).eq('id', _supabase.auth.currentUser!.id);
      }
    } catch (e) {
      _logSpy("GEO_ERR", "Erreur synchro position : $e");
    }
  }

  List<Player> players = [];
  GameState currentState = GameState.idle;
  int currentPlayerIndex = 0;
  int? dealerIndex;
  List<CardModel> chien = [];
  List<Map<int, CardModel>> currentTrickData = [];
  List<CardModel> lastTrickCards = [];
  BidType? selectedBid;
  bool isChelemAnounced = false;
  int? takerId;
  int? partnerId;
  int? revealedPartnerId;
  CardSuit? calledKingSuit;
  bool isCalledSuitRevealed = false;
  String lastBidName = "";
  int? get calledKingId => calledKingSuit?.index;
  List<CardModel> get currentTrick => currentTrickData.map((e) => e.values.first).toList();
  int? lastWinnerIndex;
  String? lastCardPlayed;

  int version = 1;
  bool hasClickedBid = false;
  bool hasClickedKing = false;
  bool cardsRevealed = false;

  int manchesRestantes = 0;
  String currentDeckHash = "";
 
  final _timeController = StreamController<double>.broadcast();
  Stream<double> get remainingTimeStream => _timeController.stream;
  double _remainingTime = 30.0;
  double get remainingTime => _remainingTime;
  set remainingTime(double value) {
    if ((_remainingTime - value).abs() < 0.5) return;
    _remainingTime = value;
    _timeController.add(value);
    notifyListeners();
  }

  Timer? _turnTimer;
  Timer? _autoNextGameTimer;
  Map<int, double> sessionScores = {};
  List<Map<String, dynamic>> historyManches = [];

  int currentManche = 1;
  double currentTakerScore = 0.0;
  double currentDefenseScore = 0.0;
  List<CardModel> currentEcartVisual = [];
  CardSuit? leadSuit;
  int tricksCount = 0;
  String callMessage = "En attente de connexion...";
  bool _isProcessing = false;
  bool showPoigneeButton = false;
  Map<int, String> poigneesAnnoncees = {};
  Map<int, double> cardRotations = {};
  int? petitAuBoutWinner;  

  String? tableId;
  bool isMultiplayer = false;
  bool isHost = false;
  int _myMultiplayerSide = 0;
  dynamic multiplayerManager;
  int get myMultiplayerSide => _myMultiplayerSide;
  set myMultiplayerSide(int value) {
    if (_myMultiplayerSide == value) return;
    _myMultiplayerSide = value;
    notifyListeners();
  }

  List<bool> _actualBots = [false, false, false, false, false];
  bool _preparingDiscard = false;
  
  bool _isNextMancheLock = false; 
  bool _isDistributeLock = false;

  final Set<int> _inactiveAiPlayers = {};
  Set<int> get inactiveAiPlayers => _inactiveAiPlayers;
  
  final Set<int> inactiveHumanPlayers = {};

  Map<int, Map<String, dynamic>> lastBidsAnnounced = {};

  final _playerCountController = StreamController<int>.broadcast();
  Stream<int> get playerCountStream => _playerCountController.stream;

  Function(String type, Map<String, dynamic> data)? onActionBroadcast;

  void toggleZoom() { _iz = !_iz; notifyListeners(); }
  bool _iz = false;
  double get cardWidth => _iz ? 142.5 : 95.0;

  void sendQuickMessage(String message) {
    lastBidsAnnounced[myMultiplayerSide] = {
      'text': message,
      'time': DateTime.now(),
    };

    if (isMultiplayer && tableId != null) {
      _supabase.from('tarot_actions').insert({
        'table_id': tableId,
        'player_index': myMultiplayerSide,
        'action_type': 'QUICK_MESSAGE',
        'payload': {'msg': message, 'pid': myMultiplayerSide}
      }).then((_) {}).catchError((e) {});
    }

    notifyListeners();
  }

  Future<void> reportPlayer(int targetSlot, String reason) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('reports').insert({
        'reporter_id': user?.id ?? 'ANONYMOUS',
        'reported_slot': targetSlot,
        'table_id': tableId ?? 'LOCAL',
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _logSpy("REPORT_ERR", "Erreur signalement: $e");
    }
  }

  Future<void> sendGiftToPlayer(int targetSlot, String giftType) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        int balance = await TokenManager.getBalance();
        if (balance >= 50) {
          await TokenManager.debitStake(50);
          notifyListeners();
        }
      }
    } catch (e) {
      _logSpy("GIFT_ERR", "Erreur envoi cadeau: $e");
    }
  }

  Future<bool> checkAndResumeActiveGame() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _supabase
          .from('table_tarot_5')
          .select()
          .or('player0_uid.eq.${user.id},player1_uid.eq.${user.id},player2_uid.eq.${user.id},player3_uid.eq.${user.id},player4_uid.eq.${user.id}')
          .neq('game_status', 'FINISHED')
          .maybeSingle();

      if (response == null) {
        if (currentState != GameState.idle) {
          fullResetForExit();
        }
        return false;
      }

      tableId = response['table_id'];
      isMultiplayer = true;

      for (int i = 0; i < 5; i++) {
        if (response['player${i}_uid'] == user.id) {
          myMultiplayerSide = i;
          break;
        }
      }

      syncCommonData(response);

      if (response['turn_ends_at'] != null) {
        String rawTime = response['turn_ends_at'].toString();
        if (!rawTime.endsWith('Z') && !rawTime.contains('+')) rawTime += 'Z';
        DateTime expiration = DateTime.parse(rawTime).toUtc();
        
        if (DateTime.now().toUtc().isAfter(expiration)) {
          if (isHost || !isMultiplayer) {
            Future.delayed(const Duration(seconds: 1), () {
              forceTimeoutAction();
            });
          }
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }
 
  void _resetCleaMemory(int count) {
    TarotAI.resetMemory(count);
    cardRotations.clear();
    poigneesAnnoncees.clear();
    currentTrickData.clear();
    currentEcartVisual.clear();
    lastBidsAnnounced.clear();
    _inactiveAiPlayers.clear();
    inactiveHumanPlayers.clear();
    
    for (var p in players) {
      p.tricksWon.clear();
    }
   
    callMessage = "";
    currentTakerScore = 0.0;
    currentDefenseScore = 0.0;
   
    _turnTimer?.cancel();
    _autoNextGameTimer?.cancel();
   
    notifyListeners();
  }

  void _updateLiveScore() {
    var balance = ScoringLogic.getLiveBalance(
      players, 
      takerId ?? 0, 
      partnerId,
      isPartnerRevealed: isCalledSuitRevealed && revealedPartnerId != null,
      ecartCards: currentEcartVisual,
    );
    currentTakerScore = balance['taker']!;
    currentDefenseScore = balance['defense']!;
    notifyListeners();
  }

  void _recordBidForAvatar(BidType? b, int pid) {
    String bidText = (b == null || b == BidType.pass) ? "PASSE" : b.toString().split('.').last.toUpperCase();
    if (bidText == "GARDECONTRE") bidText = "G. CONTRE";
    if (bidText == "GARDESANS") bidText = "G. SANS";

    lastBidsAnnounced[pid] = {
      'text': bidText,
      'time': DateTime.now(),
    };
    notifyListeners();
  }

  void _checkPoignee(int pid) {
    if (currentState != GameState.playing || tricksCount > 0) {
      return;
    }
    int atouts = players[pid].hand.where((c) => c.suit == CardSuit.atout || c.suit == CardSuit.excuse).length;
    int requissage = (players.length == 5) ? 10 : 13;
    if (atouts >= requissage) {
      if (pid == myMultiplayerSide) {
        showPoigneeButton = true;
      } else {
        _autoAnnouncePoignee(pid, atouts);
      }
    }
  }

  void _autoAnnouncePoignee(int pid, int count) {
    String type = count >= 20 ? "TRIPLE" : count >= 13 ? "DOUBLE" : "SIMPLE";
    poigneesAnnoncees[pid] = type;
  }

  void _sortHand(List<CardModel> h) {
    h.sort((a, b) {
      int p(CardSuit s) {
        switch (s) {
          case CardSuit.atout: case CardSuit.excuse: return 0;
          case CardSuit.coeur: case CardSuit.pique: return 2;
          case CardSuit.carreau: case CardSuit.trefle: return 4;
        }
      }
      return p(a.suit) != p(b.suit) ? p(a.suit).compareTo(p(b.suit)) : b.power.compareTo(a.power);
    });
    for (var card in h) {
      card.assetPath = _getAssetPath(card.suit, card.value);
    }
  }

  String _getAssetPath(CardSuit s, String v) {
    if (s == CardSuit.excuse) {
      return "assets/images/cards/L'Excuse.png";
    }

    String sn = s.toString().split('.').last.toLowerCase();
    sn = sn.replaceAll('trefle', 'Trefle')
           .replaceAll('carreau', 'Carreau')
           .replaceAll('coeur', 'Coeur')
           .replaceAll('pique', 'Pique')
           .replaceAll('atout', 'Atout');

    String vn = v.replaceAll('R', 'Roi')
                 .replaceAll('D', 'Dame')
                 .replaceAll('C', 'Cavalier')
                 .replaceAll('V', 'Valet');

    return "assets/images/cards/${vn.isEmpty ? '?' : vn} de ${sn.isEmpty ? '?' : sn}.png";
  }

  BidType _iaSmartBidding() => TarotAI.decideBid(players[currentPlayerIndex]);

  int _bidRank(BidType? t) {
    if (t == BidType.petite) { return 1; }
    if (t == BidType.garde) { return 2; }
    if (t == BidType.gardeSans) { return 3; }
    if (t == BidType.gardeContre) { return 4; }
    return 0;
  }

  void _iaPlayCall() {
    var h = players[currentPlayerIndex].hand;
    List<CardSuit> suits = [CardSuit.coeur, CardSuit.carreau, CardSuit.pique, CardSuit.trefle];
    suits.removeWhere((x) => h.any((c) => c.suit == x && c.value == "R"));
    if (suits.isEmpty) {
      selectCalledKing(CardSuit.coeur);
      return;
    }
    suits.sort((a, b) => h.where((c) => c.suit == a).length.compareTo(h.where((c) => c.suit == b).length));
    selectCalledKing(suits.first);
  }

  void _iaSmartDiscard() {
    if (takerId == null) return;
    List<CardModel> h = players[takerId!].hand;
    currentEcartVisual.clear();
    int n = (players.length == 5 ? 3 : 6);
   
    List<CardSuit> suits = [CardSuit.pique, CardSuit.coeur, CardSuit.carreau, CardSuit.trefle];
    suits.sort((a, b) => h.where((c) => c.suit == a).length.compareTo(h.where((c) => c.suit == b).length));

    for (var s in suits) {
      var candidates = h.where((c) => c.suit == s && c.value != "R" && !c.isBout).toList();
      for (var card in candidates) {
        if (currentEcartVisual.length < n) {
          currentEcartVisual.add(card);
        }
      }
    }

    if (currentEcartVisual.length < n) {
      List<CardModel> remain = h.where((card) => !currentEcartVisual.contains(card) && card.suit != CardSuit.atout && card.value != "R").toList();
      remain.sort((a, b) => a.points.compareTo(b.points));
      while (currentEcartVisual.length < n && remain.isNotEmpty) {
        currentEcartVisual.add(remain.removeAt(0));
      }
    }

    for (var card in currentEcartVisual) {
      h.removeWhere((c) => c.id == card.id);
    }

    _sortHand(players[takerId!].hand);
    _finishDiscard();
  }

  CardModel _getBestAICard(List<CardModel> possible) {
    if (possible.isEmpty) {
      if (players[currentPlayerIndex].hand.isEmpty) return generateFullTarotDeck().first;
      return players[currentPlayerIndex].hand.first;
    }
   
    return TarotAI.decideCardToPlay(
      playableCards: possible,
      leadSuit: leadSuit,
      calledKing: calledKingSuit,
      myId: currentPlayerIndex,
      tId: takerId,
      pId: partnerId,
      currentTrick: currentTrickData,
      totalTricksPlayed: tricksCount,
      totalPlayers: players.length,
    );
  }

  void initGame(int pc, {bool multi = false, String? rid, int entryFee = 200}) async {
    currentTableEntryFee = entryFee;
    
    bool success = await deductEntryFee(entryFee: entryFee);
    if (!success) return;

    await syncPlayerLocation();

    sessionScores.clear();
    historyManches.clear();
    currentManche = 1;
    currentState = GameState.idle;
    tableId = rid;
   
    playBackgroundTrack1();

    if (multi) {
      isMultiplayer = true;
    }

    if (!isMultiplayer || (isMultiplayer && isHost)) {
      if (isMultiplayer && players.isNotEmpty) {
        for (var p in players) {
          p.hand.clear();
          p.tricksWon.clear();
        }
        if (players.length < pc) {
          for (int i = players.length; i < pc; i++) {
            players.add(Player(id: i, name: "IA $i", hand: [], isHuman: false));
          }
        }
      } else {
        players = List.generate(pc, (i) => Player(
          id: i, 
          name: i == myMultiplayerSide ? "MOI" : "IA $i", 
          hand: [], 
          isHuman: i == myMultiplayerSide
        ));
      }

      for (int i = 0; i < pc; i++) {
        _actualBots[i] = (i < players.length) ? !players[i].isHuman : true;
      }

      for (var p in players) { sessionScores[p.id] = 0.0; }
     
      selectedBid = null;
      lastBidName = "";
      takerId = null;
      calledKingSuit = null;
      isCalledSuitRevealed = false;
      revealedPartnerId = null;
      currentTrickData.clear();
     
      distributeAndStart(pc);
    } else {
      players = [];
      callMessage = "En attente de l'hôte...";
      notifyListeners();
    }
  }

  void resetGameForTimeout(int pc, String rid) {
    version++;
    sessionScores.clear();
    currentState = GameState.bidding;
    tableId = rid;

    for (int i = 0; i < pc; i++) {
      if (i >= players.length) {
        players.add(Player(id: i, name: "IA $i", hand: [], isHuman: false));
      }
      _actualBots[i] = !players[i].isHuman;
    }
    
    for (var p in players) { sessionScores[p.id] = 0.0; }
    selectedBid = null;
    lastBidName = "";
    takerId = null;
    calledKingSuit = null;
    isCalledSuitRevealed = false;
    revealedPartnerId = null;
    currentTrickData.clear();

    distributeAndStart(pc);
  }

  void distributeAndStart(int pc) {
    if (isMultiplayer && !isHost) return;
    if (_isDistributeLock) return;
    _isDistributeLock = true;

    version++;
    _resetCleaMemory(pc);
    List<CardModel> deck = generateFullTarotDeck();
    deck.shuffle();

    String packageRaw = deck.map((c) => c.id).join(',');
    currentDeckHash = sha256.convert(utf8.encode(packageRaw)).toString();

    int cSize = (pc == 5) ? 3 : 6;
    chien = deck.take(cSize).toList();
    for (var card in chien) {
      card.assetPath = _getAssetPath(card.suit, card.value);
    }
    deck = deck.skip(cSize).toList();
    int hSize = deck.length ~/ pc;
    for (int i = 0; i < pc; i++) {
      players[i].hand = deck.skip(i * hSize).take(hSize).toList();
      _sortHand(players[i].hand);
    }

    for (int i = 0; i < pc; i++) {
      var hand = players[i].hand;
      var atouts = hand.where((card) => card.suit == CardSuit.atout).toList();
      bool hasPetit = atouts.any((card) => card.value == "1");
      bool hasExcuse = hand.any((card) => card.suit == CardSuit.excuse);

      if (hasPetit && atouts.length == 1 && !hasExcuse) {
        callMessage = "Redistribution : ${players[i].name} a le Petit Sec !";
        cardsRevealed = true;
        _isDistributeLock = false;
        notifyListeners();
        
        if (onActionBroadcast != null) {
          onActionBroadcast!('PETIT_SEC_ANNOUNCED', {'player_id': i});
        }

        Future.delayed(const Duration(seconds: 5), () {
          cardsRevealed = false;
          distributeAndStart(pc);
        });
        return;
      }
    }
    
    currentState = GameState.bidding;

    if (isMultiplayer && isHost && onActionBroadcast != null) {
      onActionBroadcast!('INITIAL_DEAL', {
        'chien': chien.map((card) => card.id).toList(),
        'deck_hash': currentDeckHash,
        'hands': {for (var p in players) p.id.toString(): p.hand.map((card) => card.id).toList()}
      });
    }
    _startNewManche();
    _isDistributeLock = false;
    notifyListeners();
  }

  void handleAction(String type, Map<String, dynamic> data) {
    try {
      if (type == 'INITIAL_DEAL') {
        final allCards = generateFullTarotDeck();
        if (data.containsKey('hands')) {
          var handsMap = Map<String, dynamic>.from(data['hands'] as Map);
          String mySlotKey = myMultiplayerSide.toString();
          
          if (handsMap.containsKey(mySlotKey)) {
            List<dynamic> cardIds = handsMap[mySlotKey] as List;
            if (players.isEmpty) {
              players = List.generate(5, (i) => Player(id: i, name: i == myMultiplayerSide ? "MOI" : "J${i+1}", hand: [], isHuman: i == myMultiplayerSide));
            }
            
            players[myMultiplayerSide].hand = cardIds
                .map((id) => allCards.firstWhere((card) => card.id == int.parse(id.toString())))
                .toList();
            
            for (var card in players[myMultiplayerSide].hand) {
              card.assetPath = _getAssetPath(card.suit, card.value);
            }
            _sortHand(players[myMultiplayerSide].hand);
          }
        }
        
        if (data.containsKey('chien')) {
          List<dynamic> chienIds = data['chien'] as List;
          chien = chienIds.map((id) => allCards.firstWhere((card) => card.id == int.parse(id.toString()))).toList();
          for (var card in chien) {
            card.assetPath = _getAssetPath(card.suit, card.value);
          }
        }
        
        if (data.containsKey('deck_hash')) {
          currentDeckHash = data['deck_hash'].toString();
        }
        
        currentState = GameState.bidding;
        _startTurnSystem();
        notifyListeners();
        return;
      }

      if (type == 'SYNC_VIA_SQL' || type == 'SYNC_VAL_SQL') {
        if (data.containsKey('game_status')) {
          syncCommonData(data);
          if (data['hands'] != null) {
            Map<String, dynamic> handsMap = {};
            var rawHands = data['hands'];
           
            if (rawHands is String) {
              String cleanStr = rawHands.replaceAll('\\"', '"');
              if (cleanStr.startsWith('"') && cleanStr.endsWith('"')) {
                cleanStr = cleanStr.substring(1, cleanStr.length - 1);
              }
             
              String recherche = '"$myMultiplayerSide":[';
              if (cleanStr.contains(recherche)) {
                int debut = cleanStr.indexOf(recherche) + recherche.length;
                int fin = cleanStr.indexOf(']', debut);
                String listeCartes = cleanStr.substring(debut, fin);
                if (listeCartes.isNotEmpty) {
                  List<int> cardIds = listeCartes.split(',').map((e) => int.parse(e.trim())).toList();
                  handsMap[myMultiplayerSide.toString()] = cardIds;
                }
              }
            } else if (rawHands is Map) {
              handsMap = Map<String, dynamic>.from(rawHands);
            }

            if (handsMap.containsKey(myMultiplayerSide.toString())) {
              syncReceivedCards({'to': myMultiplayerSide, 'h': handsMap[myMultiplayerSide.toString()]});
            }
          }
        }
      }
      else if (type == 'HANDS_UPDATED') {
        if (currentState == GameState.playing || currentState == GameState.scoring) {
          return;
        }

        if (takerId != myMultiplayerSide || (currentState != GameState.dogRevealed && currentState != GameState.discarding)) {
          if (data.containsKey('hands')) {
            final allCards = generateFullTarotDeck();
            var handsMap = Map<String, dynamic>.from(data['hands'] as Map);
            String mySlotKey = myMultiplayerSide.toString();
            if (handsMap.containsKey(mySlotKey)) {
              List<dynamic> cardIds = handsMap[mySlotKey] as List;
              players[myMultiplayerSide].hand = cardIds
                  .map((id) => allCards.firstWhere((card) => card.id == int.parse(id.toString())))
                  .toList();
              for (var card in players[myMultiplayerSide].hand) {
                card.assetPath = _getAssetPath(card.suit, card.value);
              }
              _sortHand(players[myMultiplayerSide].hand);
            }
          }
        }
        currentState = GameState.discarding;
        cardsRevealed = true;
        notifyListeners();
      }
      else if (type == 'NEXT_MANCHE_TRIGGER') {
        if (data.containsKey('cumule_score') && data['cumule_score'] is Map) {
          var cumulMap = Map<String, dynamic>.from(data['cumule_score'] as Map);
          sessionScores.clear();
          cumulMap.forEach((k, v) {
            int pid = int.tryParse(k) ?? 0;
            sessionScores[pid] = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
          });
        }
        if (data.containsKey('dealer_index')) dealerIndex = int.tryParse(data['dealer_index'].toString());
        if (data.containsKey('current_player_index')) currentPlayerIndex = int.tryParse(data['current_player_index'].toString()) ?? 0;
        
        for (var p in players) {
          p.tricksWon.clear();
        }
        currentTakerScore = 0.0;
        currentDefenseScore = 0.0;
        lastBidsAnnounced.clear();
        revealedPartnerId = null;
        isCalledSuitRevealed = false;
        
        currentState = GameState.bidding;
        _startTurnSystem();
        notifyListeners();
      }
      else if (type == 'NEXT_BIDDER_INDEX') {
        if (data.containsKey('current_player_index')) {
          currentPlayerIndex = int.tryParse(data['current_player_index'].toString()) ?? currentPlayerIndex;
          hasClickedBid = false; 
          _startTurnSystem();
          notifyListeners();
        }
      }
      else if (type == 'TRICK_RESOLVED') {
        int w = int.tryParse(data['winner']?.toString() ?? '0') ?? 0;
        currentTrickData.clear();
        cardRotations.clear();
        leadSuit = null;
        currentPlayerIndex = w;
        if (data.containsKey('last_trick')) {
          final allCards = generateFullTarotDeck();
          List<dynamic> rawLt = data['last_trick'] as List;
          lastTrickCards = rawLt.map((item) {
            int cid = int.tryParse(item['id'].toString()) ?? 0;
            var c = allCards.firstWhere((card) => card.id == cid, orElse: () => allCards.first);
            c.assetPath = _getAssetPath(c.suit, c.value);
            return c;
          }).toList();
        }
        _isProcessing = false;
        _startTurnSystem();
        notifyListeners();
      }
      else if (type == 'STATE_CHANGED') {
        String st = data['status']?.toString() ?? '';
        if (st == 'CALLING') currentState = GameState.calling;
        else if (st == 'DISCARDING') {
          currentState = GameState.discarding;
          cardsRevealed = true;
        }
        else if (st == 'STARTED') {
          if (currentState != GameState.playing) {
            currentState = GameState.playing;
            cardsRevealed = false;
            _isProcessing = false;
            lastBidsAnnounced.clear();
            _startTurnSystem();
          }
        }
        notifyListeners();
      }
      else if (type == 'SUBMIT_DISCARD') {
        if (isHost) {
          int pid = int.tryParse(data['pid']?.toString() ?? '0') ?? 0;
          if (data.containsKey('hand')) {
            final allCards = generateFullTarotDeck();
            List<dynamic> handIds = data['hand'] as List;
            players[pid].hand = handIds
                .map((id) => allCards.firstWhere((card) => card.id == int.parse(id.toString())))
                .toList();
            for (var card in players[pid].hand) {
              card.assetPath = _getAssetPath(card.suit, card.value);
            }
            _sortHand(players[pid].hand);
          }
          _finishDiscard();
        }
      }
      else if (type == 'MAKE_BID') {
        int pid = int.tryParse(data['pid']?.toString() ?? '0') ?? 0;
        String bidStr = data['bid']?.toString() ?? "pass";
        receiveBid(bidStr, pid);
      }
      else if (type == 'SELECT_KING') {
        int suitIdx = int.tryParse(data['suit']?.toString() ?? '0') ?? 0;
        calledKingSuit = CardSuit.values[suitIdx];
        if (data.containsKey('takerId')) takerId = int.tryParse(data['takerId'].toString());
        if (data.containsKey('partnerId')) partnerId = int.tryParse(data['partner_id'].toString());
        
        isCalledSuitRevealed = false;
        revealedPartnerId = null;
        
        currentState = GameState.dogRevealed;
        cardsRevealed = true;
        _updateLiveScore();
        notifyListeners();
      }
      else if (type == 'PLAY_CARD') {
        int pid = int.tryParse(data['pid']?.toString() ?? '0') ?? 0;
        final all = generateFullTarotDeck();
        final card = all.firstWhere((c) => c.suit.toString() == data['cardSuit'] && c.value == data['cardValue'].toString());
        card.assetPath = _getAssetPath(card.suit, card.value);
        
        if (!currentTrickData.any((e) => e.containsKey(pid))) {
          cardRotations[pid] = (math.Random().nextDouble() - 0.5) * 0.2;
          players[pid].hand.removeWhere((c) => c.id == card.id);
          currentTrickData.add({pid: card});
          
          CardSuit? actualLead = leadSuit;
          if (actualLead == null) {
            for (var entry in currentTrickData) {
              var cInTrick = entry.values.first;
              if (cInTrick.suit != CardSuit.excuse) {
                actualLead = cInTrick.suit;
                break;
              }
            }
          }
          if (actualLead == null && card.suit != CardSuit.excuse) {
            leadSuit = card.suit;
          } else {
            leadSuit = actualLead;
          }

          if (calledKingSuit != null && card.suit == calledKingSuit && card.value == "R") {
            partnerId = pid;
            revealedPartnerId = pid;
            isCalledSuitRevealed = true;
            _updateLiveScore();
          }

          if (currentTrickData.length < players.length) {
            if (data.containsKey('nextPlayer')) {
              currentPlayerIndex = int.tryParse(data['nextPlayer'].toString()) ?? currentPlayerIndex;
            } else {
              currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
            }
          }

          if (isHost) {
            if (currentTrickData.length == players.length) {
              _stopTimer(); 
              _resolveTrick();
            } else {
              List<Map<String, dynamic>> trickJson = currentTrickData.map((entry) {
                return {'p': entry.keys.first, 'id': entry.values.first.id};
              }).toList();
              version++;
              
              bool isInactive = _inactiveAiPlayers.contains(currentPlayerIndex) || inactiveHumanPlayers.contains(currentPlayerIndex);
              int turnDuration = isInactive ? 10 : 20;

              _supabase.from('table_tarot_5').update({
                'current_trick': trickJson,
                'current_player_index': currentPlayerIndex,
                'partner_id': partnerId?.toString(),
                'version': version,
                'lead_suit': leadSuit?.toString(),
                'hand_$pid': players[pid].hand.map((card) => card.id).toList(),
                'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
                'turn_ends_at': DateTime.now().toUtc().add(Duration(seconds: turnDuration)).toIso8601String(),
              }).eq('table_id', tableId ?? '').then((_) {}).catchError((e) {});
            }
          }
        }
        _isProcessing = false;
        if (currentTrickData.length < players.length) {
          _startTurnSystem();
        }
        notifyListeners();
      }
    } catch (e) {
      _logSpy("ERROR", "Erreur critique handleAction: $e");
    }
  }

  dynamic _safeParseJson(dynamic incoming) {
    if (incoming == null) return null;
    if (incoming is List || incoming is Map) return incoming;
    if (incoming is String) {
      try { return jsonDecode(incoming); } catch (_) {}
    }
    return null;
  }

  void syncCommonData(Map<String, dynamic> data) {
    if (currentState == GameState.scoring && data['game_status'] != 'BIDDING') {
      return;
    }

    final int incomingVersion = int.tryParse(data['version']?.toString() ?? '0') ?? 0;
    if (incomingVersion > version) {
      version = incomingVersion;
    }

    final String sqlStatus = data['game_status']?.toString() ?? 'IDLE';
    final String sqlContrat = data['contrat']?.toString() ?? '';

    if (data['live_taker_score'] != null) {
      currentTakerScore = double.tryParse(data['live_taker_score'].toString()) ?? 0.0;
    }
    if (data['live_defense_score'] != null) {
      currentDefenseScore = double.tryParse(data['live_defense_score'].toString()) ?? 0.0;
    }

    if (data['players_tricks_won'] != null) {
      var rawTricks = _safeParseJson(data['players_tricks_won']);
      if (rawTricks is Map) {
        final allCards = generateFullTarotDeck();
        rawTricks.forEach((k, v) {
          int pid = int.tryParse(k) ?? 0;
          List<dynamic> cardIds = v as List? ?? [];
          if (pid < players.length) {
            players[pid].tricksWon = cardIds.map((id) {
              int cid = int.tryParse(id.toString()) ?? 0;
              var c = allCards.firstWhere((card) => card.id == cid, orElse: () => allCards.first);
              c.assetPath = _getAssetPath(c.suit, c.value);
              return c;
            }).toList();
          }
        });
      }
    }

    if (data['lead_suit'] != null && data['lead_suit'] != 'null' && data['lead_suit'] != '') {
      String suitStr = data['lead_suit'].toString();
      try {
        leadSuit = CardSuit.values.firstWhere((e) => e.toString() == suitStr || e.toString().split('.').last == suitStr);
      } catch (_) {
        leadSuit = null;
      }
    } else {
      if (currentTrickData.isEmpty) {
        leadSuit = null;
      }
    }

    if (data['cumule_score'] != null) {
      var rawCumul = _safeParseJson(data['cumule_score']);
      if (rawCumul is Map) {
        sessionScores.clear();
        rawCumul.forEach((k, v) {
          int pid = int.tryParse(k) ?? 0;
          sessionScores[pid] = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
        });
      }
    } else {
      sessionScores.clear();
    }

    if (data['history_manches'] != null) {
      try {
        final dynamic rawHist = _safeParseJson(data['history_manches']);
        if (rawHist is List) {
          historyManches = rawHist.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    if (data['last_trick'] != null) {
      final List<dynamic> rawLastTrick = _safeParseJson(data['last_trick']) as List? ?? [];
      if (rawLastTrick.isNotEmpty) {
        final allCards = generateFullTarotDeck();
        lastTrickCards = rawLastTrick.map((item) {
          int cardId = -1;
          if (item is Map) {
            cardId = int.tryParse(item['id']?.toString() ?? '-1') ?? -1;
            if (cardId == -1 && item.containsKey('suit') && item.containsKey('value')) {
              try {
                var found = allCards.firstWhere((c) => c.suit.toString() == item['suit'] && c.value == item['value'].toString());
                cardId = found.id;
              } catch (_) {}
            }
          } else {
            cardId = int.tryParse(item.toString()) ?? -1;
          }
          var c = allCards.firstWhere((card) => card.id == cardId, orElse: () => allCards.first);
          c.assetPath = _getAssetPath(c.suit, c.value);
          return c;
        }).toList();
      } else {
        lastTrickCards.clear();
      }
    }

    if (data['last_action_player'] != null && data['last_action_text'] != null) {
      int actionPid = int.tryParse(data['last_action_player'].toString()) ?? -1;
      String actionText = data['last_action_text'].toString();

      if (actionPid >= 0 && actionText.isNotEmpty) {
        lastBidsAnnounced[actionPid] = {
          'text': actionText,
          'time': DateTime.now(),
        };
      }
    }

    if (sqlStatus != 'WAITING' && sqlStatus != 'IDLE') {
      callMessage = "";
    }

    if (data['dealer_index'] != null) {
      dealerIndex = int.tryParse(data['dealer_index'].toString());
    }
    if (data['bid_taker_id'] != null && data['bid_taker_id'] != 'null') {
      takerId = int.tryParse(data['bid_taker_id'].toString());
    }
    if (data['partner_id'] != null && data['partner_id'] != 'null') {
      partnerId = int.tryParse(data['partner_id'].toString());
      if (partnerId != null) {
        revealedPartnerId = partnerId;
        isCalledSuitRevealed = true;
      }
    }

    if (data['called_king'] != null && data['called_king'] != 'null') {
      int? suitIdx = int.tryParse(data['called_king'].toString());
      if (suitIdx != null && suitIdx >= 0 && suitIdx < CardSuit.values.length) {
        calledKingSuit = CardSuit.values[suitIdx];
      }
    }

    if (data['chien'] != null) {
      final List<dynamic> rawChien = _safeParseJson(data['chien']) as List? ?? [];
      if (rawChien.isNotEmpty) {
        final allCards = generateFullTarotDeck();
        chien = rawChien.map((id) {
          int cardId = int.tryParse(id.toString()) ?? -1;
          var card = allCards.firstWhere((c) => c.id == cardId, orElse: () => allCards.first);
          card.assetPath = _getAssetPath(card.suit, card.value);
          return card;
        }).toList();
      }
    }

    if (sqlStatus == 'WAITING') {
      if (players.isNotEmpty && myMultiplayerSide < players.length && players[myMultiplayerSide].hand.isNotEmpty) {
        currentState = GameState.bidding;
      } else {
        currentState = GameState.idle;
      }
    }
    else if (sqlStatus == 'BIDDING') {
      if (currentState != GameState.playing && currentState != GameState.discarding && currentState != GameState.dogRevealed) {
        currentState = GameState.bidding;
        if (sqlContrat == '' || sqlContrat == 'null') {
          lastBidName = "";
          selectedBid = null;
        } else {
          lastBidName = sqlContrat;
          try {
            selectedBid = BidType.values.firstWhere((e) => e.toString().split('.').last.toUpperCase() == sqlContrat.toUpperCase());
          } catch (_) {
            selectedBid = null;
          }
        }
      }
    }
    else if (sqlStatus == 'DOG_REVEALED') {
      cardsRevealed = true;
      if (currentState != GameState.dogRevealed && currentState != GameState.discarding) {
        currentState = GameState.dogRevealed;
        if (takerId != null && players.isNotEmpty && takerId! < players.length) {
          _prepareDiscard();
        }
      }
    }
    else if (sqlStatus == 'DISCARDING') {
      currentState = GameState.discarding;
      cardsRevealed = true; 
    }
    else if (sqlStatus == 'CALLING') {
      if (currentState != GameState.scoring && currentState != GameState.dogRevealed && currentState != GameState.discarding && !_preparingDiscard) {
        currentState = GameState.calling;
      }
    }
    else if (sqlStatus == 'STARTED') {
      bool wasPlaying = (currentState == GameState.playing);
      currentState = GameState.playing;
      cardsRevealed = false; 
      lastBidsAnnounced.clear();

      playBackgroundTrack2();

      int oldPlayer = currentPlayerIndex;
      if (data['current_player_index'] != null) {
        currentPlayerIndex = int.tryParse(data['current_player_index'].toString()) ?? currentPlayerIndex;
      }

      if (!wasPlaying || oldPlayer != currentPlayerIndex) {
        _isProcessing = false;
        _startTurnSystem();
      }
    }
    else if (sqlStatus == 'SCORING') {
      currentState = GameState.scoring;
    }

    int pc = int.tryParse(data['player_count']?.toString() ?? '5') ?? 5;
    currentManche = int.tryParse(data['current_manche']?.toString() ?? '1') ?? 1;
    currentDeckHash = data['deck_hash']?.toString() ?? "";
   
    if (data['contrat'] != null && data['contrat'] != 'null' && data['contrat'] != '') {
      lastBidName = data['contrat'].toString();
      try {
        selectedBid = BidType.values.firstWhere((e) => e.toString().split('.').last.toUpperCase() == lastBidName.toUpperCase());
      } catch (_) {
        selectedBid = null;
      }
    }

    if (players.isEmpty || players.length != pc) {
      players = List.generate(pc, (i) {
        final String? sqlUid = data['player${i}_uid']?.toString();
        final String? sqlName = data['player${i}_name']?.toString();
        final String? sqlAvatar = data['player${i}_avatar']?.toString();

        return Player(
          id: i, 
          name: (i == myMultiplayerSide) ? "MOI" : (sqlName ?? "IA $i"), 
          hand: [], 
          isHuman: (sqlUid != 'IA_ID' && sqlUid != null),
          avatarUrl: (sqlAvatar != null && sqlAvatar.isNotEmpty) ? sqlAvatar : null
        );
      });
      for (var p in players) { sessionScores[p.id] = 0.0; }
    } else {
      for (int i = 0; i < players.length; i++) {
        final String? sqlUid = data['player${i}_uid']?.toString();
        final String? sqlName = data['player${i}_name']?.toString();
        final String? sqlAvatar = data['player${i}_avatar']?.toString(); 
        
        if (sqlUid != null && sqlUid != 'IA_ID') {
          players[i].isHuman = true;
          players[i].name = (i == myMultiplayerSide) ? "MOI" : (sqlName ?? "Humain $i");
        } else {
          players[i].isHuman = false;
          players[i].name = sqlName ?? "IA $i";
        }

        if (sqlAvatar != null && sqlAvatar.isNotEmpty) {
          players[i].avatarUrl = sqlAvatar; 
        } else {
          players[i].avatarUrl = null;
        }
        
        if (i == myMultiplayerSide) {
          players[i].isHuman = true;
          players[i].name = "MOI";
          if (sqlAvatar != null && sqlAvatar.isNotEmpty) {
            players[i].avatarUrl = sqlAvatar;
          }
        }
      }
    }

    for (int i = 0; i < pc; i++) {
      final uid = data['player${i}_uid']?.toString();
      if (i < _actualBots.length) {
        _actualBots[i] = (uid == 'IA_ID' || uid == null);
      }
    }

    if (sqlStatus == 'BIDDING' || sqlStatus == 'STARTED' || sqlStatus == 'DISCARDING' || sqlStatus == 'CALLING' || sqlStatus == 'DOG_REVEALED') {
      if (data['current_player_index'] != null && sqlStatus != 'STARTED') {
        currentPlayerIndex = int.tryParse(data['current_player_index'].toString()) ?? 0;
      }
    }

    if (data['inactive_humans'] != null) {
      var rawInactives = _safeParseJson(data['inactive_humans']);
      if (rawInactives is List) {
        inactiveHumanPlayers.clear();
        for (var idx in rawInactives) {
          int? pIdx = int.tryParse(idx.toString());
          if (pIdx != null) inactiveHumanPlayers.add(pIdx);
        }
      }
    }

    final allCards = generateFullTarotDeck();
    bool isShieldActive = (_preparingDiscard || (currentState == GameState.dogRevealed && takerId == myMultiplayerSide));
    
    for (int i = 0; i < 5; i++) {
      final String handKey = 'hand_$i';
      if (data[handKey] != null) {
        if (currentState == GameState.playing && i == myMultiplayerSide && players[i].hand.isNotEmpty) {
          continue;
        }
        if (currentState == GameState.bidding || isShieldActive) {
          if (i == myMultiplayerSide && players[i].hand.isNotEmpty) {
            continue; 
          }
        }

        final List<dynamic> hList = _safeParseJson(data[handKey]) as List? ?? [];
        if (i < players.length) {
          if (currentState == GameState.playing && hList.isEmpty) {
            continue; 
          }

          players[i].hand = hList
              .map((id) => allCards.firstWhere((c) => c.id == (int.tryParse(id.toString()) ?? -1), orElse: () => allCards.first))
              .toList();
          for (var card in players[i].hand) {
            card.assetPath = _getAssetPath(card.suit, card.value);
          }
          _sortHand(players[i].hand);
        }
      }
    }

    if (currentState != GameState.dogRevealed && currentState != GameState.discarding && !_preparingDiscard) {
      currentTrickData.clear();
      if (data['current_trick'] != null) {
        final parsedTrick = _safeParseJson(data['current_trick']);
        
        if (parsedTrick is List) {
          for (int i = 0; i < parsedTrick.length; i++) {
            var item = parsedTrick[i];
            if (item == null) continue;
            
            int cardId = -1;
            int computedPid = i;
            
            if (item is Map) {
              cardId = int.tryParse(item['id']?.toString() ?? '-1') ?? -1;
              if (item.containsKey('p')) {
                computedPid = int.tryParse(item['p']?.toString() ?? i.toString()) ?? i;
              }
            } else {
              cardId = int.tryParse(item.toString()) ?? -1;
            }
            
            if (cardId != -1) {
              try {
                var card = allCards.firstWhere((cardItem) => cardItem.id == cardId);
                card.assetPath = _getAssetPath(card.suit, card.value);
                currentTrickData.add({computedPid: card});
              } catch (_) {}
            }
          }
        } else if (parsedTrick is Map) {
          parsedTrick.forEach((key, val) {
            int pid = int.tryParse(key) ?? 0;
            int cardId = -1;
            
            if (val is Map) {
              cardId = int.tryParse(val['id']?.toString() ?? '-1') ?? -1;
            } else {
              cardId = int.tryParse(val.toString()) ?? -1;
            }
            
            if (cardId != -1) {
              try {
                var card = allCards.firstWhere((cardItem) => cardItem.id == cardId);
                card.assetPath = _getAssetPath(card.suit, card.value);
                currentTrickData.add({pid: card});
              } catch (_) {}
            }
          });
        }
        
        if (currentTrickData.length == players.length) {
          _stopTimer(); 
          _resolveTrick();
        }
      } else {
        cardRotations.clear();
      }
    }

    if (data['turn_ends_at'] != null && incomingVersion >= version) {
      String rawTime = data['turn_ends_at'].toString();
      if (!rawTime.endsWith('Z') && !rawTime.contains('+')) rawTime += 'Z';
      DateTime expiration = DateTime.parse(rawTime).toUtc();
      
      DateTime referenceNow = DateTime.now().toUtc();
      if (multiplayerManager != null) {
        try {
          referenceNow = multiplayerManager._correctedNow ?? referenceNow;
        } catch (_) {}
      }
      
      double secondesServeur = expiration.difference(referenceNow).inMilliseconds / 1000.0;

      if ((secondesServeur - remainingTime).abs() > 1.5) {
        remainingTime = secondesServeur > 0 ? secondesServeur : 0.0;
      }
    }
   
    notifyListeners();
  }

  void syncReceivedCards(Map<String, dynamic> data) {
    int targetSlot = int.tryParse(data['to']?.toString() ?? '-1') ?? -1;
   
    bool isShieldActive = (_preparingDiscard || ((currentState == GameState.dogRevealed || currentState == GameState.discarding) && takerId == myMultiplayerSide));
    if (isShieldActive && targetSlot == myMultiplayerSide) {
      return; 
    }

    myMultiplayerSide = targetSlot;
   
    final allCards = generateFullTarotDeck();
    final List<dynamic> hList = data['h'] as List? ?? [];
   
    if (players.isEmpty) {
      players = List.generate(5, (i) => Player(id: i, name: i == myMultiplayerSide ? "MOI" : "J${i+1}", hand: [], isHuman: i == myMultiplayerSide));
    }

    players[myMultiplayerSide].hand = hList.map((id) => allCards.firstWhere((c) => c.id == id)).toList();
    for (var card in players[myMultiplayerSide].hand) {
      card.assetPath = _getAssetPath(card.suit, card.value);
    }
   
    _sortHand(players[myMultiplayerSide].hand);
    if (!isMultiplayer) {
      currentState = GameState.bidding;
    }
    _startTurnSystem();
    notifyListeners();
  }

  void _startNewManche() {
    tricksCount = 0;
    currentTakerScore = 0.0;
    currentDefenseScore = 0.0;
    lastTrickCards = [];
    currentTrickData.clear();
    revealedPartnerId = null;
    isCalledSuitRevealed = false;
    lastBidsAnnounced.clear();

    for (var p in players) {
      p.tricksWon.clear();
    }
   
    hasClickedKing = false;
    hasClickedBid = false;
    selectedBid = null;
    calledKingSuit = null;
    takerId = null;
    partnerId = null;
    petitAuBoutWinner = null;
    lastBidName = "";

    currentState = GameState.bidding;
    dealerIndex ??= 0;
    currentPlayerIndex = (dealerIndex! + 1) % (players.isEmpty ? 1 : players.length);
    _startTurnSystem();
  }

  void _startTurnSystem() {
    if (currentState == GameState.scoring || players.isEmpty) return;
   
    if (currentState == GameState.playing) {
      bool isInactive = _inactiveAiPlayers.contains(currentPlayerIndex) || inactiveHumanPlayers.contains(currentPlayerIndex);
      remainingTime = isInactive ? 10.0 : 20.0;
    } else {
      remainingTime = 30.0;
    }

    _isProcessing = false;
    _stopTimer();
    _startTimer();

    bool isLastTrick = players.isNotEmpty && players[currentPlayerIndex].hand.length == 1;

    if (currentPlayerIndex < players.length) {
      if (_actualBots[currentPlayerIndex] || isLastTrick) {
        if (!isMultiplayer || isHost) {
          Future.delayed(const Duration(milliseconds: 1000), () => iaPlay()); 
        }
      }
    }
    notifyListeners();
  }

  void makeBid(BidType? b, {bool isManualAction = true}) {
    if (players.isEmpty) return;

    if (isManualAction && players[currentPlayerIndex].isHuman) {
      if (inactiveHumanPlayers.remove(currentPlayerIndex)) {
        if (isMultiplayer && isHost && tableId != null) {
          version++;
          _supabase.from('table_tarot_5').update({
            'version': version,
            'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          }).eq('table_id', tableId!).then((_) {}).catchError((e) {});
        }
      }
    } else {
      _inactiveAiPlayers.remove(currentPlayerIndex);
    }

    hasClickedBid = true;
    _stopTimer();

    if (isMultiplayer && !isHost) {
      _supabase.from('tarot_actions').insert({
        'table_id': tableId,
        'player_index': currentPlayerIndex,
        'action_type': 'MAKE_BID',
        'payload': {'bid': b.toString(), 'pid': currentPlayerIndex}
      }).then((_) {});
      
      _applyBidLogic(b, currentPlayerIndex);
      _finalizeBidTurn();
      return;
    }

    _applyBidLogic(b, currentPlayerIndex);

    if (onActionBroadcast != null) {
      onActionBroadcast!('MAKE_BID', {'bid': b.toString(), 'pid': currentPlayerIndex});
    }

    _finalizeBidTurn();
    notifyListeners();
  }

  void receiveBid(String bidStr, int pid) {
    BidType b = BidType.values.firstWhere(
      (e) => e.toString() == bidStr || e.toString().split('.').last == bidStr, 
      orElse: () => BidType.pass
    );
    _applyBidLogic(b, pid);
    _finalizeBidTurn();
    notifyListeners();
  }

  void _applyBidLogic(BidType? b, int pid) {
    _recordBidForAvatar(b, pid); 
    
    if (b != null && b != BidType.pass) {
      if (selectedBid == null || _bidRank(b) > _bidRank(selectedBid!)) {
        selectedBid = b;
        takerId = pid;
        lastBidName = b.toString().split('.').last.toUpperCase();
      }
    }

    if (isMultiplayer && isHost && tableId != null) {
      String bidStr = (b == null || b == BidType.pass) ? "PASSE" : b.toString().split('.').last.toUpperCase();
      if (bidStr == "GARDECONTRE") bidStr = "G. CONTRE";
      if (bidStr == "GARDESANS") bidStr = "G. SANS";

      version++;
      _supabase.from('table_tarot_5').update({
        'version': version,
        'contrat': lastBidName,
        'bid_taker_id': takerId?.toString(),
        'current_player_index': (currentPlayerIndex + 1) % players.length,
        'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
        'last_action_player': pid,
        'last_action_text': bidStr,
      }).eq('table_id', tableId!);
    }
  }

  void _finalizeBidTurn() {
    if (players.isEmpty) return;

    int nextIndex = (currentPlayerIndex + 1) % players.length;

    if (nextIndex == (dealerIndex! + 1) % players.length) {
      if (takerId == null || selectedBid == null || selectedBid == BidType.pass) {
        dealerIndex = (dealerIndex! + 1) % players.length;
        if (!isMultiplayer || isHost) {
          distributeAndStart(players.length);
        }
      } else {
        if (players.length == 5) {
          currentState = GameState.calling;
          currentPlayerIndex = takerId!;
          
          if (isMultiplayer && isHost && onActionBroadcast != null) {
            onActionBroadcast!('STATE_CHANGED', {'status': 'CALLING'});
          }
          _startTurnSystem();
        } else {
          _prepareDiscard();
        }
      }
    } else {
      currentPlayerIndex = nextIndex;
      hasClickedBid = false;
      
      if (isMultiplayer && isHost) {
        version++;
        _supabase.from('table_tarot_5').update({
          'version': version,
          'current_player_index': currentPlayerIndex,
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
        }).eq('table_id', tableId ?? '');

        if (onActionBroadcast != null) {
          onActionBroadcast!('NEXT_BIDDER_INDEX', {'current_player_index': currentPlayerIndex});
        }
      }
      
      _startTurnSystem();
    }
  }

  void selectCalledKing(CardSuit s) async {
    calledKingSuit = s;
    hasClickedKing = true;
    
    isCalledSuitRevealed = false;
    revealedPartnerId = null;

    try {
      int ownerId = players.firstWhere((p) => p.hand.any((c) => c.suit == s && c.value == "R")).id;
      partnerId = (ownerId == takerId) ? takerId : ownerId;
    } catch (e) {
      partnerId = null;
    }
   
    if (isMultiplayer && !isHost) {
      await _supabase.from('tarot_actions').insert({
        'table_id': tableId,
        'player_index': myMultiplayerSide,
        'action_type': 'SELECT_KING',
        'payload': {
          'suit': s.index, 
          'pid': myMultiplayerSide,
          'takerId': takerId,
          'partnerId': partnerId,
        }
      });
      currentState = GameState.dogRevealed;
      cardsRevealed = true;
      _prepareDiscard();
      notifyListeners();
      return;
    }

    if (onActionBroadcast != null) {
      onActionBroadcast!('SELECT_KING', {
        'suit': s.index, 
        'pid': currentPlayerIndex,
        'takerId': takerId,
        'partnerId': partnerId,
      });
    }
    
    if (isMultiplayer && isHost) {
      try {
        version++;
        await _supabase.from('table_tarot_5').update({
          'version': version,
          'called_king': s.index,
          'partner_id': partnerId?.toString(),
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          'game_status': 'DOG_REVEALED',
        }).eq('table_id', tableId ?? '');
      } catch (e) {}
    }

    _updateLiveScore();
    _prepareDiscard();
    notifyListeners();
  }

  Future<void> _prepareDiscard() async {
    if (_preparingDiscard) return;

    if (selectedBid == BidType.gardeSans || selectedBid == BidType.gardeContre) {
      cardsRevealed = false;
      _finishDiscard();
      return;
    }

    _preparingDiscard = true;
    currentState = GameState.dogRevealed;
    cardsRevealed = true;
    isCalledSuitRevealed = false;
    revealedPartnerId = null;
    
    currentEcartVisual.clear();
    currentTrickData.clear(); 
    
    if (isMultiplayer && isHost && onActionBroadcast != null) {
      onActionBroadcast!('CHIEN_REVEALED', {
        'chien': chien.map((card) => card.id).toList(),
        'taker_id': takerId
      });
    }
    
    notifyListeners(); 

    await Future.delayed(const Duration(seconds: 4));
    
    if (takerId != null && players.isNotEmpty && takerId! < players.length) {
      bool alreadyAdded = players[takerId!].hand.any((card) => chien.any((c) => c.id == card.id));
      if (!alreadyAdded) {
        players[takerId!].hand.addAll(chien);
      }
      _sortHand(players[takerId!].hand);
     
      if (isMultiplayer && isHost) {
        try {
          version++;
          Map<String, dynamic> updates = {
            'version': version,
            'hand_$takerId': players[takerId!].hand.map((card) => card.id).toList(), 
            'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
            'game_status': 'DISCARDING', 
            'current_player_index': takerId 
          };
          await _supabase.from('table_tarot_5').update(updates).eq('table_id', tableId ?? '');
        } catch (e) {}
        
        if (onActionBroadcast != null) {
          onActionBroadcast!('HANDS_UPDATED', {
            'hands': {for (var p in players) p.id.toString(): p.hand.map((card) => card.id).toList()}
          });
        }
      }

      currentState = GameState.discarding;
      currentPlayerIndex = takerId!; 
      _preparingDiscard = false;
      _stopTimer(); 
      currentEcartVisual.clear(); 
      notifyListeners(); 
     
      if (_actualBots[takerId!]) {
        _iaSmartDiscard();
      }
    } else {
      _preparingDiscard = false;
      currentState = GameState.playing;
      playBackgroundTrack2();
      notifyListeners();
    }
  }

  void handleDiscardClick(CardModel c) {
    if (takerId == null || currentState != GameState.discarding || _isProcessing) return;
    if (isMultiplayer && takerId != myMultiplayerSide) return;
   
    _playCardSound();

    if (currentEcartVisual.contains(c)) {
      currentEcartVisual.remove(c);
      players[takerId!].hand.add(c);
    } else if (currentEcartVisual.length < (players.length == 5 ? 3 : 6)) {
      if (c.value == "R" || c.isBout) return;
      players[takerId!].hand.remove(c);
      currentEcartVisual.add(c);
    }
    _sortHand(players[takerId!].hand);
    notifyListeners();
  }

  void validateDiscard() {
    if (isEcartValid) {
      _finishDiscard();
    }
  }
 
  bool get isEcartValid => currentEcartVisual.length == (players.length == 5 ? 3 : 6);

  void _finishDiscard() async {
    _isProcessing = true;
    callMessage = "Validation de l'écart...";
    notifyListeners();

    if (isMultiplayer && isHost && tableId != null && takerId != null) {
      try {
        double chienPoints = currentEcartVisual.fold(0.0, (sum, c) => sum + c.points);
        final ecartPayload = currentEcartVisual.map((e) => {
          'id': e.id,
          'pts': e.points,
        }).toList();

        await _supabase.from('game_tricks').insert({
          'table_id': tableId,
          'manche_index': currentManche,
          'trick_number': 0, 
          'winner_id': takerId,
          'cards_played': ecartPayload,
          'trick_points': chienPoints,
        });
      } catch (e) {
        _logSpy("CHIEN_CERTIFICATE_ERR", "Erreur chien : $e");
      }
    }

    if (isMultiplayer && !isHost) {
      try {
        await _supabase.from('tarot_actions').insert({
          'table_id': tableId,
          'player_index': myMultiplayerSide,
          'action_type': 'SUBMIT_DISCARD',
          'payload': {
            'pid': myMultiplayerSide,
            'hand': players[myMultiplayerSide].hand.map((card) => card.id).toList()
          }
        });
      } catch (e) {
        _isProcessing = false;
        callMessage = "";
        notifyListeners();
      }
      return; 
    }

    currentState = GameState.playing;
    playBackgroundTrack2();
    cardsRevealed = false; 
    lastBidsAnnounced.clear();
    currentPlayerIndex = (dealerIndex! + 1) % (players.isEmpty ? 1 : players.length);
   
    if (isMultiplayer && isHost) {
      try {
        version++;

        Map<String, dynamic> tricksWonMap = {};
        for (var p in players) {
          tricksWonMap[p.id.toString()] = p.tricksWon.map((c) => c.id).toList();
        }

        await _supabase.from('table_tarot_5').update({
          'version': version,
          'game_status': 'STARTED',
          'current_player_index': currentPlayerIndex,
          'hand_$takerId': players[takerId!].hand.map((card) => card.id).toList(), 
          'players_tricks_won': tricksWonMap,
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          'contrat': lastBidName, 
        }).eq('table_id', tableId ?? '');
      } catch (e) {}
      
      if (onActionBroadcast != null) {
        onActionBroadcast!('STATE_CHANGED', {'status': 'STARTED'});
      }
    }

    _isProcessing = false;
    callMessage = "";
    _updateLiveScore();
    _startTurnSystem();
    notifyListeners();
  }

  bool isCardPlayable(CardModel c) {
    if (currentState == GameState.playing && currentPlayerIndex == myMultiplayerSide && !_isProcessing) {
      List<CardModel> validCards = TarotAI.getStrictlyValidPlayableCards(
        players[myMultiplayerSide].hand, 
        leadSuit, 
        currentTrickData,
        calledKing: tricksCount == 0 ? calledKingSuit : null,
      );
      return validCards.any((card) => card.id == c.id);
    }
    return true; 
  }

  Future<void> playCard(int pid, CardModel card, {bool isManualAction = true}) async {
    if (players.isEmpty || pid >= players.length || players[pid].hand.isEmpty) {
      return;
    }

    if (pid != currentPlayerIndex || _isProcessing) {
      return;
    }
    if (currentTrickData.any((e) => e.containsKey(pid))) {
      return;
    }
   
    // 🔒 SÉCURITÉ ABSOLUE : Si c'est un humain, on vérifie strictement la règle officielle (ex: obligation de monter à l'atout)
    if (players[pid].isHuman && !isCardPlayable(card)) {
      _logSpy("ILLEGAL_MOVE", "Tentative de jouer une carte interdite bloquée : ${card.value} de ${card.suit}");
      return; // On annule l'action, la carte ne peut pas être jouée
    }

    _isProcessing = true;
    _stopTimer();
    _playCardSound();

    if (isManualAction && players[pid].isHuman) {
      if (inactiveHumanPlayers.remove(pid)) {
        if (isMultiplayer && isHost && tableId != null) {
          version++;
          _supabase.from('table_tarot_5').update({
            'version': version,
            'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          }).eq('table_id', tableId!).then((_) {}).catchError((e) {});
        }
      }
    } else {
      _inactiveAiPlayers.remove(pid);
    }

    if (calledKingSuit != null && card.suit == calledKingSuit && card.value == "R") {
      partnerId = pid;
      revealedPartnerId = pid;
      isCalledSuitRevealed = true;
      _updateLiveScore();
    }

    cardRotations[pid] = (math.Random().nextDouble() - 0.5) * 0.2;
    players[pid].hand.removeWhere((c) => c.id == card.id);
    currentTrickData.add({pid: card});
    
    CardSuit? actualLead = leadSuit;
    if (actualLead == null) {
      for (var entry in currentTrickData) {
        var cInTrick = entry.values.first;
        if (cInTrick.suit != CardSuit.excuse) {
          actualLead = cInTrick.suit;
          break;
        }
      }
    }
    if (actualLead == null && card.suit != CardSuit.excuse) {
      leadSuit = card.suit;
    } else {
      leadSuit = actualLead;
    }

    // MISE À JOUR ATOMIQUE IMMÉDIATE POUR ÉVITER LE DÉCALAGE UI
    int nextPlayer = currentPlayerIndex;
    if (currentTrickData.length < players.length) {
      nextPlayer = (currentPlayerIndex + 1) % players.length;
      currentPlayerIndex = nextPlayer;
    }

    notifyListeners();

    bool isInactive = _inactiveAiPlayers.contains(currentPlayerIndex) || inactiveHumanPlayers.contains(currentPlayerIndex);
    int turnDuration = isInactive ? 10 : 20;

    if (isMultiplayer && !isHost && tableId != null) {
      try {
        List<Map<String, dynamic>> trickJson = currentTrickData.map((entry) {
          return {'p': entry.keys.first, 'id': entry.values.first.id};
        }).toList();

        version++;

        await _supabase.from('table_tarot_5').update({
          'current_trick': trickJson,
          'current_player_index': currentPlayerIndex,
          'partner_id': partnerId?.toString(),
          'version': version,
          'lead_suit': leadSuit?.toString(),
          'hand_$pid': players[pid].hand.map((c) => c.id).toList(),
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          'turn_ends_at': DateTime.now().toUtc().add(Duration(seconds: turnDuration)).toIso8601String(),
        }).eq('table_id', tableId!);

        await _supabase.from('tarot_actions').insert({
          'table_id': tableId,
          'player_index': pid,
          'action_type': 'PLAY_CARD',
          'payload': {
            'pid': pid,
            'cardSuit': card.suit.toString(),
            'cardValue': card.value,
            'nextPlayer': currentPlayerIndex
          }
        });
      } catch (e) {}
      
      _isProcessing = false;
      if (currentTrickData.length < players.length) {
        _startTurnSystem();
      }
      return; 
    }

    if (isMultiplayer && isHost && tableId != null) {
      try {
        List<Map<String, dynamic>> trickJson = currentTrickData.map((entry) {
          return {'p': entry.keys.first, 'id': entry.values.first.id};
        }).toList();

        version++;

        await _supabase.from('table_tarot_5').update({
          'current_trick': trickJson,
          'current_player_index': currentPlayerIndex,
          'partner_id': partnerId?.toString(),
          'version': version,
          'lead_suit': leadSuit?.toString(),
          'hand_$pid': players[pid].hand.map((c) => c.id).toList(),
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          'turn_ends_at': DateTime.now().toUtc().add(Duration(seconds: turnDuration)).toIso8601String(),
        }).eq('table_id', tableId!);
      } catch (e) {}
    }

    if (onActionBroadcast != null) {
      onActionBroadcast!('PLAY_CARD', {
        'pid': pid,
        'cardSuit': card.suit.toString(),
        'cardValue': card.value,
        'nextPlayer': currentPlayerIndex
      });
    }

    if (currentTrickData.length == players.length) {
      _stopTimer(); 
      await Future.delayed(const Duration(milliseconds: 1200));
      await _resolveTrick();
      if (players.every((p) => p.hand.isEmpty)) {
        return;
      }
    } else {
      _isProcessing = false;
      _startTurnSystem();
    }
    notifyListeners();
  }

  Future<void> _resolveTrick() async {
    if (players.isEmpty) return;

    _isProcessing = true;
    _stopTimer();

    if (leadSuit != null) {
      TarotAI.analyzeTrick(currentTrickData, leadSuit!);
    }
   
    int winner = _determineWinner();
    lastTrickCards = currentTrickData.map((e) => e.values.first).toList();
    
    double trickPoints = lastTrickCards.fold(0.0, (sum, c) => sum + c.points);

    bool isLast = (players.isNotEmpty && players[0].hand.isEmpty);

    if (isLast) {
      players[winner].tricksWon.addAll(lastTrickCards);
    } else {
      players[winner].tricksWon.addAll(lastTrickCards.where((c) => c.suit != CardSuit.excuse));
      for (var e in currentTrickData) {
        if (e.values.first.suit == CardSuit.excuse) {
          players[e.keys.first].tricksWon.add(e.values.first);
        }
      }
    }
   
    if (isLast && lastTrickCards.any((c) => c.suit == CardSuit.atout && c.value == "1")) {
      petitAuBoutWinner = winner;
    }

    tricksCount++;

    // 🛑 VÉRIFICATION PRÉALABLE : Si c'est le tout dernier pli de la 3ème manche, 
    // on calcule les scores et on bloque net AVANT d'insérer dans game_tricks pour éviter les doublons/erreurs SQL.
    if (isLast && currentManche >= 3) {
      _stopTimer();
      _updateLiveScore(); 
      _calculateFinalScores();

      await _finalizeTokenDistribution();
      totalGamesCompleted++;

      if (navigatorKey.currentContext != null) {
        BuildContext ctx = navigatorKey.currentContext!;
        await PermissionsService.checkAndSuggestNotificationsAfterFirstGame(ctx, totalGamesCompleted);
        await PermissionsService.checkAndSuggestSocialTarot(ctx, totalGamesCompleted);
      }

      notifyListeners();
      await Future.delayed(const Duration(seconds: 3));

      currentTrickData.clear();
      cardRotations.clear();

      currentState = GameState.scoring; // Fige définitivement l'état sur l'écran de score final
      notifyListeners();

      if (isMultiplayer && isHost) {
        Map<String, int> finalCumul = {};
        sessionScores.forEach((k, v) => finalCumul[k.toString()] = v.toInt());

        version++;
        await _supabase.from('table_tarot_5').update({
          'version': version,
          'game_status': 'SCORING',
          'cumule_score': finalCumul,
          'history_manches': jsonEncode(historyManches),
          'inactive_humans': jsonEncode([]),
          'lead_suit': null,
        }).eq('table_id', tableId ?? '');
      }
      return; // INTERDICTION ABSOLUE DE CONTINUER VERS UNE 4E MANCHE OU UN CYCLE AUTOMATIQUE !
    }

    if (isMultiplayer && isHost && tableId != null) {
      try {
        final trickPayload = currentTrickData.map((e) => {
          'p': e.keys.first,
          'id': e.values.first.id,
          'pts': e.values.first.points,
        }).toList();

        await _supabase.from('game_tricks').insert({
          'table_id': tableId,
          'manche_index': currentManche,
          'trick_number': tricksCount,
          'winner_id': winner,
          'cards_played': trickPayload,
          'trick_points': trickPoints,
        });
      } catch (e) {}
    }

    _updateLiveScore();

    currentPlayerIndex = winner; 
    leadSuit = null;

    bool isInactive = _inactiveAiPlayers.contains(currentPlayerIndex) || inactiveHumanPlayers.contains(currentPlayerIndex);
    int turnDuration = isInactive ? 10 : 20;

    if (isMultiplayer && isHost && tableId != null) {
      try {
        version++;
        List<Map<String, dynamic>> lastTrickJson = lastTrickCards.map((c) => {
          'id': c.id,
          'suit': c.suit.toString(),
          'value': c.value
        }).toList();

        Map<String, dynamic> tricksWonMap = {};
        for (var p in players) {
          tricksWonMap[p.id.toString()] = p.tricksWon.map((c) => c.id).toList();
        }

        await _supabase.from('table_tarot_5').update({
          'current_trick': {},
          'last_trick': lastTrickJson,
          'current_player_index': currentPlayerIndex,
          'partner_id': partnerId?.toString(),
          'live_taker_score': currentTakerScore,
          'live_defense_score': currentDefenseScore,
          'players_tricks_won': tricksWonMap,
          'version': version,
          'lead_suit': null,
          'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
          'turn_ends_at': DateTime.now().toUtc().add(Duration(seconds: turnDuration)).toIso8601String(),
        }).eq('table_id', tableId!);
      } catch (e) {}
    }

    if (isMultiplayer && isHost && onActionBroadcast != null) {
      onActionBroadcast!('TRICK_RESOLVED', {
        'winner': winner,
        'last_trick': lastTrickCards.map((c) => {'id': c.id, 'suit': c.suit.toString(), 'value': c.value}).toList()
      });
    }

    if (isLast) {
      _stopTimer();

      _updateLiveScore(); 
      _calculateFinalScores();

      notifyListeners();
      await Future.delayed(const Duration(seconds: 3));

      currentTrickData.clear();
      cardRotations.clear();

      currentState = GameState.scoring;
      notifyListeners();

      if (isMultiplayer && isHost) {
        Map<String, int> finalCumul = {};
        sessionScores.forEach((k, v) => finalCumul[k.toString()] = v.toInt());

        version++;
        await _supabase.from('table_tarot_5').update({
          'version': version,
          'game_status': 'SCORING',
          'cumule_score': finalCumul,
          'history_manches': jsonEncode(historyManches),
          'inactive_humans': jsonEncode([]),
          'lead_suit': null,
        }).eq('table_id', tableId ?? '');
      }

    } else {
      currentTrickData.clear();
      cardRotations.clear();
      _isProcessing = false;
      _startTurnSystem();
      notifyListeners();
    }
  }

  Future<void> _finalizeTokenDistribution() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null || sessionScores.isEmpty) return;

      int mySlot = myMultiplayerSide;
      int playerCount = players.length;
      int entryFee = currentTableEntryFee;

      List<MapEntry<int, double>> sortedScores = sessionScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      List<MapEntry<int, double>> positivePlayers = sortedScores.where((e) => e.value > 0).toList();
      int myReward = 0;

      if (positivePlayers.isNotEmpty) {
        int firstPlaceSlot = positivePlayers[0].key;

        if (playerCount == 5) {
          int uniquePrize = 400;
          int firstPrize = 300;
          int secondPrize = 100;

          if (entryFee == 500) {
            uniquePrize = 1000;
            firstPrize = 750;
            secondPrize = 250;
          } else if (entryFee == 1000) {
            uniquePrize = 2000;
            firstPrize = 1500;
            secondPrize = 500;
          } else if (entryFee == 2000) {
            uniquePrize = 2500;
            firstPrize = 1750;
            secondPrize = 750;
          }

          if (positivePlayers.length == 1) {
            if (mySlot == firstPlaceSlot) myReward = uniquePrize;
          } else {
            int secondPlaceSlot = positivePlayers[1].key;
            if (mySlot == firstPlaceSlot) {
              myReward = firstPrize;
            } else if (mySlot == secondPlaceSlot) {
              myReward = secondPrize;
            }
          }
        } else {
          int uniquePrize = (entryFee == 2000) ? 2500 : (entryFee * 2);
          if (mySlot == firstPlaceSlot) myReward = uniquePrize;
        }
      }

      if (myReward > 0) {
        await TokenManager.creditUser(user.id, myReward);
        notifyListeners();
      }
    } catch (e) {
      _logSpy("JETONS_ERR", "Erreur jetons: $e");
    }
  }

  int _determineWinner() {
    if (currentTrickData.isEmpty) return 0;
    var trumps = currentTrickData.where((e) => e.values.first.suit == CardSuit.atout).toList();
    if (trumps.isNotEmpty) {
      trumps.sort((a, b) => b.values.first.power.compareTo(a.values.first.power));
      return trumps.first.keys.first;
    }
    var colorCards = currentTrickData.where((e) => e.values.first.suit == leadSuit).toList();
    if (colorCards.isEmpty) return currentTrickData.first.keys.first;
    colorCards.sort((a, b) => b.values.first.power.compareTo(a.values.first.power));
    return colorCards.first.keys.first;
  }

  void _calculateFinalScores() {
    if (takerId == null || players.isEmpty) return;
   
    if (isMultiplayer && !isHost) return;

    var finalGains = ScoringLogic.computeFinalGains(
      players: players,
      takerId: takerId!,
      partnerId: partnerId,
      selectedBid: selectedBid,
      petitAuBoutWinner: petitAuBoutWinner,
      poignees: poigneesAnnoncees,
      ecartCards: currentEcartVisual,
    );
   
    finalGains.forEach((pid, gain) {
      sessionScores[pid] = (sessionScores[pid] ?? 0.0) + gain;
    });

    final mancheDetail = {
      'manche': currentManche,
      'taker_id': takerId,
      'contrat': lastBidName,
      'gains': finalGains.map((k, v) => MapEntry(k.toString(), v)),
      'poignees': poigneesAnnoncees.map((k, v) => MapEntry(k.toString(), v)),
      'timestamp': DateTime.now().toIso8601String(),
    };
    historyManches.add(mancheDetail);
   
    RemoteLogger.logEnd(tableId ?? "SANS_TABLE", true);
  }

  /// Clôture définitive de la partie (fin des 3 manches) et retour propre à l'accueil
  Future<void> finishGameAndExit() async {
    _stopTimer();
    _autoNextGameTimer?.cancel();
    _isProcessing = false;

    if (isMultiplayer && tableId != null && isHost) {
      try {
        await _supabase.from('table_tarot_5').update({
          'game_status': 'FINISHED',
          'inactive_humans': jsonEncode([]),
        }).eq('table_id', tableId!);
      } catch (e) {
        _logSpy("FINISH_GAME_ERR", "Erreur clôture table : $e");
      }
    }

    fullResetForExit();
  }

  void nextManche() async {
    if (players.isEmpty || _isNextMancheLock) return;

    // Si on clique sur le bouton alors qu'on est déjà à la 3e manche (ou plus), on quitte vers l'accueil
    if (currentManche >= 3) {
      await finishGameAndExit();
      return;
    }

    _isNextMancheLock = true;

    try {
      _autoNextGameTimer?.cancel();
      _stopTimer();
      _isProcessing = false;

      tricksCount = 0;

      selectedBid = null;
      calledKingSuit = null;
      isCalledSuitRevealed = false;
      revealedPartnerId = null;
      takerId = null;
      partnerId = null;
      petitAuBoutWinner = null;
      lastBidName = "";
      leadSuit = null;
      hasClickedKing = false;
      hasClickedBid = false;

      currentTakerScore = 0.0;
      currentDefenseScore = 0.0;
      currentTrickData.clear();
      lastTrickCards = [];
      cardRotations.clear();
      lastBidsAnnounced.clear();
      currentEcartVisual.clear();

      _inactiveAiPlayers.clear();
      inactiveHumanPlayers.clear();

      for (var p in players) {
        p.tricksWon.clear();
        p.hand.clear();
      }

      currentManche++;
      dealerIndex = (dealerIndex! + 1) % players.length;

      if (isMultiplayer && isHost) {
        Map<String, int> nouveauCumul = {};
        sessionScores.forEach((key, value) {
          nouveauCumul[key.toString()] = value.toInt();
        });

        List<CardModel> deck = generateFullTarotDeck();
        deck.shuffle();

        String packageRaw = deck.map((c) => c.id).join(',');
        currentDeckHash = sha256.convert(utf8.encode(packageRaw)).toString();

        int cSize = 3;
        chien = deck.take(cSize).toList();
        for (var card in chien) {
          card.assetPath = _getAssetPath(card.suit, card.value);
        }
        deck = deck.skip(cSize).toList();
        int hSize = deck.length ~/ players.length;
        for (int i = 0; i < players.length; i++) {
          players[i].hand = deck.skip(i * hSize).take(hSize).toList();
          _sortHand(players[i].hand);
        }

        currentState = GameState.bidding;
        currentPlayerIndex = (dealerIndex! + 1) % players.length;

        version++;
        await _supabase.from('table_tarot_5').update({
          'version': version,
          'game_status': 'BIDDING',
          'current_manche': currentManche,
          'dealer_index': dealerIndex,
          'current_player_index': currentPlayerIndex,
          'contrat': null,
          'bid_taker_id': null,
          'partner_id': null,
          'called_king': null,
          'live_taker_score': 0,
          'live_defense_score': 0,
          'players_tricks_won': {'0': [], '1': [], '2': [], '3': [], '4': []},
          'chien': chien.map((card) => card.id).toList(),
          'current_trick': [],
          'last_trick': [],
          'lead_suit': null,
          'deck_hash': currentDeckHash,
          'cumule_score': nouveauCumul,
          'history_manches': jsonEncode(historyManches),
          'hand_0': players[0].hand.map((card) => card.id).toList(),
          'hand_1': players[1].hand.map((card) => card.id).toList(),
          'hand_2': players[2].hand.map((card) => card.id).toList(),
          'hand_3': players[3].hand.map((card) => card.id).toList(),
          'hand_4': players[4].hand.map((card) => card.id).toList(),
          'inactive_humans': jsonEncode([]),
        }).eq('table_id', tableId ?? '');

        if (onActionBroadcast != null) {
          onActionBroadcast!('NEXT_MANCHE_TRIGGER', {
            'cumule_score': nouveauCumul,
            'dealer_index': dealerIndex,
            'current_player_index': currentPlayerIndex
          });
        }

        _startTurnSystem();
        notifyListeners();
        return;
      }

      if (isMultiplayer && !isHost) {
        callMessage = "Attente de l'hôte...";
        notifyListeners();
        return;
      }

      distributeAndStart(players.length);
    } finally {
      _isNextMancheLock = false;
    }
  }

  void annoncerPoignee() {
    if (players.isEmpty) return;
    showPoigneeButton = false;
    int count = players[myMultiplayerSide].hand.where((card) => card.suit == CardSuit.atout || card.suit == CardSuit.excuse).length;
    _autoAnnouncePoignee(myMultiplayerSide, count);
    notifyListeners();
  }

  void _startTimer() {
    _stopTimer();
    
    _turnTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (players.isEmpty || currentState == GameState.idle || currentState == GameState.scoring) {
        _stopTimer();
        return;
      }

      if (currentState == GameState.discarding || 
          currentState == GameState.dogRevealed || 
          currentState == GameState.calling) {
        _stopTimer();
        return;
      }

      if (currentPlayerIndex < players.length && players[currentPlayerIndex].isHuman) {
        if (remainingTime <= 5.0 && !inactiveHumanPlayers.contains(currentPlayerIndex)) {
          inactiveHumanPlayers.add(currentPlayerIndex);
          
          if (isMultiplayer && isHost && tableId != null) {
            version++;
            _supabase.from('table_tarot_5').update({
              'version': version,
              'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
            }).eq('table_id', tableId!).then((_) {}).catchError((e) {});
          }

          if (isHost || !isMultiplayer) {
            Future.delayed(const Duration(milliseconds: 200), () {
              if (currentState != GameState.idle && currentState != GameState.scoring) {
                iaPlay();
              }
            });
          }
        }
      }

      if (remainingTime > 0.1) {
        remainingTime -= 0.1;
      } else {
        _stopTimer();

        if (currentPlayerIndex < players.length) {
          if (players[currentPlayerIndex].isHuman) {
            inactiveHumanPlayers.add(currentPlayerIndex);
            if (isMultiplayer && isHost && tableId != null) {
              version++;
              _supabase.from('table_tarot_5').update({
                'version': version,
                'inactive_humans': jsonEncode(inactiveHumanPlayers.toList()),
              }).eq('table_id', tableId!).then((_) {}).catchError((e) {});
            }
          } else {
            _inactiveAiPlayers.add(currentPlayerIndex);
          }

          if (isMultiplayer && !isHost) return;

          Future.delayed(const Duration(seconds: 1), () {
            if (currentState != GameState.idle && currentState != GameState.scoring && currentState != GameState.discarding) {
              iaPlay();
            }
          });
        }
        return;
      }
      notifyListeners();
    });
  }

  void startTimerForceHost() {
    _startTurnSystem();
  }

  void _stopTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
  }

  void fullResetForExit() {
    _stopTimer();
    stopBackgroundMusic();
    _autoNextGameTimer?.cancel();
    currentState = GameState.idle;
    tableId = null;
    players.clear();
    currentTrickData.clear();
    lastTrickCards.clear();
    currentEcartVisual.clear();
    sessionScores.clear();
    historyManches.clear();
    lastBidsAnnounced.clear();
    _inactiveAiPlayers.clear();
    inactiveHumanPlayers.clear();
    leadSuit = null;
    notifyListeners();
  }

  List<CardModel> generateFullTarotDeck() {
    List<CardModel> d = [];
    int id = 0;
    for (var s in CardSuit.values) {
      if (s == CardSuit.atout) {
        for (int i = 1; i <= 21; i++) {
          d.add(CardModel(
            id: id++, 
            suit: s, 
            value: i.toString(), 
            power: i, 
            points: (i == 1 || i == 21) ? 4.5 : 0.5, 
            isBout: (i == 1 || i == 21),
            assetPath: _getAssetPath(s, i.toString())
          ));
        }
      } else if (s == CardSuit.excuse) {
        d.add(CardModel(
          id: id++, 
          suit: s, 
          value: "Excuse", 
          power: 0, 
          points: 4.5, 
          isBout: true,
          assetPath: _getAssetPath(s, "Excuse")
        ));
      } else if (s != CardSuit.atout && s != CardSuit.excuse) {
        for (int i = 1; i <= 10; i++) {
          d.add(CardModel(
            id: id++, 
            suit: s, 
            value: i.toString(), 
            power: i, 
            points: 0.5,
            assetPath: _getAssetPath(s, i.toString())
          ));
        }
        for (var v in ["V", "C", "D", "R"]) {
          d.add(CardModel(
            id: id++, 
            suit: s, 
            value: v, 
            power: v == "V" ? 11 : v == "C" ? 12 : v == "D" ? 13 : 14, 
            points: v == "V" ? 1.5 : v == "C" ? 2.5 : v == "D" ? 3.5 : 4.5,
            assetPath: _getAssetPath(s, v)
          ));
        }
      }
    }
    d.shuffle(math.Random(1337));
    return d;
  }

  @override
  void dispose() {
    _playerCountController.close();
    _timeController.close();
    _stopTimer();
    _autoNextGameTimer?.cancel();
    super.dispose();
  }

  List<CardModel> get cardsOnTable => currentTrickData.map((e) => e.values.first).toList();
  String? get bidTakerId => takerId?.toString();
 
  String get currentContractName {
    if (selectedBid == null || currentState == GameState.bidding) {
      return "";
    }
    String name = selectedBid.toString().split('.').last.toUpperCase();
    return name == "NULL" || name == "" ? "" : name;
  }

  Future<void> forceTimeoutAction() async {
    if (players.isEmpty || currentState == GameState.idle || currentState == GameState.scoring) return;

    _isProcessing = false;

    if (currentState == GameState.bidding) {
      makeBid(_iaSmartBidding(), isManualAction: false);
    } else if (currentState == GameState.calling) {
      _iaPlayCall();
    } else if (currentState == GameState.discarding) {
      _iaSmartDiscard();
    } else if (currentState == GameState.playing) {
      _checkPoignee(currentPlayerIndex);
      var h = players[currentPlayerIndex].hand;
      if (h.isEmpty) return;
      List<CardModel> p = TarotAI.getStrictlyValidPlayableCards(
        h, 
        leadSuit, 
        currentTrickData,
        calledKing: tricksCount == 0 ? calledKingSuit : null,
      );
      CardModel chosenCard = p.isNotEmpty ? _getBestAICard(p) : h.first;
      await playCard(currentPlayerIndex, chosenCard, isManualAction: false);
    }
  }

  Future<void> iaPlay() async {
    if (players.isEmpty || currentState == GameState.idle || currentState == GameState.scoring) return;
    await forceTimeoutAction();
  }
}
