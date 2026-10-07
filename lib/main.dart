import 'dart:async';
import 'global.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

// Imports locaux
import 'package:tarot_app/logic.dart';
import 'package:tarot_app/models.dart';
import 'package:tarot_app/widgets.dart';
import 'package:tarot_app/multiplayer_manager.dart';
import 'package:tarot_app/remote_logger.dart';
import 'package:tarot_app/token_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RemoteLogger.send("INFO", "🎯 [ESPION_MAIN] Début de l'initialisation de l'application");
 
  try {
    await Supabase.initialize(
      url: 'https://ruixknekqinalyccxotp.supabase.co',
      anonKey: 'sb_publishable_srFEs1VmnrK-ThxZzR7kOQ_QPNnCQ-T',
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
    );
   
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      RemoteLogger.send("INFO", "🎯 [ESPION_MAIN] Session persistante détectée", {"id": session.user.id});
    } else {
      RemoteLogger.send("INFO", "🎯 [ESPION_MAIN] Aucune session active au démarrage");
    }
  } catch (e) {
    RemoteLogger.send("ERROR", "❌ [ESPION_MAIN] Erreur Supabase : $e");
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight
  ]);
 
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    ChangeNotifierProvider(
      create: (_) => TarotGameLogic(),
      child: const TarotApp(),
    ),
  );
}

// Gestionnaire global des paramètres audio
class AudioSettings extends ChangeNotifier {
  bool _isMusicEnabled = true;
  bool _isCardSoundEnabled = true;

  bool get isMusicEnabled => _isMusicEnabled;
  bool get isCardSoundEnabled => _isCardSoundEnabled;

  void toggleMusic(bool value, AudioPlayer player) async {
    _isMusicEnabled = value;
    notifyListeners();
    if (!_isMusicEnabled) {
      await player.pause();
    } else {
      await player.resume();
    }
  }

  void toggleCardSound(bool value) {
    _isCardSoundEnabled = value;
    notifyListeners();
  }
}

final AudioSettings globalAudioSettings = AudioSettings();

class TarotApp extends StatefulWidget {
  const TarotApp({super.key});
  @override 
  State<TarotApp> createState() => _TarotAppState();
}

class _TarotAppState extends State<TarotApp> {
  late bool _needsWebGate;
  bool _isLoading = true;
  final AudioPlayer _scaryMusicPlayer = AudioPlayer();
  StreamSubscription? _playerCompleteSubscription;
  bool _isLoopingTrackPlaying = false;

  @override
  void initState() {
    super.initState();
    _needsWebGate = true; // Force le clic utilisateur pour débloquer l'audio partout
  }

  // Séquence audio : Joue l'intro une fois, puis enchaîne sur la boucle infinie
  Future<void> _initAndPlayAudioSequence() async {
    try {
      _isLoopingTrackPlaying = false;
      await _scaryMusicPlayer.setReleaseMode(ReleaseMode.stop);
      await _scaryMusicPlayer.setSource(AssetSource('sounds/slice.mp3'));
      
      if (globalAudioSettings.isMusicEnabled) {
        await _scaryMusicPlayer.resume();
      }
      RemoteLogger.send("INFO", "🎵 [AUDIO] Lancement de l'intro audio");

      // Écoute de la fin de l'intro pour basculer sur la boucle infinie
      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = _scaryMusicPlayer.onPlayerComplete.listen((_) async {
        if (!_isLoopingTrackPlaying) {
          _isLoopingTrackPlaying = true;
          try {
            await _scaryMusicPlayer.setSource(AssetSource('sounds/halloween_loop.mp3'));
            await _scaryMusicPlayer.setReleaseMode(ReleaseMode.loop);
            if (globalAudioSettings.isMusicEnabled) {
              await _scaryMusicPlayer.resume();
            }
            RemoteLogger.send("INFO", "🎵 [AUDIO] Passage à la piste en boucle infinie");
          } catch (e) {
            RemoteLogger.send("ERROR", "❌ [AUDIO] Erreur passage boucle : $e");
          }
        }
      });
    } catch (e) {
      RemoteLogger.send("ERROR", "❌ [AUDIO] Erreur de lecture de la séquence audio : $e");
    }
  }

  Future<void> _onWebGatePassed() async {
    // Demande explicite des permissions Android dès le premier clic sur le portail
    if (!kIsWeb) {
      try {
        await [
          Permission.camera,
          Permission.microphone,
          Permission.storage,
        ].request();
      } catch (e) {
        RemoteLogger.send("ERROR", "❌ [PERMISSIONS] Erreur demande : $e");
      }
    }

    setState(() {
      _needsWebGate = false;
    });
    
    _initAndPlayAudioSequence();
    
    // Double battement de sécurité pour stabiliser le focus audio sur mobile
    Future.delayed(const Duration(milliseconds: 500), () {
      if (globalAudioSettings.isMusicEnabled) {
        _scaryMusicPlayer.resume();
      }
    });
  }

  void _onSplashFinished() {
    RemoteLogger.send("INFO", "🎯 [ESPION_SPLASH] Fin de la vidéo de démarrage, transition vers le menu principal");
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _scaryMusicPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget activeHome;

    if (_needsWebGate) {
      activeHome = WebGateScreen(onEnter: _onWebGatePassed);
    } else if (_isLoading) {
      activeHome = ReaperVideoSplashScreen(onFinished: _onSplashFinished);
    } else {
      activeHome = MainMenu(musicPlayer: _scaryMusicPlayer);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tarot 2026',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFD4AF37),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1200),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: activeHome,
      ),
    );
  }
}

class WebGateScreen extends StatelessWidget {
  final VoidCallback onEnter;
  const WebGateScreen({super.key, required this.onEnter});

  @override
  Widget build(BuildContext context) {
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "TAROT GOTHIQUE",
                style: TextStyle(
                  color: Color(0xFFD4AF37),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'Almendra',
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: const Color(0xFFD4AF37),
                  side: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onEnter,
                child: const Text(
                  "ENTRER DANS LA CRYPTE",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontFamily: 'Almendra',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaperVideoSplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const ReaperVideoSplashScreen({super.key, required this.onFinished});

  @override
  State<ReaperVideoSplashScreen> createState() => _ReaperVideoSplashScreenState();
}

class _ReaperVideoSplashScreenState extends State<ReaperVideoSplashScreen> {
  late VideoPlayerController _controller;
  bool _isVideoReady = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    // Utilisation de mixWithOthers pour empêcher le lecteur vidéo de couper le son global sur Android
    _controller = VideoPlayerController.asset(
      'assets/reaper_3d/depart.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _isVideoReady = true;
      });
      _controller.setVolume(0.0); 
      _controller.play();
      
      _safetyTimer = Timer(const Duration(milliseconds: 5167), () {
        widget.onFinished();
      });
    }).catchError((error) {
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isVideoReady && _controller.value.isInitialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width > 0 ? _controller.value.size.width : 1280,
                    height: _controller.value.size.height > 0 ? _controller.value.size.height : 720,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  SizedBox(height: 20),
                  Text(
                    "CHARGEMENT DE LA FAUCHEUSE...",
                    style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, letterSpacing: 2),
                  ),
                ],
              ),
      ),
    );
  }
}

class MainMenu extends StatefulWidget {
  final AudioPlayer musicPlayer;
  const MainMenu({super.key, required this.musicPlayer});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  final ValueNotifier<String> _nameNotifier = ValueNotifier<String>("JOUEUR 1");
  final ValueNotifier<String> _avatarNotifier = ValueNotifier<String>("");
  StreamSubscription<AuthState>? _authSubscription;

  Timer? _autoLaunchTimer;
  int _secondsRemaining = 50;

  final List<Map<String, int>> _stakes = [
    {'stake': 200, 'pot': 300},
    {'stake': 500, 'pot': 700},
    {'stake': 1000, 'pot': 1500},
    {'stake': 2000, 'pot': 3000},
  ];

  int _selectedStakeIndex = 0;
  late final PageController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = PageController(initialPage: 0, viewportFraction: 0.85);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) _fetchUserData();
    });
    _fetchUserData();
    _startCountdown();
  }

  void _startCountdown() {
    _autoLaunchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _autoLaunchTimer?.cancel();
          _performAutoClick();
        }
      });
    });
  }

  void _performAutoClick() {
    if (!mounted) return;
    _autoLaunchTimer?.cancel();
    if (Supabase.instance.client.auth.currentUser != null) {
      int activeStake = _stakes[_selectedStakeIndex]['stake']!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(playerCount: 5, isOnline: true, stake: activeStake),
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoLaunchTimer?.cancel();
    _slideController.dispose();
    _authSubscription?.cancel();
    _nameNotifier.dispose();
    _avatarNotifier.dispose();
    super.dispose();
  }

  void _fetchUserData() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final name = user.userMetadata?['display_name'] ??
                   user.userMetadata?['full_name'] ??
                   user.email?.split('@')[0].toUpperCase() ??
                   "JOUEUR 1";
                   
      final avatar = user.userMetadata?['avatar_url'] ??
                     user.userMetadata?['picture'] ?? "";

      if (mounted) {
        setState(() {
          _nameNotifier.value = name;
          _avatarNotifier.value = avatar;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _nameNotifier.value = "INVITÉ";
          _avatarNotifier.value = "";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "LANCEMENT AUTO DANS $_secondsRemaining SECONDES",
                  style: TextStyle(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                    fontSize: 7,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),

            Positioned(
              top: 15,
              left: 20,
              child: ValueListenableBuilder<String>(
                valueListenable: _nameNotifier,
                builder: (context, name, child) {
                  return ValueListenableBuilder<String>(
                    valueListenable: _avatarNotifier,
                    builder: (context, avatarUrl, child) {
                      return GestureDetector(
                        onTap: () => _showEditNameDialog(context, name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFD4AF37), width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFFD4AF37),
                                    backgroundImage: (avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                                    child: avatarUrl.isEmpty
                                        ? CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Colors.black,
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : "J",
                                              style: const TextStyle(
                                                color: Color(0xFFD4AF37),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const CircleAvatar(
                                    radius: 5,
                                    backgroundColor: Colors.white,
                                    child: Icon(Icons.edit, size: 7, color: Colors.black),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                name.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
           
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "TAROT 2026",
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      width: 420,
                      height: 55,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: PageView.builder(
                          controller: _slideController,
                          itemCount: _stakes.length,
                          onPageChanged: (index) {
                            setState(() {
                              _selectedStakeIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            final stakeData = _stakes[index];
                            final bool isSelected = index == _selectedStakeIndex;
                            return Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.swipe, color: Colors.white54, size: 14),
                                  const SizedBox(width: 8),
                                  Text(
                                    "MISE : ${stakeData['stake']} JETONS",
                                    style: TextStyle(
                                      color: isSelected ? const Color(0xFFD4AF37) : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4AF37).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      "Pot: ${stakeData['pot']}",
                                      style: const TextStyle(
                                        color: Color(0xFFD4AF37),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSoloColumn(context, "LOCAL (SOLO)", [3, 4, 5]),
                        const SizedBox(width: 50),
                        _buildOnlineColumn(context, "EN LIGNE (SUPA)", [3, 4, 5]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
           
            Positioned(
              top: 15,
              right: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TokenDisplayWidget(),
                  const SizedBox(width: 10),
                  _googleBtn(context),
                  const SizedBox(width: 10),
                  _settingsBtn(context, widget.musicPlayer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, String currentName) {
    final TextEditingController controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (diagCtx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("MODIFIER MON PSEUDO",
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFD4AF37)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(diagCtx),
            child: const Text("ANNULER", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(data: {'display_name': newName})
                );
              }
              _fetchUserData();
              if (mounted) {
                Navigator.pop(diagCtx);
              }
            },
            child: const Text("VALIDER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSoloColumn(BuildContext context, String label, List<int> players) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
      const SizedBox(height: 15),
      ...players.map((n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: const Color(0xFFD4AF37),
              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
              minimumSize: const Size(180, 45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              _autoLaunchTimer?.cancel();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GameScreen(playerCount: n, isOnline: false, stake: 0),
                ),
              );
            },
            child: Text("$n JOUEURS", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
      )),
    ]);
  }

  Widget _buildOnlineColumn(BuildContext context, String label, List<int> players) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
      const SizedBox(height: 15),
      ...players.map((n) {
        int currentStake = _stakes[_selectedStakeIndex]['stake']!;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SizedBox(
            height: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                minimumSize: const Size(180, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                _autoLaunchTimer?.cancel();

                int balance = await TokenManager.getBalance();
                if (balance < currentStake) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Solde insuffisant pour cette mise !"),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                  return;
                }

                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(playerCount: n, isOnline: true, stake: currentStake),
                    ),
                  );
                }
              },
              child: Text("$n JOUEURS", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _googleBtn(BuildContext context) => InkWell(
    onTap: () async {
      final logic = Provider.of<TarotGameLogic>(context, listen: false);
      await logic.signInWithGoogle();
      if (!mounted) return;
      _fetchUserData();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4AF37)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_circle, color: Color(0xFFD4AF37), size: 18),
          SizedBox(width: 8),
          Text("GOOGLE", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );

  Widget _settingsBtn(BuildContext context, AudioPlayer player) => InkWell(
    onTap: () {
      showDialog(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("PARAMÈTRES AUDIO", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text("Musique ambiante", style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: globalAudioSettings.isMusicEnabled,
                  activeColor: const Color(0xFFD4AF37),
                  onChanged: (val) {
                    globalAudioSettings.toggleMusic(val, player);
                    setStateDialog(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text("Bruit des cartes", style: TextStyle(color: Colors.white, fontSize: 13)),
                  value: globalAudioSettings.isCardSoundEnabled,
                  activeColor: const Color(0xFFD4AF37),
                  onChanged: (val) {
                    globalAudioSettings.toggleCardSound(val);
                    setStateDialog(() {});
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text("FERMER", style: TextStyle(color: Color(0xFFD4AF37))),
              ),
            ],
          ),
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4AF37)),
      ),
      child: const Icon(Icons.settings, color: Color(0xFFD4AF37), size: 18),
    ),
  );
}

class GameScreen extends StatefulWidget {
  final int playerCount;
  final bool isOnline;
  final int stake;
  const GameScreen({super.key, required this.playerCount, required this.isOnline, required this.stake});
  @override 
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  MultiplayerManager? _multiManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final logic = Provider.of<TarotGameLogic>(context, listen: false);

      if (widget.isOnline) {
        if (widget.stake > 0) {
          await _debitStakeSupabase(widget.stake);
        }

        logic.lastBidName = "";
        _multiManager = MultiplayerManager(logic);
        _multiManager?.joinTable('salle_par_defaut');
        RemoteLogger.send("INFO", "Entrée Jeu Online avec mise", {"table_id": "salle_par_defaut", "stake": widget.stake});
      } else {
        logic.initGame(widget.playerCount, multi: false);
      }
    });
  }

  Future<void> _debitStakeSupabase(int stakeAmount) async {
    try {
      bool success = await TokenManager.debitStake(stakeAmount);
      if (success) {
        RemoteLogger.send("INFO", "💰 [MISE] Débit réussi de $stakeAmount jetons via TokenManager");
      } else {
        RemoteLogger.send("WARNING", "❌ [MISE] Échec du débit de la mise (solde insuffisant)");
      }
    } catch (e) {
      RemoteLogger.send("ERROR", "❌ [MISE] Erreur lors du débit de la mise : $e");
    }
  }

  @override
  void dispose() {
    _multiManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameState state = context.select<TarotGameLogic, GameState>((l) => l.currentState);
    final double time = context.select<TarotGameLogic, double>((l) => l.remainingTime);
    final String currentName = context.select<TarotGameLogic, String>((l) => l.players.isNotEmpty ? l.players[l.myMultiplayerSide].name : 'EN ATTENTE');

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: TarotTable(playerCount: widget.playerCount)),
         
          if (state == GameState.idle && widget.isOnline)
            Container(
              color: Colors.black.withValues(alpha: 0.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    const SizedBox(height: 30),
                    const Text(
                      "SYNCHRONISATION...",
                      style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "JOUEUR : $currentName",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 30),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: time / 30,
                            color: const Color(0xFFD4AF37),
                            backgroundColor: Colors.white10,
                            strokeWidth: 2,
                          ),
                        ),
                        Text(
                          "${time.toInt()}",
                          style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 32, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
         
          Positioned(
            top: 20,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Color(0xFFD4AF37), size: 30),
              onPressed: () async {
                if (!context.mounted) return;
                final logicProvider = Provider.of<TarotGameLogic>(context, listen: false);
               
                if (logicProvider.version != 0) {
                  try {
                    logicProvider.lastBidName = "";
                    logicProvider.fullResetForExit();
                  } catch(_) {}
                }

                _multiManager?.dispose();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
