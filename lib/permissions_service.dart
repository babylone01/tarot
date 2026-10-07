import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'geo_service.dart';

class PermissionsService {
  /// 1. Demande de NOTIFICATION (Après la 1ère partie = 3 manches)
  static Future<bool> checkAndSuggestNotificationsAfterFirstGame(
    BuildContext context, 
    int totalGamesPlayed,
  ) async {
    if (totalGamesPlayed != 1) return false;

    PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) return true;

    bool? shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.amber),
            SizedBox(width: 10),
            Text("Ne manque aucun tour !", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          "Bravo pour ta première partie !\n\n"
          "Active les notifications pour être alerte quand c'est à ton tour de jouer en multijoueur, "
          "et pour ne pas rater les annonces de tournois et d'événements.",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Plus tard", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Activer", 
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      PermissionStatus result = await Permission.notification.request();
      if (result.isPermanentlyDenied && context.mounted) {
        _showSettingsDialog(context, "Notifications");
      }
      return result.isGranted;
    }

    return false;
  }

  /// 2. Demande de GÉOLOCALISATION (Après 3 parties = 9 manches)
  static Future<bool> checkAndSuggestSocialTarot(
    BuildContext context, 
    int totalGamesPlayed,
  ) async {
    if (totalGamesPlayed != 3) return false;

    PermissionStatus status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;

    bool? shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.amber),
            SizedBox(width: 10),
            Text("Découvre le Tarot Social", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          "Tu as déjà 3 parties à ton actif !\n\n"
          "En activant la localisation, tu débloques le Tarot Social : "
          "vois la distance qui te sépare des autres joueurs autour de chez toi et rejoins les tables de ta région.\n\n"
          "🔒 Ta position exacte ne sera jamais révélée (seule la distance en km est affichée).",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Plus tard", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Activer le GPS", 
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldRequest == true && context.mounted) {
      return await GeoService.requestLocationPermission(context);
    }

    return false;
  }

  /// 3. Partage natif vers les amis
  static Future<void> shareAppWithFriends() async {
    const String shareMessage =
        "Rejoins-moi sur Tarot Gothic ! Viens jouer au Tarot à 5 en ligne. "
        "Télécharge l'application ici : https://play.google.com/store/apps/details?id=com.tarot.gothic";

    await Share.share(
      shareMessage,
      subject: "Partie de Tarot à 5",
    );
  }

  static void _showSettingsDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("$feature désactivées", style: const TextStyle(color: Colors.white)),
        content: Text(
          "L'autorisation pour $feature est actuellement bloquée dans les paramètres de ton téléphone.\n\n"
          "Souhaites-tu ouvrir les paramètres pour l'activer ?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text("Paramètres", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
