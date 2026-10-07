import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool isMusicEnabled = true;
  bool isSfxEnabled = true;

  /// Initialisation globale de la session audio
  Future<void> initAudio() async {
    try {
      await _musicPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
        ),
      ));

      await _sfxPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
        ),
      ));

      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint("Erreur initAudio: $e");
    }
  }

  /// Musique de fond
  Future<void> playBackgroundMusic(String assetPath) async {
    if (!isMusicEnabled) return;
    try {
      if (_musicPlayer.state != PlayerState.playing) {
        await _musicPlayer.play(AssetSource(assetPath), volume: 0.5);
      }
    } catch (e) {
      debugPrint("Erreur playBackgroundMusic: $e");
    }
  }

  /// Bruitage de carte ou clic (stoppe si désactivé)
  Future<void> playSfx(String assetPath) async {
    if (!isSfxEnabled) return;

    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint("Erreur playSfx: $e");
    }
  }

  /// Interrupteur Musique
  Future<void> toggleMusic(bool enabled) async {
    isMusicEnabled = enabled;
    if (!isMusicEnabled) {
      await _musicPlayer.pause();
    } else {
      await _musicPlayer.resume();
    }
  }

  /// Interrupteur Bruitages
  void toggleSfx(bool enabled) {
    isSfxEnabled = enabled;
    if (!isSfxEnabled) {
      _sfxPlayer.stop();
    }
  }

  void dispose() {
    _musicPlayer.dispose();
    _sfxPlayer.dispose();
  }
}
