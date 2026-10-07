-- =========================================================================
-- 1. PURGE ET NETTOYAGE COMPLET (Ordre strict pour éviter les verrous de dépendance)
-- =========================================================================
DROP TRIGGER IF EXISTS tr_central_tarot ON public.table_tarot_5;
DROP TRIGGER IF EXISTS tr_global_manche_reset ON public.table_tarot_5;
DROP TRIGGER IF EXISTS tr_protect_tarot_sync ON public.table_tarot_5;

DROP FUNCTION IF EXISTS public.join_or_create_tarot_table(text, text, text);
DROP FUNCTION IF EXISTS public.distribue_tarot_cards(text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.central_tarot_orchestrator();
DROP FUNCTION IF EXISTS public.handle_next_manche_cleanup_vfinal();
DROP FUNCTION IF EXISTS public.protect_tarot_sync();
DROP FUNCTION IF EXISTS public.get_server_time();

DROP TABLE IF EXISTS public.table_tarot_5;

-- =========================================================================
-- 2. CRÉATION DE LA TABLE MAÎTRESSE : table_tarot_5
-- =========================================================================
CREATE TABLE public.table_tarot_5 (
    table_id TEXT PRIMARY KEY,
    game_status TEXT NOT NULL DEFAULT 'IDLE',
    version BIGINT NOT NULL DEFAULT 1,
    game_version INTEGER NOT NULL DEFAULT 1,
    
    -- Indexations techniques des appareils et chronos
    phone_index TEXT DEFAULT 'INIT',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_action_time TEXT,
    turn_ends_at TIMESTAMP WITH TIME ZONE,
    
    -- Paramétrages et métadonnées de la manche
    player_count INTEGER DEFAULT 5,
    current_manche INTEGER DEFAULT 1,
    dealer_index INTEGER DEFAULT 0,
    current_player_index INTEGER DEFAULT 0,
    current_bidder_index INTEGER DEFAULT 0,
    next_manche_ready BOOLEAN DEFAULT FALSE,
    
    -- États des Enchères et Contrats
    contrat TEXT,
    last_bid_name TEXT,
    bid_taker_id TEXT,
    partner_id TEXT,
    called_king INTEGER,
    
    -- Identifiants uniques et métadonnées des Joueurs
    player0_uid TEXT, player0_name TEXT, player0_avatar TEXT,
    player1_uid TEXT, player1_name TEXT, player1_avatar TEXT,
    player2_uid TEXT, player2_name TEXT, player2_avatar TEXT,
    player3_uid TEXT, player3_name TEXT, player3_avatar TEXT,
    player4_uid TEXT, player4_name TEXT, player4_avatar TEXT,
    
    -- Structures de cartes au format JSONB strict
    hands JSONB DEFAULT '{}'::jsonb,
    hand_0 JSONB DEFAULT '[]'::jsonb,
    hand_1 JSONB DEFAULT '[]'::jsonb,
    hand_2 JSONB DEFAULT '[]'::jsonb,
    hand_3 JSONB DEFAULT '[]'::jsonb,
    hand_4 JSONB DEFAULT '[]'::jsonb,
    chien JSONB DEFAULT '[]'::jsonb,
    current_trick JSONB DEFAULT '{}'::jsonb,
    cards_on_table JSONB DEFAULT '[]'::jsonb,
    pli_joueurs JSONB DEFAULT '{"0":[],"1":[],"2":[],"3":[],"4":[]}'::jsonb,
    scores JSONB DEFAULT '{}'::jsonb,
    
    -- Historiques et traces du dernier pli posé
    last_card_played TEXT,
    last_winner_index INTEGER,
    deck_hash TEXT
);

-- =========================================================================
-- 3. CRÉATION DES FONCTIONS DE TRIGGERS ESSENTIELS
-- =========================================================================

-- Trigger 1 : L'Orchestrateur Central (Gère l'alignement des versions et timestamps)
CREATE OR REPLACE FUNCTION public.central_tarot_orchestrator()
RETURNS TRIGGER AS $$
BEGIN
    -- Aligne les colonnes de versioning pour éviter tout désaccord avec Dart
    IF NEW.version IS DISTINCT FROM OLD.version THEN
        NEW.game_version := NEW.version::INT;
    ELSIF NEW.game_version IS DISTINCT FROM OLD.game_version THEN
        NEW.version := NEW.game_version::BIGINT;
    END IF;

    -- Gestion dynamique du timer (turn_ends_at)
    IF (NEW.current_player_index IS DISTINCT FROM OLD.current_player_index) 
       OR (NEW.game_status IS DISTINCT FROM OLD.game_status)
       OR (NEW.version > OLD.version) THEN
        NEW.turn_ends_at := NOW() + INTERVAL '30 seconds';
    ELSE
        NEW.turn_ends_at := OLD.turn_ends_at;
    END IF;

    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger 2 : Nettoyage automatique inter-manches (Consomme le drapeau next_manche_ready)
CREATE OR REPLACE FUNCTION public.handle_next_manche_cleanup_vfinal()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.next_manche_ready = true THEN
        NEW.game_status := 'BIDDING';
        NEW.contrat := NULL;
        NEW.last_bid_name := NULL;
        NEW.bid_taker_id := NULL;
        NEW.partner_id := NULL;
        NEW.called_king := NULL;
        NEW.last_card_played := NULL;
        NEW.last_winner_index := NULL;

        NEW.current_trick := '[]'::jsonb;
        NEW.cards_on_table := '[]'::jsonb;
        NEW.pli_joueurs := '{"0":[], "1":[], "2":[], "3":[], "4":[]}'::jsonb;
        NEW.hands := '{}'::jsonb;
        NEW.hand_0 := '[]'::jsonb;
        NEW.hand_1 := '[]'::jsonb;
        NEW.hand_2 := '[]'::jsonb;
        NEW.hand_3 := '[]'::jsonb;
        NEW.hand_4 := '[]'::jsonb;
        NEW.chien := '[]'::jsonb;

        NEW.dealer_index := (OLD.dealer_index + 1) % 5;
        NEW.current_player_index := (OLD.dealer_index + 1) % 5;
        NEW.current_bidder_index := (OLD.dealer_index + 1) % 5;
       
        NEW.next_manche_ready := false;
        NEW.version := COALESCE(OLD.version, 0) + 1;
        NEW.game_version := NEW.version::INT;
        NEW.updated_at := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger 3 : Protection anti-conflits de concurrence
CREATE OR REPLACE FUNCTION public.protect_tarot_sync()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.version <= OLD.version) AND (NEW.phone_index IS DISTINCT FROM OLD.phone_index) THEN
        NEW.version := OLD.version + 1;
        NEW.game_version := NEW.version::INT;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- 4. ASSOCIATION DES TRIGGERS AUX ÉVÉNEMENTS DE LA TABLE
-- =========================================================================
CREATE TRIGGER tr_central_tarot 
    BEFORE UPDATE ON public.table_tarot_5 
    FOR EACH ROW EXECUTE FUNCTION public.central_tarot_orchestrator();

CREATE TRIGGER tr_global_manche_reset 
    BEFORE UPDATE OF next_manche_ready ON public.table_tarot_5 
    FOR EACH ROW EXECUTE FUNCTION public.handle_next_manche_cleanup_vfinal();

CREATE TRIGGER tr_protect_tarot_sync 
    BEFORE UPDATE ON public.table_tarot_5 
    FOR EACH ROW EXECUTE FUNCTION public.protect_tarot_sync();

-- =========================================================================
-- 5. RECRÉATION DES FONCTIONS RPC INDISPENSABLES (POINTS D'ENTRÉE APPLICATION)
-- =========================================================================

-- Fonction de synchronisation d'horloge globale
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS TIMESTAMP WITH TIME ZONE AS $$
    SELECT NOW();
$$ LANGUAGE sql;

-- Fonction maîtresse de connexion dynamique et création de table
CREATE OR REPLACE FUNCTION public.join_or_create_tarot_table(
    p_user_id TEXT,
    p_user_name TEXT,
    p_user_avatar TEXT DEFAULT NULL
)
RETURNS TABLE(assigned_table_id TEXT, assigned_slot INTEGER) AS $$
DECLARE
    v_table_id TEXT;
    v_slot INTEGER;
BEGIN
    -- Recherche d'une table active en phase d'enchères non complète
    SELECT table_id INTO v_table_id
    FROM public.table_tarot_5
    WHERE game_status = 'BIDDING'
      AND turn_ends_at > NOW() 
      AND (
        (CASE WHEN player0_uid IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN player1_uid IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN player2_uid IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN player3_uid IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN player4_uid IS NULL THEN 0 ELSE 1 END)
      ) < 5
    ORDER BY created_at DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    -- Si une table existe, on s'installe sur le premier emplacement libre disponible
    IF v_table_id IS NOT NULL THEN
        IF (SELECT player0_uid FROM public.table_tarot_5 WHERE table_id = v_table_id) IS NULL THEN
            UPDATE public.table_tarot_5 SET player0_uid = p_user_id, player0_name = p_user_name, player0_avatar = p_user_avatar, version = version + 1 WHERE table_id = v_table_id; v_slot := 0;
        ELSIF (SELECT player1_uid FROM public.table_tarot_5 WHERE table_id = v_table_id) IS NULL THEN
            UPDATE public.table_tarot_5 SET player1_uid = p_user_id, player1_name = p_user_name, player1_avatar = p_user_avatar, version = version + 1 WHERE table_id = v_table_id; v_slot := 1;
        ELSIF (SELECT player2_uid FROM public.table_tarot_5 WHERE table_id = v_table_id) IS NULL THEN
            UPDATE public.table_tarot_5 SET player2_uid = p_user_id, player2_name = p_user_name, player2_avatar = p_user_avatar, version = version + 1 WHERE table_id = v_table_id; v_slot := 2;
        ELSIF (SELECT player3_uid FROM public.table_tarot_5 WHERE table_id = v_table_id) IS NULL THEN
            UPDATE public.table_tarot_5 SET player3_uid = p_user_id, player3_name = p_user_name, player3_avatar = p_user_avatar, version = version + 1 WHERE table_id = v_table_id; v_slot := 3;
        ELSIF (SELECT player4_uid FROM public.table_tarot_5 WHERE table_id = v_table_id) IS NULL THEN
            UPDATE public.table_tarot_5 SET player4_uid = p_user_id, player4_name = p_user_name, player4_avatar = p_user_avatar, version = version + 1 WHERE table_id = v_table_id; v_slot := 4;
        END IF;
    ELSE
        -- Sinon, création de la table par le Joueur 0 (Hôte ALPHA)
        v_table_id := 'table_' || substring(md5(random()::text) from 1 for 8);
        v_slot := 0;
        
        INSERT INTO public.table_tarot_5 (
            table_id, game_status, version, player0_uid, player0_name, player0_avatar, last_action_time, turn_ends_at, phone_index
        ) VALUES (
            v_table_id, 'BIDDING', 1, p_user_id, p_user_name, p_user_avatar, TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), NOW() + INTERVAL '30 seconds', 'INIT'
        );
    END IF;

    RETURN QUERY SELECT v_table_id, v_slot;
END;
$$ LANGUAGE plpgsql;

-- Fonction maîtresse de distribution des cartes (Signature française propre sans "T")
CREATE OR REPLACE FUNCTION public.distribue_tarot_cards(
    p_table_id TEXT,
    p_hand_0 JSONB,
    p_hand_1 JSONB,
    p_hand_2 JSONB,
    p_hand_3 JSONB,
    p_hand_4 JSONB,
    p_chien JSONB
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.table_tarot_5
    SET hand_0 = p_hand_0,
        hand_1 = p_hand_1,
        hand_2 = p_hand_2,
        hand_3 = p_hand_3,
        hand_4 = p_hand_4,
        chien = p_chien,
        game_status = 'BIDDING',
        version = version + 1
    WHERE table_id = p_table_id;
END;
$$ LANGUAGE plpgsql;
