import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tarot_app/models.dart';
import 'dart:math' as math;
import 'package:tarot_app/score_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'logic.dart';

class TarotTable extends StatelessWidget {
  final int playerCount;
  const TarotTable({super.key, required this.playerCount});

  static final ValueNotifier<bool> _isTrickZoomed = ValueNotifier<bool>(false);
  static final ValueNotifier<int> _tableZoomLevel = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    final l = Provider.of<TarotGameLogic>(context);
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    bool isMyTurn = l.currentPlayerIndex == myIdx;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
          _showQuickInteractionMenu(context, l);
        }
      },
      child: Container(
        key: const ValueKey('tarot_table_root_interface'),
        width: 1280,
        height: 720,
        color: const Color(0xFF050505),
        child: Stack(children: [
          _bg(),
          _tapis(context),
          
          if (l.players.isNotEmpty)
            _opponents(l, context),

          _tableCards(l),
          _chienEcart(l),
          _playerHand(l, context),
          _score(l, context),
          _lastTrick(l),

          if (l.showPoigneeButton)
            Positioned(top: 15, right: 15, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
              ),
              onPressed: () => l.annoncerPoignee(),
              child: const Text("ANNONCER POIGNÉE", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
            )),

          if (l.currentState == GameState.scoring)
            const Positioned.fill(
              child: Material(
                color: Colors.black,
                child: ScoreScreen(),
              ),
            ),

          if (l.currentState == GameState.bidding && isMyTurn && !l.hasClickedBid)
            _bidding(l),

          if (l.currentState == GameState.calling && isMyTurn)
            _kingPicker(l),

          if (l.callMessage.isNotEmpty && l.currentState != GameState.idle)
            Positioned(top: 15, left: 0, right: 0, child: _announcement(l.callMessage)),

          Positioned(
            bottom: 5,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "▲ Glisser vers le haut pour Emojis & Tchat ▲",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 9),
              ),
            ),
          ),

          Positioned(bottom: 10, right: 10, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.account_circle, color: Colors.white70),
              onPressed: () => Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google)
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _bg() => Container(decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/images/menu_bg.png"), fit: BoxFit.cover)));
 
  Widget _tapis(BuildContext c) => Center(
    child: Container(
      width: MediaQuery.of(c).size.width * 0.82,
      height: MediaQuery.of(c).size.height * 0.77,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage("assets/images/table_tapis.png"),
          fit: BoxFit.fill,
          colorFilter: ColorFilter.mode(
            Colors.white.withValues(alpha: 0.85),
            BlendMode.dstIn
          )
        )
      )
    )
  );

  Widget _lastTrick(TarotGameLogic l) {
    if (l.lastTrickCards.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: _isTrickZoomed, 
      builder: (context, isZoomed, child) {
        return Positioned(
          top: isZoomed ? 70 : 25, 
          right: isZoomed ? 40 : 15, 
          child: GestureDetector(
            onTap: () => _isTrickZoomed.value = !_isTrickZoomed.value, 
            child: SizedBox(
              width: isZoomed ? 240 : 140, 
              height: isZoomed ? 140 : 90, 
              child: Stack(
                clipBehavior: Clip.none, 
                children: List.generate(l.lastTrickCards.length, (i) => Positioned(
                  left: i * (isZoomed ? 32.0 : 18.0), 
                  child: TarotCardWidget(
                    card: l.lastTrickCards[i], 
                    isHuman: true, 
                    width: isZoomed ? 65.0 : 42.0,
                    showFrame: false,
                  )
                ))
              )
            )
          )
        );
      }
    );
  }

  Widget _score(TarotGameLogic l, BuildContext context) {
    if (l.selectedBid == null || l.selectedBid == BidType.pass || l.version == 0 || l.currentState == GameState.idle || l.currentState == GameState.bidding) {
      return const SizedBox.shrink();
    }
   
    String b = l.selectedBid.toString().split('.').last.toUpperCase();
    String s = l.calledKingSuit != null ? _sym(l.calledKingSuit) : "";
   
    return Positioned(top: 15, left: 15, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("$b $s", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85), 
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1.5), 
          borderRadius: BorderRadius.circular(12)
        ), 
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.flash_on, color: Colors.redAccent, size: 18), 
            const SizedBox(width: 10), 
            Text(
              l.currentTakerScore.toStringAsFixed(1).replaceFirst('.', ','), 
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
            )
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(color: Colors.white12, height: 1)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shield, color: Colors.blueAccent, size: 18), 
            const SizedBox(width: 10), 
            Text(
              l.currentDefenseScore.toStringAsFixed(1).replaceFirst('.', ','), 
              style: const TextStyle(color: Colors.white70, fontSize: 18)
            )
          ]),
        ]),
      ),
    ]));
  }

  Widget _playerHand(TarotGameLogic l, BuildContext c) {
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    if (l.players.isEmpty || l.players.length <= myIdx) return const SizedBox.shrink();
   
    final h = List<CardModel>.from(l.players[myIdx].hand);
    h.sort((a, b) {
      Map<CardSuit, int> order = {CardSuit.pique: 0, CardSuit.carreau: 1, CardSuit.trefle: 2, CardSuit.coeur: 3, CardSuit.atout: 4, CardSuit.excuse: 5};
      int cmp = order[a.suit]!.compareTo(order[b.suit]!);
      return cmp != 0 ? cmp : a.power.compareTo(b.power);
    });
   
    return Positioned(bottom: -200, left: 0, right: 0, child: SizedBox(height: 400, child: LayoutBuilder(builder: (c, constraints) {
      bool f = h.length <= 6;
      int m = f ? h.length : (h.length / 2).ceil();
      double sp = l.cardWidth > 100 ? (l.players.length == 5 ? 60.0 : 68.0) : (l.players.length == 5 ? 47.0 : 54.0);
      double w = l.cardWidth;
     
      return Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
        ...List.generate(h.length, (i) {
          bool t = f ? true : i < m;
          int rI = f ? i : (t ? i : i - m);
          int rT = f ? m : (t ? m : h.length - m);
          double an = f ? 0.0 : (rI / (rT - 1 + 1e-9) - 0.5) * 0.35;
          double cv = f ? 0.0 : math.pow((rI / (rT - 1 + 1e-9) - 0.5), 2) * 15;
         
          return Positioned(left: (constraints.maxWidth/2) + ((rI-(rT-1)/2)*sp) - (w/2), bottom: (t ? 162.0 : 122.5) - cv, child: Transform.rotate(angle: an, child: GestureDetector(onTap: () {
            if (l.currentState == GameState.discarding) { l.handleDiscardClick(h[i]); }
            else if (l.currentState == GameState.playing && l.currentPlayerIndex == myIdx) { l.playCard(myIdx, h[i]); }
          }, child: TarotCardWidget(card: h[i], isHuman: true, isPlayable: l.isCardPlayable(h[i]), width: w))));
        }),
        Positioned(left: (constraints.maxWidth/2) - (m*sp/2) - 160, bottom: 220, child: _avatar(l.players[myIdx], l.currentPlayerIndex == myIdx, l, c)),
      ]);
    })));
  }

  Widget _opponents(TarotGameLogic l, BuildContext context) {
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    List<Widget> children = [];
    for (int i = 0; i < l.players.length; i++) {
      if (i == myIdx) continue;
      int visualPos = (i - myIdx + l.players.length) % l.players.length;
      children.add(Align(alignment: _align(visualPos, l.players.length), child: _avatar(l.players[i], l.currentPlayerIndex == i, l, context)));
    }
    return Stack(children: children);
  }

  Alignment _align(int i, int n) {
    if (n == 5) {
      switch (i) {
        case 1: return const Alignment(0.98, 0.60);
        case 2: return const Alignment(0.55, -0.98);
        case 3: return const Alignment(-0.55, -0.98);
        case 4: return const Alignment(-0.98, 0.05);
      }
    }
    if (n == 4) {
      switch (i) {
        case 1: return const Alignment(0.95, 0.0);
        case 2: return const Alignment(0.0, -0.95);
        case 3: return const Alignment(-0.95, 0.0);
      }
    }
    if (n == 3) {
      switch (i) {
        case 1: return const Alignment(0.75, -0.85);
        case 2: return const Alignment(-0.75, -0.85);
      }
    }
    return Alignment.center;
  }

  void _showEditNameDialog(BuildContext context, TarotGameLogic l, Player p) {
    TextEditingController controller = TextEditingController(text: p.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Modifier mon pseudo", style: TextStyle(color: Colors.amber)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Entre ton nom...",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber, width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ANNULER", style: TextStyle(color: Colors.white))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () async {
              p.name = controller.text;
              l.refresh();
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                try {
                  await Supabase.instance.client.auth.updateUser(
                    UserAttributes(data: {'display_name': controller.text}),
                  );
                } catch (e) {
                  debugPrint("Erreur synchro pseudo: $e");
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("VALIDER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPlayerActionMenu(BuildContext context, TarotGameLogic l, Player targetPlayer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("INTERAGIR AVEC ${targetPlayer.name.toUpperCase()}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.amber),
              title: const Text("Offrir une boisson / cadeau (50 jetons)", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                l.sendGiftToPlayer(targetPlayer.id, "boisson");
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cadeau envoyé à ${targetPlayer.name} !")));
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_problem, color: Colors.redAccent),
              title: const Text("Signaler un abus / triche", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _showReportDialog(context, l, targetPlayer);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context, TarotGameLogic l, Player targetPlayer) {
    String reason = "Triche / Comportement suspect";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("Signaler ${targetPlayer.name}", style: const TextStyle(color: Colors.redAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Sélectionne le motif du signalement :", style: TextStyle(color: Colors.white70)),
            DropdownButton<String>(
              dropdownColor: Colors.black,
              value: reason,
              isExpanded: true,
              items: ["Triche / Comportement suspect", "Pseudo inapproprié", "Photo offensante", "Anti-jeu"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white))))
                  .toList(),
              onChanged: (val) { if (val != null) reason = val; },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANNULER")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              l.reportPlayer(targetPlayer.id, reason);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signalement transmis aux modérateurs.")));
            },
            child: const Text("ENVOYER"),
          )
        ],
      ),
    );
  }

  void _showQuickInteractionMenu(BuildContext context, TarotGameLogic l) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 200,
        child: Column(
          children: [
            const Text("MESSAGES RAPIDES & EMOJIS", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ["👋 Bonjour", "👏 bien joué", "😅 Désolé", "🔥 GG"].map((msg) => ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                onPressed: () {
                  l.sendQuickMessage(msg);
                  Navigator.pop(ctx);
                },
                child: Text(msg, style: const TextStyle(color: Colors.white)),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(Player p, bool a, TarotGameLogic l, BuildContext context) {
    double rT = l.remainingTime.toDouble();
    Color cColor = rT > 5 ? Colors.green : (rT > 2 ? Colors.orange : Colors.red);
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    bool isMe = p.id == myIdx;

    String? avatarUrl = p.avatarUrl;
    String displayName = p.name;

    if (isMe) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user?.userMetadata != null) {
        avatarUrl = (user!.userMetadata!['avatar_url'] as String?) ?? avatarUrl;
        if (displayName == "MOI" || displayName == "J1" || displayName.isEmpty) {
          displayName = (user.userMetadata!['display_name'] ?? user.userMetadata!['full_name'] ?? displayName) as String;
        }
      }
    }

    String? currentBidText;
    if (l.lastBidsAnnounced.containsKey(p.id)) {
      final bidData = l.lastBidsAnnounced[p.id]!;
      final DateTime bidTime = bidData['time'] as DateTime;
      if (DateTime.now().difference(bidTime).inSeconds < 5) {
        currentBidText = bidData['text'] as String;
      }
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        SizedBox(
          width: 70, 
          height: 70, 
          child: CircularProgressIndicator(
            value: a ? (rT / 20.0).clamp(0.0, 1.0) : 0.0, 
            strokeWidth: 4, 
            color: cColor, 
            backgroundColor: Colors.white.withValues(alpha: 0.1)
          ),
        ),
        if (l.takerId == p.id && l.currentState != GameState.bidding && l.currentState != GameState.idle) const Positioned(bottom: -5, right: -5, child: Icon(Icons.star, color: Colors.amber, size: 24)),
        if (l.revealedPartnerId == p.id && l.currentState != GameState.bidding) const Positioned(bottom: -5, right: -5, child: Icon(Icons.colorize, color: Colors.redAccent, size: 22)),
        GestureDetector(
          onTap: () {
            if (isMe) {
              l.toggleZoom();
            } else {
              _showPlayerActionMenu(context, l, p);
            }
          },
          child: Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isMe ? Colors.blueAccent : const Color(0xFFD4AF37), width: 2.0)
            ),
            child: ClipOval(
              child: Container(
                color: Colors.black.withValues(alpha: 0.92),
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => _fallbackContent(displayName, isMe))
                  : _fallbackContent(displayName, isMe)
              )
            )
          ),
        )
      ]),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: isMe ? () => _showEditNameDialog(context, l, p) : null,
        child: SizedBox(
          width: 70, 
          child: Text(
            displayName.toUpperCase(), 
            textAlign: TextAlign.center, 
            overflow: TextOverflow.ellipsis, 
            style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)
          )
        ),
      ),

      if (currentBidText != null) ...[
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: currentBidText == "PASSE" ? Colors.red.shade900.withValues(alpha: 0.9) : Colors.amber.shade800.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white30, width: 0.8),
          ),
          child: Text(
            currentBidText,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ]);
  }

  Widget _fallbackContent(String name, bool isMe) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        if (isMe)
          const Positioned(bottom: 2, child: Icon(Icons.edit, size: 10, color: Colors.white54)),
      ],
    );
  }

  Widget _tableCards(TarotGameLogic l) {
    if (l.players.isEmpty) return const SizedBox.shrink();
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
   
    return ValueListenableBuilder<int>(valueListenable: _tableZoomLevel, builder: (context, zoomStep, child) {
      double scale = 1.0 + (zoomStep * 0.3);
      return GestureDetector(onTap: () => _tableZoomLevel.value = (_tableZoomLevel.value + 1) % 4, child: AnimatedScale(scale: scale, duration: const Duration(milliseconds: 250), curve: Curves.easeOutBack, child: Align(alignment: Alignment.center, child: SizedBox(width: 350, height: 350, child: Stack(alignment: Alignment.center, children: List.generate(l.players.length, (visualPos) {
        
        int realPId = (visualPos + myIdx) % l.players.length;
        
        CardModel? cardPlayed;
        for (var entry in l.currentTrickData) {
          if (entry.containsKey(realPId)) {
            cardPlayed = entry[realPId];
            break;
          }
        }

        if (cardPlayed == null) return const SizedBox.shrink();

        double dx = 0.0, dy = 0.0, rot = 0.0;
       
        if (l.players.length == 5) {
          switch (visualPos) {
            case 0: dx = 0.0; dy = 45.0; break;
            case 1: dx = 65.0; dy = 15.0; rot = -math.pi/3; break;
            case 2: dx = 40.0; dy = -50.0; rot = math.pi/6; break;
            case 3: dx = -40.0; dy = -50.0; rot = -math.pi/6; break;
            case 4: dx = -65.0; dy = 15.0; rot = math.pi/3; break;
          }
        } else if (l.players.length == 4) {
          switch (visualPos) {
            case 0: dx = 0.0; dy = 45.0; break;
            case 1: dx = 65.0; dy = 0.0; rot = -math.pi/2; break;
            case 2: dx = 0.0; dy = -45.0; break;
            case 3: dx = -65.0; dy = 0.0; rot = math.pi/2; break;
          }
        } else {
          switch (visualPos) {
            case 0: dx = 0.0; dy = 45.0; break;
            case 1: dx = 55.0; dy = -35.0; rot = -math.pi/4; break;
            case 2: dx = -55.0; dy = -35.0; rot = math.pi/4; break;
          }
        }
       
        return Transform.translate(offset: Offset(dx, dy), child: Transform.rotate(angle: rot, child: TarotCardWidget(card: cardPlayed, isHuman: true, isPlayable: true, width: 63.25)));
      }))))));
    });
  }

  Widget _bidding(TarotGameLogic l) => Center(child: Container(width: 500, margin: const EdgeInsets.only(bottom: 50), child: Column(mainAxisSize: MainAxisSize.min, children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [_btn(l, BidType.petite, "PETITE"), const SizedBox(width: 15), _btn(l, BidType.garde, "GARDE"), const SizedBox(width: 15), _btn(l, BidType.gardeSans, "G. SANS")]), const SizedBox(height: 15), Row(mainAxisAlignment: MainAxisAlignment.center, children: [_btn(l, BidType.gardeContre, "G. CONTRE"), const SizedBox(width: 15), _btn(l, null, "CHELEM", c: true), const SizedBox(width: 15), _btn(l, BidType.pass, "PASSER", p: true)])])));
 
  Widget _btn(TarotGameLogic l, dynamic t, String lb, {bool p = false, bool c = false}) {
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: p ? Colors.red.shade900 : (c ? Colors.deepPurple.shade700 : Colors.amber), foregroundColor: (p || c) ? Colors.white : Colors.black, elevation: 5), onPressed: () => (l.currentPlayerIndex != myIdx) ? null : (c ? null : l.makeBid(t)), child: Text(lb, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)));
  }

  Widget _chienEcart(TarotGameLogic l) => LayoutBuilder(builder: (c, constraints) {
    double dw = constraints.maxWidth * 0.085;
    
    bool isGardeSansOrContre = l.selectedBid == BidType.gardeSans || l.selectedBid == BidType.gardeContre;

    if (l.cardsRevealed && l.currentState == GameState.dogRevealed && !isGardeSansOrContre) {
      return Align(
        alignment: const Alignment(0.0, -0.15),
        child: Row(
          mainAxisSize: MainAxisSize.min, 
          children: l.chien.map((cd) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6), 
            child: TarotCardWidget(card: cd, isHuman: true, isPlayable: true, width: dw)
          )).toList()
        ),
      );
    }
    
    int myIdx = l.isMultiplayer ? l.myMultiplayerSide : 0;
    bool isMyEcart = (l.takerId == myIdx) || (l.bidTakerId == myIdx.toString());

    if (l.currentState == GameState.discarding && isMyEcart && !isGardeSansOrContre) {
      return Align(
        alignment: const Alignment(0.0, -0.22),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Row(
              mainAxisSize: MainAxisSize.min, 
              children: List.generate(l.players.length == 5 ? 3 : 6, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6), 
                child: SizedBox(
                  width: dw, 
                  height: dw * 1.63, 
                  child: i < l.currentEcartVisual.length 
                    ? GestureDetector(onTap: () => l.handleDiscardClick(l.currentEcartVisual[i]), child: TarotCardWidget(card: l.currentEcartVisual[i], isHuman: true, width: dw)) 
                    : Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.black.withValues(alpha: 0.38), border: Border.all(color: Colors.amber.withValues(alpha: 0.2), width: 1.5)), child: const Center(child: Icon(Icons.add, color: Colors.white12)))
                )
              ))
            ), 
            const SizedBox(height: 25), 
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: l.isEcartValid ? Colors.orange.shade800 : Colors.grey.shade900, 
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18)
              ), 
              onPressed: l.isEcartValid ? () => l.validateDiscard() : null, 
              child: const Text("VALIDER L'ÉCART", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))
            )
          ]
        ),
      );
    }
    return const SizedBox.shrink();
  });

  Widget _kingPicker(TarotGameLogic l) => Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CardSuit.coeur, CardSuit.carreau, CardSuit.pique, CardSuit.trefle].map((s) => GestureDetector(onTap: () => l.selectCalledKing(s), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 2), borderRadius: BorderRadius.circular(10)), child: Image.asset("assets/images/cards/Roi de ${s.toString().split('.').last[0].toUpperCase()}${s.toString().split('.').last.substring(1)}.png", width: 77, height: 125, fit: BoxFit.fill))))).toList()));
 
  String _sym(dynamic s) {
    switch (s) {
      case CardSuit.coeur: return "♥";
      case CardSuit.carreau: return "♦";
      case CardSuit.pique: return "♠";
      case CardSuit.trefle: return "♣";
      default: return "";
    }
  }
 
  Widget _announcement(String m) => Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 14), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(40)), child: Text(m, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16))));
}

class TarotCardWidget extends StatelessWidget {
  final CardModel card;
  final bool isHuman, isPlayable;
  final double width;
  final bool showFrame;
  const TarotCardWidget({super.key, required this.card, this.isHuman = false, this.isPlayable = true, this.width = 95, this.showFrame = true});
 
  @override
  Widget build(BuildContext context) {
    final l = Provider.of<TarotGameLogic>(context);
    
    // 🔒 MODIFICATION VISUELLE : Si la carte n'est pas jouable, on réduit sa luminosité (effet grisé/flouté)
    final double lum = isPlayable ? 1.0 : 0.4;
    
    final List<double> matrix = <double>[
      lum, 0.0, 0.0, 0.0, 0.0,
      0.0, lum, 0.0, 0.0, 0.0,
      0.0, 0.0, lum, 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    return Container(
      decoration: showFrame
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.54), blurRadius: 4, offset: const Offset(2, 2))]
            )
          : BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: Image.asset(
            (isHuman || l.cardsRevealed) ? card.assetPath : "assets/images/card_back_dark.png",
            width: width,
            height: width * 1.63,
            fit: BoxFit.fill
          ),
        ),
      ),
    );
  }
}
