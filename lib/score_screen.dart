import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'logic.dart' as rules;

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Provider.of<rules.TarotGameLogic>(context);
    final size = MediaQuery.of(context).size;
    
    final int currentLocalId = logic.isMultiplayer 
        ? logic.myMultiplayerSide 
        : ((logic.players.isNotEmpty) ? logic.players.first.id : 0);
    
    final bool win = (logic.sessionScores[currentLocalId] ?? 0.0) >= 0;

    final int totalHistory = logic.historyManches.length;
    final int displayManche = logic.currentManche > totalHistory 
        ? logic.currentManche 
        : (totalHistory == 0 ? 1 : totalHistory);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "MANCHE $displayManche / 3",
                  style: const TextStyle(
                    color: Colors.amber, 
                    fontSize: 20, 
                    fontWeight: FontWeight.bold
                  ),
                ),
                const SizedBox(height: 8),
                _buildGothicTitle(win),
                const SizedBox(height: 12),
                
                SizedBox(
                  height: 120,
                  child: Center(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: logic.players.length,
                      itemBuilder: (context, index) {
                        final p = logic.players[index];
                        final score = logic.sessionScores[p.id] ?? 0.0;
                        return _buildNeonCard(p, index, score);
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),

                Container(
                  constraints: BoxConstraints(
                    maxHeight: size.height * 0.52,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: _buildDetailedHistoryContent(context, logic, size.width),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                (!logic.isMultiplayer || logic.isHost)
                    ? _buildActionBtn(context, logic, displayManche) 
                    : _buildWaitingText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedHistoryContent(BuildContext context, rules.TarotGameLogic logic, double screenWidth) {
    final reversedManches = logic.historyManches.reversed.toList();
    final bool isMobile = screenWidth < 700;

    if (reversedManches.isEmpty) {
      return const Center(
        child: Text(
          "Aucun historique pour le moment.\nTerminez au moins une manche !",
          style: TextStyle(color: Colors.white70, fontSize: 16, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: reversedManches.length,
      itemBuilder: (context, index) {
        final manche = reversedManches[index];
        final int originalIndex = logic.historyManches.length - 1 - index;
        final int numManche = manche['manche'] ?? (originalIndex + 1);
        
        final String contratBrut = (manche['contrat'] ?? 'PETITE').toString().toUpperCase();
        final int? takerId = manche['taker_id'];
        final int? partnerId = manche['partner_id'] ?? logic.partnerId;

        final Map<String, dynamic> gains = Map<String, dynamic>.from(manche['gains'] ?? {});
        final Map<String, dynamic> poignees = Map<String, dynamic>.from(manche['poignees'] ?? {});

        int mult = 1;
        if (contratBrut.contains('GARDE') && contratBrut.contains('SANS')) {
          mult = 4;
        } else if (contratBrut.contains('GARDE') && contratBrut.contains('CONTRE')) {
          mult = 6;
        } else if (contratBrut.contains('GARDE')) {
          mult = 2;
        }

        List<Player> attackers = logic.players.where((p) => p.id == takerId || p.id == partnerId).toList();
        List<Player> defenders = logic.players.where((p) => p.id != takerId && p.id != partnerId).toList();
        List<Player> orderedPlayers = [...attackers, ...defenders];

        double totalAttackTricks = 0.0;
        double totalDefenseTricks = 0.0;
        int boutsCount = 0;

        if (manche.containsKey('attack_points') && manche.containsKey('defense_points')) {
          totalAttackTricks = (manche['attack_points'] as num).toDouble();
          totalDefenseTricks = (manche['defense_points'] as num).toDouble();
          boutsCount = manche['bouts_count'] ?? 0;
        } else {
          for (var p in logic.players) {
            double pPts = 0.0;
            for (var c in p.tricksWon) {
              pPts += c.points;
            }
            if (p.id == takerId || (partnerId != null && p.id == partnerId)) {
              totalAttackTricks += pPts;
              boutsCount += p.tricksWon.where((c) => c.isBout).length;
            } else {
              totalDefenseTricks += pPts;
            }
          }
        }

        double pointsRequis = boutsCount == 3 ? 36.0 : (boutsCount == 2 ? 41.0 : (boutsCount == 1 ? 51.0 : 56.0));

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Text(
                  "Tableau - Manche $numManche",
                  style: const TextStyle(
                    color: Color(0xFFD4AF37), 
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Padding(
                padding: EdgeInsets.only(left: isMobile ? 110 : 140),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: orderedPlayers.map((p) {
                    return SizedBox(
                      width: isMobile ? 55 : 75,
                      child: Center(
                        child: _buildAvatarColumn(p, takerId, partnerId, gains),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 8),
              const Divider(color: Color(0xFF333333), height: 1),
              const SizedBox(height: 6),

              _buildGridRow("Points faits", orderedPlayers, isMobile, (p) {
                bool isAttacker = p.id == takerId || p.id == partnerId;
                double pts = isAttacker ? totalAttackTricks : totalDefenseTricks;
                return "${pts.toStringAsFixed(1)} pts";
              }),
              _buildGridRow("Écart", orderedPlayers, isMobile, (p) {
                double ecartPts = 0.0;
                if (manche.containsKey('ecart_archive') && manche['ecart_archive'] is List) {
                  for (var c in manche['ecart_archive']) {
                    if (c is Map && c.containsKey('pts')) {
                      ecartPts += (c['pts'] as num).toDouble();
                    }
                  }
                } else {
                  ecartPts = logic.currentEcartVisual.fold(0.0, (sum, c) => sum + c.points);
                }

                return (p.id == takerId || p.id == partnerId) ? "${ecartPts.toStringAsFixed(1)} pts" : "-";
              }),
              _buildGridRow("Bouts", orderedPlayers, isMobile, (p) {
                return (p.id == takerId || p.id == partnerId) ? "$boutsCount (${pointsRequis.toStringAsFixed(1)})" : "-";
              }),
              _buildGridRow("Contrat", orderedPlayers, isMobile, (p) {
                return (p.id == takerId || p.id == partnerId) ? "+25" : "-";
              }),
              _buildGridRow("Enchère", orderedPlayers, isMobile, (p) {
                return (p.id == takerId || p.id == partnerId) ? "x$mult" : "-";
              }),

              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _buildGridRow("Chelem", orderedPlayers, isMobile, (p) {
                      final String chelemVal = manche['chelem']?[p.id.toString()] ?? '-';
                      return chelemVal;
                    }),
                    const SizedBox(height: 2),
                    _buildGridRow("Petit au bout", orderedPlayers, isMobile, (p) {
                      final String petitVal = manche['petit_au_bout']?[p.id.toString()] ?? '-';
                      return petitVal;
                    }),
                    const SizedBox(height: 2),
                    _buildGridRow("Poignées", orderedPlayers, isMobile, (p) {
                      return poignees.containsKey(p.id.toString()) ? poignees[p.id.toString()]! : "-";
                    }),
                  ],
                ),
              ),

              _buildGridRow("Fin du tour", orderedPlayers, isMobile, (p) {
                final double gain = double.tryParse(gains[p.id.toString()]?.toString() ?? '0') ?? 0.0;
                return "${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} pts";
              }, isHighlighted: true),
              const SizedBox(height: 4),
              _buildGridRow("Total cumulé", orderedPlayers, isMobile, (p) {
                final double total = logic.sessionScores[p.id] ?? 0.0;
                return "${total > 0 ? '+' : ''}${total.toStringAsFixed(1)} pts";
              }, isHighlighted: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatarColumn(Player p, int? takerId, int? partnerId, Map<String, dynamic> gains) {
    bool isTaker = p.id == takerId;
    bool isPartner = p.id == partnerId;
    final double gain = double.tryParse(gains[p.id.toString()]?.toString() ?? '0') ?? 0.0;
    bool isPositive = gain >= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isTaker ? Colors.amber : (isPartner ? Colors.redAccent : const Color(0xFFD4AF37)),
                  width: (isTaker || isPartner) ? 2.0 : 1.0,
                ),
              ),
              child: ClipOval(
                child: (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
                    ? Image.network(p.avatarUrl!, fit: BoxFit.cover, errorBuilder: (c, e, s) => _fallbackModalAvatarText(p.name))
                    : _fallbackModalAvatarText(p.name),
              ),
            ),
            if (isTaker)
              const Positioned(bottom: -3, right: -3, child: Icon(Icons.star, color: Colors.amber, size: 12)),
            if (isPartner)
              const Positioned(bottom: -3, right: -3, child: Icon(Icons.colorize, color: Colors.redAccent, size: 10)),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 55,
          child: Text(
            p.name,
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        Text(
          "${isPositive ? '+' : ''}${gain.toStringAsFixed(1)}",
          style: TextStyle(
            color: isPositive ? Colors.greenAccent : Colors.orangeAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGridRow(String label, List<Player> orderedPlayers, bool isMobile, String Function(Player) valueExtractor, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: isMobile ? 110 : 140,
            child: Text(
              label,
              style: TextStyle(
                color: isHighlighted ? Colors.amber : Colors.white70, 
                fontSize: isMobile ? 14 : 16, 
                fontWeight: FontWeight.bold
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: orderedPlayers.map((p) {
                return SizedBox(
                  width: isMobile ? 55 : 75,
                  child: Text(
                    valueExtractor(p),
                    style: TextStyle(
                      color: isHighlighted ? Colors.amberAccent : Colors.white, 
                      fontSize: isMobile ? 15 : 18, 
                      fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.bold
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackModalAvatarText(String name) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildGothicTitle(bool win) => Text(
    win ? "VICTOIRE" : "DÉFAITE",
    style: TextStyle(
      color: win ? Colors.amber : Colors.redAccent, 
      fontSize: 32, 
      fontWeight: FontWeight.w900, 
      letterSpacing: 3
    ),
  );

  Widget _buildNeonCard(Player p, int i, double score) {
    final List<Color> neonColors = [
      Colors.purpleAccent, 
      Colors.cyanAccent, 
      Colors.pinkAccent, 
      Colors.orangeAccent, 
      Colors.blueAccent
    ];
    Color c = neonColors[i % neonColors.length];

    return Container(
      width: 100,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c, width: 2),
        color: const Color(0xFF111111),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              p.name, 
              style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.bold), 
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "${score > 0 ? '+' : ''}${score.toStringAsFixed(1)}", 
            style: TextStyle(
              color: score >= 0 ? Colors.greenAccent : Colors.redAccent, 
              fontSize: 22, 
              fontWeight: FontWeight.w900
            )
          ),
          const Text(
            "PTS", 
            style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(BuildContext context, rules.TarotGameLogic l, int currentDisplayManche) => ElevatedButton(
    onPressed: () {
      if (currentDisplayManche >= 3 || l.currentManche >= 3) {
        l.fullResetForExit();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      } else {
        l.nextManche();
      }
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.amber, 
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
    ),
    child: Text(
      (currentDisplayManche >= 3 || l.currentManche >= 3) ? "FIN DE PARTIE" : "MANCHE SUIVANTE", 
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)
    ),
  );

  Widget _buildWaitingText() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white12),
      borderRadius: BorderRadius.circular(20),
      color: Colors.white.withOpacity(0.02),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
        ),
        SizedBox(width: 12),
        Text(
          "EN ATTENTE DE L'HÔTE...", 
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)
        ),
      ],
    ),
  );
}
