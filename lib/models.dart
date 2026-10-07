import 'package:flutter/material.dart';

// --- ENUMÉRATIONS DE BASE ALIGNÉES ---
enum CardSuit { coeur, carreau, pique, trefle, atout, excuse }
enum GameState { idle, waiting, bidding, calling, dogRevealed, playing, discarding, scoring }
enum BidType { pass, petite, garde, gardeSans, gardeContre }
enum TableType { triangle, square, pentagon }
enum PoigneeType { none, simple, doubleP, triple }

// --- MODÈLE DE CARTE ---
class CardModel {
  final int id;
  final CardSuit suit;
  final String value;
  final int power;
  final double points;
  String assetPath;
  bool isSelected;
  bool isHuman;
  bool isBout;

  CardModel({
    required this.id,
    required this.suit,
    required this.value,
    required this.power,
    required this.points,
    required this.assetPath,
    this.isSelected = false,
    this.isHuman = false,
    this.isBout = false,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] ?? 0,
      suit: CardSuit.values[json['s'] as int],
      value: json['v'] as String,
      power: json['p'] as int,
      points: (json['pts'] as num).toDouble(),
      isBout: json['b'] ?? false,
      assetPath: "", 
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    's': suit.index,
    'v': value,
    'p': power,
    'pts': points,
    'b': isBout,
  };
}

// --- MODÈLE DE JOUEUR ---
class Player {
  int id;
  String name;
  List<CardModel> hand;
  List<CardModel> tricksWon = [];
  double score = 0.0;
  int currentBalance;
  bool isHuman;
  PoigneeType poignee = PoigneeType.none;
  BidType bid = BidType.pass;
  double lastScore = 0.0;
  
  // 👉 CORRECTION POINT 5 : Persistance renforcée des avatars et noms d'affichage
  String? avatarUrl;
  String? displayName;

  Player({
    required this.id,
    required this.name,
    required this.hand,
    this.isHuman = false,
    this.currentBalance = 15000,
    this.avatarUrl,
    this.displayName,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    var handList = json['hand'] as List? ?? [];
    var tricksList = json['tricks'] as List? ?? [];
    return Player(
      id: json['id'] ?? 0,
      name: json['name'] ?? "Joueur",
      hand: handList.map((e) => CardModel.fromJson(e)).toList(),
      isHuman: json['is_human'] ?? false,
      currentBalance: json['balance'] ?? 15000,
      avatarUrl: json['avatar'] ?? json['avatarUrl'],
      displayName: json['display_name'] ?? json['name'],
    )..tricksWon = tricksList.map((e) => CardModel.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'is_human': isHuman,
    'balance': currentBalance,
    'avatar': avatarUrl,
    'display_name': displayName,
    'hand': hand.map((e) => e.toJson()).toList(),
    'tricks': tricksWon.map((e) => e.toJson()).toList(),
  };

  void syncWithSupabase(int realSlot, String realName, String? realAvatar) {
    this.id = realSlot;
    this.name = realName;
    this.displayName = realName;
    if (realAvatar != null && realAvatar.isNotEmpty) {
      this.avatarUrl = realAvatar;
    }
  }

  static Player createLocal(int id, String name, String? avatar) {
    return Player(
      id: id,
      name: name,
      displayName: name,
      avatarUrl: avatar,
      hand: [],
      isHuman: true,
    );
  }
}

// --- GESTION DES CONTRATS ---
class TarotContract {
  final BidType type;
  final int multiplier;
  TarotContract({required this.type, this.multiplier = 1});

  int get baseValue {
    switch (type) {
      case BidType.petite: return 25;
      case BidType.garde: return 50;
      case BidType.gardeSans: return 100;
      case BidType.gardeContre: return 200;
      default: return 0;
    }
  }
}

// --- MOTEUR DE RÈGLES HARMONISÉ ---
class RuleEngine {
  static bool isMoveLegal(CardModel card, List<CardModel> hand, List<CardModel> trick) {
    if (card.suit == CardSuit.excuse) return true;
    if (trick.isEmpty) return true;
   
    CardSuit requestedSuit = (trick.first.suit == CardSuit.excuse && trick.length > 1)
        ? trick[1].suit
        : trick.first.suit;
        
    bool hasSuit = hand.any((c) => c.suit == requestedSuit);
    if (hasSuit) {
      return card.suit == requestedSuit;
    }
   
    bool hasAtout = hand.any((c) => c.suit == CardSuit.atout);
    if (requestedSuit != CardSuit.atout && hasAtout) {
      return card.suit == CardSuit.atout;
    }
    return true;
  }
}

// --- THÈME VISUEL ---
class GameTheme {
  static const Color gold = Color(0xFFD4AF37);
  static const Color darkBg = Color(0xFF0A0A0A);
}
