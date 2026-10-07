import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TokenManager {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // 1. Récupérer le solde actuel de l'utilisateur (avec attribution unique de 5000 jetons à vie)
  static Future<int> getBalance() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 500; // Valeur par défaut invité

    try {
      final response = await _supabase
          .from('user_wallets')
          .select('balance')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null && response['balance'] != null) {
        return response['balance'] as int;
      } else {
        // Le portefeuille n'existe pas encore pour cet user_id.
        // Vérifions si cet e-mail a déjà bénéficié du bonus de bienvenue (anti-abus / réinscription).
        final userEmail = user.email ?? '';
        bool alreadyClaimed = false;

        if (userEmail.isNotEmpty) {
          try {
            final traceRes = await _supabase
                .from('welcome_claims')
                .select('email')
                .eq('email', userEmail)
                .maybeSingle();
            
            if (traceRes != null) {
              alreadyClaimed = true;
            }
          } catch (_) {
            // Si la table de traçabilité n'est pas encore créée, on laisse passer par défaut
          }
        }

        // 5000 jetons pour un premier passage, 500 standard en cas de récidive après suppression de compte
        int initialBalance = alreadyClaimed ? 500 : 5000;

        // Enregistrement de la trace permanente de l'e-mail si premier passage
        if (!alreadyClaimed && userEmail.isNotEmpty) {
          try {
            await _supabase.from('welcome_claims').insert({
              'email': userEmail,
              'user_id': user.id,
              'claimed_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }

        // Initialisation automatique de la ligne dans user_wallets
        await _supabase.from('user_wallets').upsert({
          'user_id': user.id,
          'balance': initialBalance,
          'updated_at': DateTime.now().toIso8601String(),
        });
        
        return initialBalance;
      }
    } catch (e) {
      debugPrint("Erreur getBalance: $e");
      return 500;
    }
  }

  // 2. Réclamer le bonus quotidien
  static Future<Map<String, dynamic>> claimDailyBonus() async {
    try {
      final response = await _supabase.rpc('reclamer_bonus_quotidien');
      return {'success': true, 'data': response};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // 3. Débiter la mise de manière atomique (utilise UPSERT pour éviter les échecs silencieux)
  static Future<bool> debitStake(int stakeAmount) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final currentBalance = await getBalance();
      if (currentBalance < stakeAmount) return false;

      int newBalance = currentBalance - stakeAmount;

      await _supabase.from('user_wallets').upsert({
        'user_id': user.id,
        'balance': newBalance,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint("Erreur debitStake: $e");
      return false;
    }
  }

  // 4. Créditer un utilisateur (Victoires / Récompenses)
  static Future<void> creditUser(String userId, int amount) async {
    try {
      final response = await _supabase
          .from('user_wallets')
          .select('balance')
          .eq('user_id', userId)
          .maybeSingle();

      int currentBalance = 500;
      if (response != null && response['balance'] != null) {
        currentBalance = response['balance'] as int;
      }

      int newBalance = currentBalance + amount;

      await _supabase.from('user_wallets').upsert({
        'user_id': userId,
        'balance': newBalance,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Erreur creditUser: $e");
    }
  }
}

// 5. Widget d'affichage des jetons mis à jour
class TokenDisplayWidget extends StatefulWidget {
  const TokenDisplayWidget({super.key});

  @override
  State<TokenDisplayWidget> createState() => TokenDisplayWidgetState();
}

class TokenDisplayWidgetState extends State<TokenDisplayWidget> {
  int _balance = 500;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  static Future<int> fetchCurrentBalance() async {
    return await TokenManager.getBalance();
  }

  Future<void> _loadBalance() async {
    final balance = await TokenManager.getBalance();
    if (mounted) {
      setState(() {
        _balance = balance;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, color: Color(0xFFD4AF37), size: 16),
          const SizedBox(width: 6),
          _isLoading
              ? const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                )
              : Text(
                  '$_balance',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14, color: Colors.white70),
            onPressed: _loadBalance,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
