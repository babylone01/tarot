import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../logic.dart';

class TarotTable extends StatelessWidget {
  final int playerCount;
  const TarotTable({super.key, required this.playerCount});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // SÉCURITÉ ANTI-SPAM : On n'utilise plus de Consumer global.
    // L'arborescence de base reste fixe et ne subit plus les secousses du timer.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/menu_bg.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: size.width * 0.85,
                height: size.height * 0.75,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/table_tapis.png"),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            // On injecte les positions gérées par des écouteurs isolés
            ..._buildPlayerPositions(context, size),
            const Center(child: GameBoardContent()),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPlayerPositions(BuildContext context, Size size) {
    // On récupère uniquement les infos structurelles indispensables
    final logic = Provider.of<TarotGameLogic>(context, listen: false);
    final int count = context.select<TarotGameLogic, int>((l) => l.players.length);
    final int myIdx = context.select<TarotGameLogic, int>((l) => l.isMultiplayer ? l.myMultiplayerSide : 0);
    
    if (count == 0) return [];

    return List.generate(count, (index) {
      // CORRECTION DU POSITIONNEMENT MULTIJOUEUR :
      // On calcule la position visuelle relativement à la place du joueur local (myIdx)
      // pour que l'utilisateur connecté se retrouve TOUJOURS en bas de l'écran.
      final int visualPos = (index - myIdx + count) % count;

      final double angle = (visualPos * 2 * math.pi / count) + (math.pi / 2);
      final double x = (size.width / 2) + (size.width * 0.38) * math.cos(angle) - 45;
      final double y = (size.height / 2) + (size.height * 0.28) * math.sin(angle) - 45;
      
      return Positioned(
        left: x,
        top: y,
        child: PlayerWidget(playerIndex: index),
      );
    });
  }
}

class GameBoardContent extends StatelessWidget {
  const GameBoardContent({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        image: const DecorationImage(
          image: AssetImage("assets/images/card_back_dark.png"),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class PlayerWidget extends StatelessWidget {
  final int playerIndex;
  const PlayerWidget({super.key, required this.playerIndex});

  @override
  Widget build(BuildContext context) {
    // SÉCURITÉ ANTI-SPAM INTERNE : Chaque widget de joueur écoute uniquement 
    // ses propres données et l'identité du preneur.
    final playerExists = context.select<TarotGameLogic, bool>((l) => l.players.length > playerIndex);
    if (!playerExists) return const SizedBox.shrink();

    final player = context.select<TarotGameLogic, dynamic>((l) => l.players[playerIndex]);
    final int? takerId = context.select<TarotGameLogic, int?>((l) => l.takerId);
    
    double winRate = 0.0;
    final bool isTaker = takerId == player.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isTaker ? Colors.redAccent : Colors.transparent,
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 35,
            backgroundColor: const Color(0xFF1A1A1A),
            backgroundImage: AssetImage("assets/images/avatars/${player.id}.png"),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          player.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        Text(
          "${winRate.toStringAsFixed(1)}%",
          style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 10),
        ),
      ],
    );
  }
}
