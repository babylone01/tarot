import 'package:supabase_flutter/supabase_flutter.dart';
import 'token_manager.dart';

class JetonsService {
  final _supabase = Supabase.instance.client;

  // Récupérer le solde actuel de jetons du joueur connecté via le TokenManager
  Future<int> getSoldeJetons() async {
    return await TokenManager.getBalance();
  }

  // Réclamer le bonus quotidien (Cycle de 7 jours)
  Future<Map<String, dynamic>> reclamerBonusQuotidien() async {
    return await TokenManager.claimDailyBonus();
  }

  // Réclamer les 2000 jetons quotidiens VIP (Abonnement)
  Future<Map<String, dynamic>> reclamerJetonsVip() async {
    try {
      final response = await _supabase.rpc('reclamer_jetons_vip');
      return {
        'success': true,
        'jetons_gagnes': response['jetons_gagnes'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(), // Ex: "Aucun abonnement VIP actif" ou "Déjà réclamé"
      };
    }
  }
}
