// --- SDK DART ---
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'logic.dart';
import 'models.dart';

class MultiplayerManager {
  final TarotGameLogic gameLogic;
  RealtimeChannel? _channel;
  RealtimeChannel? _actionChannel; 
  Timer? _syncTimer;
  Timer? _recoveryTimer;
  
  bool isHost = false;
  String deviceLabel = "INIT";
  String currentTable = "";
  Map<String, dynamic> currentTableData = {};
  DateTime? forcedExpiration;
  
  bool _isResetting = false;
  bool _isSyncing = false;
  String _lastPayloadChecksum = "";
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  final Set<int> _processedActionIds = {};

  Duration _serverTimeOffset = Duration.zero;
  bool _isClockSyncing = false;

  static final String _sessionRandom = (100000 + math.Random().nextInt(900000)).toString();
  static String? _cachedGuestId;

  String get _myUid {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) return user.id;
    
    _cachedGuestId ??= "guest_${100000 + math.Random().nextInt(900000)}";
    return _cachedGuestId!;
  }

  String get _playerTrackingId => "${_myUid}_$_sessionRandom";

  String get _getDeviceName {
    if (kIsWeb) return "Web-Nav-$_playerTrackingId";
    return "${Platform.operatingSystem}-$_playerTrackingId";
  }

  double get _currentPlayingDuration {
    if (gameLogic.players.isEmpty || gameLogic.currentPlayerIndex >= gameLogic.players.length) return 15.0;
    
    bool isInactive = gameLogic.inactiveAiPlayers.contains(gameLogic.currentPlayerIndex) || 
                      gameLogic.inactiveHumanPlayers.contains(gameLogic.currentPlayerIndex);
    
    return isInactive ? 7.0 : 15.0;
  }

  MultiplayerManager(this.gameLogic) {
    gameLogic.multiplayerManager = this;
    gameLogic.onActionBroadcast = (type, data) {
      if (_isResetting && type != 'NEXT_MANCHE_TRIGGER') return;
      if (!gameLogic.isMultiplayer || currentTable.isEmpty) return;
      
      _sendBroadcastAction(type, Map<String, dynamic>.from(data));
      
      if (isHost) {
        Future.microtask(() => _syncActionToSql(type, Map<String, Object?>.from(data)));
      }
    };
    
    _syncClockOffset();
  }

  String get _myName {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.userMetadata?['full_name']
          ?? user.userMetadata?['name']
          ?? user.email?.split('@')[0]
          ?? "Joueur";
    }
    return "Test_${_myUid.split('_').last}";
  }

  String get _myAvatar {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.userMetadata?['avatar_url']
          ?? user.userMetadata?['picture']
          ?? "";
    }
    return "";
  }

  Future<void> _syncClockOffset() async {
    if (_isClockSyncing) return;
    _isClockSyncing = true;
    try {
      final res = await Supabase.instance.client.rpc('get_server_time');
      if (res != null) {
        final start = DateTime.now();
        final serverTime = DateTime.parse(res.toString()).toUtc();
        final now = DateTime.now().toUtc();
        final latency = now.difference(start) ~/ 2;
        _serverTimeOffset = serverTime.difference(now.add(latency));
      }
    } catch (_) {} finally {
      _isClockSyncing = false;
    }
  }

  DateTime get _correctedNow => DateTime.now().toUtc().add(_serverTimeOffset);

  Future<void> joinTable([String? targetTableId]) async {
    final myId = _myUid; 
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      await Future.delayed(const Duration(milliseconds: 200));
      
      Map<String, dynamic>? data;

      if (targetTableId != null && targetTableId.isNotEmpty && targetTableId != "salle_par_defaut") {
        final existingSnap = await Supabase.instance.client
            .from('table_tarot_5')
            .select()
            .eq('table_id', targetTableId)
            .maybeSingle();

        if (existingSnap != null) {
          currentTable = targetTableId;
          int assignedSlot = 0;
          for (int i = 0; i < 5; i++) {
            if (existingSnap['player${i}_uid'] == myId) {
              assignedSlot = i;
              break;
            }
          }
          data = {
            'assigned_table_id': targetTableId,
            'assigned_slot': assignedSlot,
          };
        }
      }

      if (data == null) {
        final response = await Supabase.instance.client.rpc(
          'join_or_create_tarot_table',
          params: {
            'p_user_id': myId.toString(), 
            'p_user_name': _myName.toString(), 
            'p_user_avatar': _myAvatar.toString()
          }
        ).timeout(const Duration(seconds: 10));

        if (response != null) {
          if (response is List && response.isNotEmpty) {
            data = Map<String, dynamic>.from(response[0]);
          } else if (response is Map) {
            data = Map<String, dynamic>.from(response);
          } else {
            return;
          }
        }
      }

      if (data != null) {
        currentTable = data['assigned_table_id']?.toString() ?? "";
        int mySlot = int.tryParse(data['assigned_slot']?.toString() ?? "0") ?? 0;
        
        gameLogic.tableId = currentTable;
        gameLogic.myMultiplayerSide = mySlot;
        isHost = (mySlot == 0);
        gameLogic.isHost = isHost;
        gameLogic.isMultiplayer = true;
        deviceLabel = isHost ? "ALPHA" : "BETA";
        
        gameLogic.players = List.generate(5, (i) {
          if (i == mySlot) return Player(id: i, name: _myName, isHuman: true, hand: []);
          return Player(id: i, name: (i == 0 && !isHost) ? "Hôte" : "IA $i", isHuman: false, hand: []);
        });

        try {
          final initialSnap = await Supabase.instance.client.from('table_tarot_5').select().eq('table_id', currentTable).maybeSingle();
          if (initialSnap != null) {
            currentTableData = initialSnap;
            gameLogic.syncCommonData(initialSnap);

            if (initialSnap['turn_ends_at'] != null) {
              String rawTime = initialSnap['turn_ends_at'] as String;
              forcedExpiration = DateTime.parse(rawTime).toUtc();
              final int localDiff = forcedExpiration!.difference(_correctedNow).inSeconds;
              gameLogic.remainingTime = localDiff.clamp(0, 30).toDouble();
            }

            for (int i = 0; i < 5; i++) {
              if (initialSnap['player${i}_name'] != null) {
                gameLogic.players[i].name = initialSnap['player${i}_name'].toString();
                if (i != gameLogic.myMultiplayerSide) {
                  gameLogic.players[i].isHuman = (initialSnap['player${i}_uid'] != 'IA_ID' && initialSnap['player${i}_uid'] != null);
                }
              }
            }
          }
        } catch (_) {
          gameLogic.remainingTime = _currentPlayingDuration;
        }

        _connectRealtime(currentTable);
        if (isHost) {
          _connectActionsListener(currentTable);
        }
        _startHostTimer();

        if (!isHost) {
          _startBetaRecoveryPoll();
        }
        gameLogic.notifyListeners();
      }
    } catch (_) {} finally {
      _isSyncing = false;
    }
  }

  void _connectActionsListener(String tableId) {
    if (tableId.isEmpty) return;
    _actionChannel = Supabase.instance.client.channel('actions_$tableId');
    
    _actionChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'tarot_actions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'table_id',
        value: tableId,
      ),
      callback: (payload) {
        if (_isResetting) return; 

        final Map<String, dynamic> record = Map<String, dynamic>.from(payload.newRecord);
        final int? actionId = record['id'] as int?;

        if (actionId != null && _processedActionIds.contains(actionId)) return;
        if (actionId != null) _processedActionIds.add(actionId);

        final String actionType = record['action_type']?.toString() ?? '';
        final Map<String, dynamic> actionPayload = Map<String, dynamic>.from(record['payload'] as Map? ?? {});

        gameLogic.handleAction(actionType, actionPayload);
        _syncActionToSql(actionType, Map<String, Object?>.from(actionPayload));
        
        gameLogic.refresh();
      }
    ).subscribe();
  }

  Future<void> _syncActionToSql(String type, Map<String, Object?> data) async {
    if (!isHost || currentTable.isEmpty || currentTable == "salle_par_defaut") return;
    
    if (type == 'NEXT_MANCHE_TRIGGER') {
      _isResetting = false; 
    }
    
    if (_isResetting) return;
    
    gameLogic.version++;

    String computedStatus = _mapStateToStatus(gameLogic.currentState);
    if (type == 'INITIAL_DEAL') computedStatus = 'BIDDING';
    if (type == 'PLAY_CARD' || gameLogic.currentState == GameState.playing) computedStatus = 'STARTED';

    Map<String, int> trickMap = {};
    for (var entry in gameLogic.currentTrickData) {
      if (entry.isNotEmpty) {
        trickMap[entry.keys.first.toString()] = entry.values.first.id;
      }
    }

    Map<String, dynamic> tricksWonMap = {};
    for (var p in gameLogic.players) {
      tricksWonMap[p.id.toString()] = p.tricksWon.map((c) => c.id).toList();
    }

    int turnDuration = 30;
    if (gameLogic.currentState == GameState.playing) {
      bool isInactive = gameLogic.inactiveAiPlayers.contains(gameLogic.currentPlayerIndex) || 
                        gameLogic.inactiveHumanPlayers.contains(gameLogic.currentPlayerIndex);
      turnDuration = isInactive ? 7 : 15;
    }

    Map<String, Object?> updates = {
      'version': gameLogic.version,
      'last_action_time': DateTime.now().toUtc().toIso8601String(),
      'current_player_index': gameLogic.currentPlayerIndex,
      'phone_index': _getDeviceName,
      'player_count': 5,
      'game_status': computedStatus,
      'contrat': gameLogic.currentContractName,
      'bid_taker_id': gameLogic.takerId?.toString(),
      'partner_id': gameLogic.partnerId?.toString(),
      'called_king': gameLogic.calledKingId,
      'chien': gameLogic.chien.map((c) => c.id).toList(),
      'current_trick': trickMap, 
      'live_taker_score': gameLogic.currentTakerScore,
      'live_defense_score': gameLogic.currentDefenseScore,
      'players_tricks_won': tricksWonMap,
      'last_winner_index': gameLogic.lastWinnerIndex,
      'last_card_played': gameLogic.lastCardPlayed?.toString(), 
      'turn_ends_at': _correctedNow.add(Duration(seconds: turnDuration)).toIso8601String(),
      'lead_suit': gameLogic.leadSuit?.toString(),
    };

    if (type == 'TRICK_RESOLVED') {
      updates['current_trick'] = {};
      updates['lead_suit'] = null;
      if (data.containsKey('winner')) {
        int w = int.tryParse(data['winner'].toString()) ?? gameLogic.currentPlayerIndex;
        gameLogic.currentPlayerIndex = w;
        updates['current_player_index'] = w;
      }
    }

    if (type == 'NEXT_MANCHE_TRIGGER') {
      updates['contrat'] = null;
      updates['bid_taker_id'] = null;
      updates['partner_id'] = null;
      updates['called_king'] = null;
      updates['current_trick'] = {}; 
      updates['live_taker_score'] = 0;
      updates['live_defense_score'] = 0;
      updates['players_tricks_won'] = {'0': [], '1': [], '2': [], '3': [], '4': []};
      updates['last_card_played'] = null;
      updates['last_winner_index'] = null;
      updates['game_status'] = 'BIDDING';
      updates['current_manche'] = gameLogic.currentManche;
      updates['dealer_index'] = gameLogic.dealerIndex;
      updates['chien'] = gameLogic.chien.map((c) => c.id).toList();
      updates['deck_hash'] = gameLogic.currentDeckHash;
      updates['lead_suit'] = null;
      updates['turn_ends_at'] = _correctedNow.add(const Duration(seconds: 30)).toIso8601String(); 
      if (data.containsKey('cumule_score')) {
        updates['cumule_score'] = data['cumule_score'];
      }
    }

    if (gameLogic.players.length >= 5) {
      Map<String, dynamic> handsMap = {};
      for (int i = 0; i < 5; i++) {
        List<int> hIds = gameLogic.players[i].hand.map((c) => c.id).toList();
        updates['hand_$i'] = hIds;
        handsMap[i.toString()] = hIds;
        updates['player${i}_name'] = gameLogic.players[i].name;
      }
      updates['hands'] = handsMap;
      
      int side = gameLogic.myMultiplayerSide;
      if (side >= 0 && side < 5) {
        updates['player${side}_uid'] = _myUid; 
        updates['player${side}_avatar'] = _myAvatar;
        updates['player${side}_name'] = _myName;
      }
    }

    String payloadChecksum = jsonEncode(updates);
    if (payloadChecksum == _lastPayloadChecksum && type != 'NEXT_MANCHE_TRIGGER') {
      return;
    }
    _lastPayloadChecksum = payloadChecksum;
    _lastSyncTime = DateTime.now();

    try {
      await Supabase.instance.client.from('table_tarot_5').update(updates).eq('table_id', currentTable);
    } catch (_) {}
  }

  String _mapStateToStatus(GameState state) {
    switch (state) {
      case GameState.bidding: return 'BIDDING';
      case GameState.calling: return 'CALLING';
      case GameState.dogRevealed: return 'DOG_REVEALED';
      case GameState.discarding: return 'DISCARDING';
      case GameState.playing: return 'STARTED';
      case GameState.scoring: return 'SCORING';
      default: return 'STARTED';
    }
  }

  void _connectRealtime(String tableId) {
    if (tableId.isEmpty) return;
    _channel = Supabase.instance.client.channel(tableId);
    
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'table_tarot_5',
      callback: (payload) {
        final Map<String, Object?> newData = Map<String, Object?>.from(payload.newRecord);
        if (newData['phone_index'] == _getDeviceName) return;

        final String? statusEnBase = newData['game_status']?.toString();
        if (statusEnBase == 'IDLE' || statusEnBase == null || statusEnBase.isEmpty) return;

        final int versionSql = int.tryParse(newData['version']?.toString() ?? '0') ?? 0;
        if (versionSql <= gameLogic.version) return;

        if (isHost) return;

        currentTableData = newData;
        gameLogic.version = versionSql;
        
        if (newData['turn_ends_at'] != null) {
          String rawTime = newData['turn_ends_at'] as String;
          if (!rawTime.endsWith('Z') && !rawTime.contains('+')) {
            rawTime += 'Z';
          }
          forcedExpiration = DateTime.parse(rawTime).toUtc();
          final int localDiff = forcedExpiration!.difference(_correctedNow).inSeconds;
          gameLogic.remainingTime = localDiff.clamp(0, 30).toDouble();
        }

        final String statusBase = newData['game_status']?.toString() ?? '';
        switch (statusBase) {
          case 'BIDDING':
            gameLogic.currentState = GameState.bidding;
            gameLogic.hasClickedBid = false;
            gameLogic.hasClickedKing = false;
            if (newData['current_player_index'] != null) {
              gameLogic.currentPlayerIndex = int.tryParse(newData['current_player_index'].toString()) ?? 0;
            }
            break;
          case 'CALLING':
            gameLogic.currentState = GameState.calling;
            break;
          case 'DOG_REVEALED':
            gameLogic.currentState = GameState.dogRevealed;
            break;
          case 'DISCARDING':
            gameLogic.currentState = GameState.discarding;
            break;
          case 'STARTED':
            if (gameLogic.players.isNotEmpty && gameLogic.currentState != GameState.scoring) {
              gameLogic.currentState = GameState.playing;
            }
            // SYNCHRONISATION ATOMIQUE DU JOUEUR ACTIF POUR ÉVITER LE RETOUR AU SLOT 0
            if (newData['current_player_index'] != null) {
              gameLogic.currentPlayerIndex = int.tryParse(newData['current_player_index'].toString()) ?? gameLogic.currentPlayerIndex;
            }
            break;
          case 'SCORING':
            gameLogic.currentState = GameState.scoring;
            break;
        }

        gameLogic.handleAction('SYNC_VAL_SQL', newData);
        
        if (newData['lead_suit'] != null && newData['lead_suit'] != 'null' && newData['lead_suit'] != '') {
          String suitStr = newData['lead_suit'].toString();
          try {
            gameLogic.leadSuit = CardSuit.values.firstWhere((e) => e.toString() == suitStr || e.toString().split('.').last == suitStr);
          } catch (_) {
            gameLogic.leadSuit = null;
          }
        } else {
          if (newData['current_trick'] != null) {
            try {
              dynamic parsedTrick = newData['current_trick'];
              if (parsedTrick is String) {
                parsedTrick = jsonDecode(parsedTrick);
              }
              if (parsedTrick is List && parsedTrick.isNotEmpty) {
                final allCards = gameLogic.generateFullTarotDeck();
                CardSuit? detectedLead;
                for (var item in parsedTrick) {
                  if (item == null) continue;
                  int cardId = -1;
                  if (item is Map) {
                    cardId = int.tryParse(item['id']?.toString() ?? '-1') ?? -1;
                  } else {
                    cardId = int.tryParse(item.toString()) ?? -1;
                  }
                  if (cardId != -1) {
                    try {
                      var foundCard = allCards.firstWhere((c) => c.id == cardId);
                      if (foundCard.suit != CardSuit.excuse) {
                        detectedLead = foundCard.suit;
                        break;
                      }
                    } catch (_) {}
                  }
                }
                gameLogic.leadSuit = detectedLead;
              } else if (parsedTrick is Map && parsedTrick.isNotEmpty) {
                final allCards = gameLogic.generateFullTarotDeck();
                CardSuit? detectedLead;
                for (var val in parsedTrick.values) {
                  if (val == null) continue;
                  int cardId = -1;
                  if (val is Map) {
                    cardId = int.tryParse(val['id']?.toString() ?? '-1') ?? -1;
                  } else {
                    cardId = int.tryParse(val.toString()) ?? -1;
                  }
                  if (cardId != -1) {
                    try {
                      var foundCard = allCards.firstWhere((c) => c.id == cardId);
                      if (foundCard.suit != CardSuit.excuse) {
                        detectedLead = foundCard.suit;
                        break;
                      }
                    } catch (_) {}
                  }
                }
                gameLogic.leadSuit = detectedLead;
              }
            } catch (_) {}
          } else {
            gameLogic.leadSuit = null;
          }
        }

        gameLogic.refresh();
      },
    ).onBroadcast(event: 'game_action', callback: (payload) {
      if (payload == null || payload['senderId'] == _playerTrackingId) return;
      
      final String actionType = payload['type'] as String? ?? 'UNKNOWN';
      final data = Map<String, dynamic>.from(payload['data'] as Map? ?? {});
      
      gameLogic.handleAction(actionType, data);
      
      if (isHost) {
        Future.microtask(() => _syncActionToSql(actionType, Map<String, Object?>.from(data)));
      }
      
      gameLogic.refresh();
    }).onPresenceSync((p) {
      _syncAvatars();
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel?.track({'id': _playerTrackingId, 'name': _myName, 'slot': gameLogic.myMultiplayerSide, 'avatar': _myAvatar});
      }
    });
  }

  void _syncAvatars() {
    if (gameLogic.players.length < 5) return;
    final states = _channel?.presenceState() ?? [];
    
    if (_isSyncing || _isResetting) return;

    for (int i = 0; i < 5; i++) {
      if (i != gameLogic.myMultiplayerSide) {
        if (!isHost) {
          gameLogic.players[i].isHuman = (i == 0); 
        }
      }
    }

    for (var state in states) {
      for (var m in state.presences) {
        final Map<String, Object?> payload = Map<String, Object?>.from(m.payload);
        int? pSlot = payload['slot'] as int?;
        if (pSlot != null && pSlot >= 0 && pSlot < 5) {
          if (pSlot != gameLogic.myMultiplayerSide) {
            gameLogic.players[pSlot].name = payload['name'] as String? ?? "Joueur";
            gameLogic.players[pSlot].isHuman = true; 
          }
        }
      }
    }
    gameLogic.notifyListeners();
  }

  void _sendBroadcastAction(String type, Map<String, dynamic> data) {
    if (currentTable.isEmpty || !gameLogic.isMultiplayer) return;
    _channel?.sendBroadcastMessage(
      event: 'game_action', 
      payload: {'type': type, 'senderId': _playerTrackingId, 'data': data}
    );
  }

  void _startHostTimer() {
    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!gameLogic.isMultiplayer) {
        timer.cancel();
        return;
      }

      if (gameLogic.currentState == GameState.playing && gameLogic.currentTrickData.length >= gameLogic.players.length) {
        return;
      }

      if (gameLogic.remainingTime > 0) {
        gameLogic.remainingTime -= 1.0;
      }

      if (gameLogic.remainingTime <= 0) {
        gameLogic.remainingTime = 0.0;
        if (isHost) {
          _onTimeout();
        } else {
          gameLogic.refresh();
        }
      } else {
        gameLogic.refresh();
      }
    });
  }

  Future<void> _onTimeout() async {
    if (!isHost || currentTable.isEmpty || _isResetting) return;
    
    if (gameLogic.currentState == GameState.bidding || 
        gameLogic.currentState == GameState.calling || 
        gameLogic.currentState == GameState.dogRevealed ||
        gameLogic.currentState == GameState.discarding || 
        gameLogic.currentState == GameState.playing) {
      
      await gameLogic.forceTimeoutAction();
      return;
    }

    _isResetting = true;
    
    gameLogic.lastBidName = "";
    gameLogic.takerId = null;
    gameLogic.version++;

    gameLogic.resetGameForTimeout(5, currentTable);
    
    final states = _channel?.presenceState() ?? [];
    List<String> uids = List.generate(5, (i) => i == 0 ? _myUid : "IA_ID");
    List<String> names = List.generate(5, (i) => i == 0 ? _myName : "IA $i");
    
    gameLogic.players[0].isHuman = true;
    gameLogic.players[0].name = _myName;
    
    for (var state in states) {
      for (var m in state.presences) {
        final Map<String, Object?> payload = Map<String, Object?>.from(m.payload);
        int? slot = payload['slot'] as int?;
        if (slot != null && slot < 5 && slot >= 0) {
          String rawId = payload['id'] as String? ?? "IA_ID";
          if (rawId.contains('_')) {
            rawId = rawId.split('_')[0];
          }
          uids[slot] = rawId;
          names[slot] = payload['name'] as String? ?? "IA $slot";
          
          if (slot != 0 && slot < gameLogic.players.length) {
            gameLogic.players[slot].isHuman = true;
            gameLogic.players[slot].name = names[slot];
          }
        }
      }
    }

    gameLogic.hasClickedBid = false;
    gameLogic.hasClickedKing = false;
    
    int pc = gameLogic.players.isEmpty ? 5 : gameLogic.players.length;
    gameLogic.currentPlayerIndex = ((gameLogic.dealerIndex ?? 0) + 1) % pc; 
    
    gameLogic.refresh();

    final Map<String, Object?> finalMap = {
      'game_status': 'BIDDING',
      'version': gameLogic.version,
      'dealer_index': gameLogic.dealerIndex ?? 0,
      'current_player_index': gameLogic.currentPlayerIndex, 
      'current_bidder_index': gameLogic.currentPlayerIndex, 
      'player0_uid': uids[0], 'player1_uid': uids[1], 'player2_uid': uids[2], 'player3_uid': uids[3], 'player4_uid': uids[4],
      'player0_name': names[0], 'player1_name': names[1], 'player2_name': names[2], 'player3_name': names[3], 'player4_name': names[4],
      'hand_0': gameLogic.players.length > 0 ? gameLogic.players[0].hand.map((c) => c.id).toList() : [],
      'hand_1': gameLogic.players.length > 1 ? gameLogic.players[1].hand.map((c) => c.id).toList() : [],
      'hand_2': gameLogic.players.length > 2 ? gameLogic.players[2].hand.map((c) => c.id).toList() : [],
      'hand_3': gameLogic.players.length > 3 ? gameLogic.players[3].hand.map((c) => c.id).toList() : [],
      'hand_4': gameLogic.players.length > 4 ? gameLogic.players[4].hand.map((c) => c.id).toList() : [],
      'chien': gameLogic.chien.map((c) => c.id).toList(),
      'deck_hash': gameLogic.currentDeckHash,
      'player_count': 5,
      'contrat': null,
      'live_taker_score': 0,
      'live_defense_score': 0,
      'players_tricks_won': {'0': [], '1': [], '2': [], '3': [], '4': []},
      'phone_index': _getDeviceName,
      'called_king': null,
      'current_trick': {},
      'lead_suit': null,
      'last_winner_index': null,
      'last_card_played': null,
      'last_action_time': DateTime.now().toUtc().toIso8601String(),
      'turn_ends_at': _correctedNow.add(const Duration(seconds: 30)).toIso8601String(),
    };

    _lastPayloadChecksum = jsonEncode(finalMap);
    _lastSyncTime = DateTime.now();

    try {
      await Supabase.instance.client.from('table_tarot_5').update(finalMap).eq('table_id', currentTable);
      _sendBroadcastAction('NEXT_MANCHE_TRIGGER', finalMap);
    } catch (_) {
      gameLogic.version--;
    } finally {
      _isResetting = false;
    }
  }

  void _startBetaRecoveryPoll() {
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (gameLogic.currentState != GameState.idle) {
        timer.cancel();
        return;
      }

      if (currentTable.isEmpty || !gameLogic.isMultiplayer || _isResetting || _isSyncing) return;
      
      final states = _channel?.presenceState() ?? [];
      bool hostFound = states.any((state) => state.presences.any((m) => m.payload['slot'] == 0));
      if (hostFound) return; 

      _isSyncing = true;
      try {
        final res = await Supabase.instance.client.from('table_tarot_5').select().eq('table_id', currentTable).maybeSingle();
        if (res != null) {
          if (res['phone_index'] == _getDeviceName) return;

          final int versionSql = int.tryParse(res['version']?.toString() ?? '0') ?? 0;
          if (versionSql <= gameLogic.version) return;

          gameLogic.handleAction('SYNC_VAL_SQL', Map<String, Object?>.from(res as Map));
          gameLogic.refresh();
        }
      } catch (_) {} finally {
        _isSyncing = false;
      }
    });
  }

  void dispose() {
    _syncTimer?.cancel(); 
    _recoveryTimer?.cancel(); 
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    if (_actionChannel != null) {
      Supabase.instance.client.removeChannel(_actionChannel!);
    }
  }
}
