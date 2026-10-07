import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tarot_app/models.dart';

/// Niveaux d'urgence des événements traqués par le mouchard
enum LogSeverity { info, warning, critical, antiCheat }

/// Helper universel de parsing des cartes (sécurité typage Supabase)
List<int> parseCardIds(dynamic rawList) {
  if (rawList == null) return [];
  if (rawList is String) {
    if (rawList.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(rawList);
      if (decoded is List) {
        return decoded
            .map((e) => e is int ? e : int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
      }
    } catch (_) {
      return rawList
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();
    }
  }
  if (rawList is List) {
    return rawList
        .map((e) => e is int ? e : int.tryParse(e.toString()))
        .whereType<int>()
        .toList();
  }
  return [];
}

class RemoteLogger {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // --- 0. COMPATIBILITÉ & LOGS SYSTÈME (main.dart & logic.dart) ---
  static void send(String level, String message, [Map<String, dynamic>? details]) {
    final timestamp = DateTime.now().toIso8601String();
    final detailsString = details != null ? ' | Details: $details' : '';
    debugPrint('[$timestamp] [$level] $message$detailsString');
  }

  static void logEnd(String tableId, bool success) {
    send('INFO', 'Fin de partie enregistrée', {
      'table_id': tableId,
      'success': success,
    });
  }

  // --- 1. EXPÉDITION DES LOGS (CONSOLE + SUPABASE) ---
  static Future<void> log({
    required String gameId,
    required int playerId,
    required String action,
    required LogSeverity severity,
    Map<String, dynamic>? details,
  }) async {
    final payload = {
      'game_id': gameId,
      'player_id': playerId,
      'action': action,
      'severity': severity.name,
      'details': details ?? {},
      'created_at': DateTime.now().toIso8601String(),
    };

    // Journalisation locale dans le terminal
    debugPrint('[AUDIT NETWORK - ${severity.name.toUpperCase()}] P$playerId -> $action | ${details ?? ""}');

    // Persistence distante pour les anomalies, alertes et cas d'anti-triche
    if (severity != LogSeverity.info) {
      try {
        await _supabase.from('game_logs').insert(payload);
      } catch (e) {
        debugPrint('[REMOTE_LOGGER ERROR] Échec d\'envoi vers Supabase: $e');
      }
    }
  }

  // --- 2. AUDIT DE SYNCHRONISATION EN TEMPS RÉEL (REALTIME) ---
  /// Compare l'état du pli local avec la transmission brute reçue de Supabase
  static bool auditTrickSync({
    required String gameId,
    required int localPlayerId,
    required List<Map<int, CardModel>> localTrick,
    required dynamic rawRemoteTrick,
  }) {
    final List<int> remoteCardIds = parseCardIds(rawRemoteTrick);
    final List<int> localCardIds = localTrick
        .where((m) => m.isNotEmpty)
        .map((m) => m.values.first.id)
        .toList();

    // Incohérence du nombre de cartes sur le tapis
    if (localCardIds.length != remoteCardIds.length) {
      log(
        gameId: gameId,
        playerId: localPlayerId,
        action: 'DESYNC_TRICK_COUNT_MISMATCH',
        severity: LogSeverity.critical,
        details: {
          'local_count': localCardIds.length,
          'remote_count': remoteCardIds.length,
          'local_ids': localCardIds,
          'remote_ids': remoteCardIds,
        },
      );
      return false;
    }

    // Incohérence sur la séquence exacte des cartes jouées
    for (int i = 0; i < localCardIds.length; i++) {
      if (localCardIds[i] != remoteCardIds[i]) {
        log(
          gameId: gameId,
          playerId: localPlayerId,
          action: 'DESYNC_CARD_MISMATCH',
          severity: LogSeverity.critical,
          details: {
            'index': i,
            'local_card': localCardIds[i],
            'remote_card': remoteCardIds[i],
          },
        );
        return false;
      }
    }
    return true;
  }

  // --- 3. MOUCHARD ANTI-TRICHE : VALIDATION AVANT SOUMISSION BDD ---

  /// Intercepte les coups illégaux avant toute écriture réseau
  static bool validateMoveBeforeSubmit({
    required String gameId,
    required int playerId,
    required CardModel cardToPlay,
    required List<CardModel> playerHand,
  }) {
    // Vérification : La carte jouée appartient-elle bien à la main locale du joueur ?
    final bool hasCard = playerHand.any((c) => c.id == cardToPlay.id);
    if (!hasCard) {
      log(
        gameId: gameId,
        playerId: playerId,
        action: 'ANTI_CHEAT_CARD_NOT_IN_HAND',
        severity: LogSeverity.antiCheat,
        details: {
          'played_card_id': cardToPlay.id,
          'hand_ids': playerHand.map((c) => c.id).toList(),
        },
      );
      return false;
    }
    return true;
  }

  /// Valide la conformité de l'Écart réalisé par le preneur
  static bool validateEcartBeforeSubmit({
    required String gameId,
    required int takerId,
    required List<CardModel> ecartCards,
    required List<CardModel> fullHandWithDog,
  }) {
    // 1. Taille exacte de l'écart
    if (ecartCards.length != 6) {
      log(
        gameId: gameId,
        playerId: takerId,
        action: 'ANTI_CHEAT_INVALID_ECART_SIZE',
        severity: LogSeverity.antiCheat,
        details: {'ecart_length': ecartCards.length},
      );
      return false;
    }

    // 2. Interdiction absolue d'écarter Bouts ou Rois
    for (var card in ecartCards) {
      if (card.isBout || (card.suit != CardSuit.atout && card.value == "14")) {
        log(
          gameId: gameId,
          playerId: takerId,
          action: 'ANTI_CHEAT_FORBIDDEN_CARD_IN_ECART',
          severity: LogSeverity.antiCheat,
          details: {'card_id': card.id, 'value': card.value, 'suit': card.suit.name},
        );
        return false;
      }
    }

    // 3. Vérification de l'origine des cartes (cartes présentes en main + Chien)
    final Set<int> validIds = fullHandWithDog.map((c) => c.id).toSet();
    for (var card in ecartCards) {
      if (!validIds.contains(card.id)) {
        log(
          gameId: gameId,
          playerId: takerId,
          action: 'ANTI_CHEAT_ECART_CARD_NOT_IN_HAND',
          severity: LogSeverity.antiCheat,
          details: {'card_id': card.id},
        );
        return false;
      }
    }

    return true;
  }
}
