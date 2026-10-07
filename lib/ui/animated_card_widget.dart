import 'package:flutter/material.dart';
import '../models.dart';
import '../audio_service.dart';

class AnimatedCardWidget extends StatefulWidget {
  final CardModel card;
  final bool isPlayable;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const AnimatedCardWidget({
    super.key,
    required this.card,
    required this.isPlayable,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  State<AnimatedCardWidget> createState() => _AnimatedCardWidgetState();
}

class _AnimatedCardWidgetState extends State<AnimatedCardWidget> {
  bool _isExiting = false;

  void _handleTap() {
    if (!widget.isPlayable || _isExiting) return;

    // Bruitage de la carte posée (respecte isSfxEnabled sans couper la musique)
    AudioService.instance.playSfx('sounds/card_play.mp3');

    setState(() {
      _isExiting = true; // Déclenche l'éjection automatique vers le haut
    });

    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      top: _isExiting ? -200 : 0, // Envoie la carte 200px vers le haut
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _isExiting ? 0.0 : (widget.isPlayable ? 1.0 : 0.4), // Floutage si non jouable
        onEnd: () {
          if (_isExiting) {
            // 🔒 NETTOYAGE MÉMOIRE ABSOLU : Supprime l'élément dès l'animation terminée
            widget.onDismissed();
          }
        },
        child: GestureDetector(
          onTap: _handleTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              border: widget.isPlayable
                  ? Border.all(color: Colors.amber, width: 1.5)
                  : Border.all(color: Colors.transparent),
            ),
            child: Image.asset(
              widget.card.assetPath,
              width: 70,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
