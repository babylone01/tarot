import os
from PIL import Image
def generer_cartes_tarot_final():
    source = "Ace of Spades.png"
    if not os.path.exists(source):
        print(f"Erreur : {source} introuvable.")
        return
    img = Image.open(source).convert('RGB')
    boite = img.getbbox()
    planche = img.crop(boite)
    largeur, hauteur = planche.size
    nb_cols, nb_rows = 14, 6
    w_case, h_case = largeur / nb_cols, hauteur / nb_rows
    # Ordre des suites selon tes instructions (Lignes 3, 4, 5, 6)
    suites = ["Spades", "Hearts", "Diamonds", "Clubs"]
    ordre_couleur = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Knight", "Queen", "King"]
    noms = []
    # Ligne 1 : Atouts 1 à 14
    noms.extend([f"{i} of Trump.png" for i in range(1, 15)])
    # Ligne 2 : Atouts 15 à 21, The Fool, puis 6 cases vides
    noms.extend([f"{i} of Trump.png" for i in range(15, 22)])
    noms.append("The Fool.png")
    noms.extend(["SKIP"] * 6)
    # Lignes 3 à 6 : Pique, Cœur, Carreau, Trèfle (1-10 + Figures)
    for suite in suites:
        for card in ordre_couleur:
            noms.append(f"{card} of {suite}.png")
    idx = 0
    for r in range(nb_rows):
        for c in range(nb_cols):
            if idx < len(noms):
                if noms[idx] != "SKIP":
                    gauche, haut = int(c * w_case) + 1, int(r * h_case) + 1
                    droite, bas = int((c + 1) * w_case) - 1, int((r + 1) * h_case) - 1
                    planche.crop((gauche, haut, droite, bas)).save(noms[idx])
                idx += 1
    print(f"Extraction terminée : 78 cartes extraites avec l'ordre des couleurs respecté.")
if __name__ == "__main__":
    generer_cartes_tarot_final()

