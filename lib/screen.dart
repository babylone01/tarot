import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logic.dart' as rules;

class TarotGameScreen extends StatelessWidget {
  const TarotGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final int currentManche = context.select<rules.TarotGameLogic, int>((l) => l.currentManche);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Center(
            child: Text(
              "PLATEAU DE JEU",
              style: TextStyle(color: Colors.white10, fontSize: 20),
            ),
          ),
          Positioned(
            bottom: 25.0,
            left: 25.0,
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                  width: 1.0,
                ),
              ),
              child: Text(
                "MANCHE : $currentManche",
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
