#!/usr/bin/env python3
"""Générateur du blog de tarot-gothique-2026.com.

On écrit les articles dans Supabase (table blog_posts : titre, description, texte Markdown,
statut « publie »). Ce script en fait de vraies pages HTML statiques, lisibles par Google :

  blog/<slug>.html      une page par article publié (commentaires modérés en bas)
  blog/index.html       la liste des articles
  index.html            le bloc « Dernières actualités du blog » de l'accueil (3 derniers)
  sitemap.xml           les adresses du blog (entre les repères BLOG:DEBUT / BLOG:FIN)

Usage (depuis la racine du site) :
  python3 blog/generer.py               articles publiés seulement
  python3 blog/generer.py --brouillons  aperçu local avec les brouillons (NE PAS publier ainsi)
Puis vérifier, commiter et pousser.
"""
import html
import json
import re
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

import markdown

RACINE = Path(__file__).resolve().parent.parent
SITE = "https://tarot-gothique-2026.com"
SUPABASE = "https://ruixknekqinalyccxotp.supabase.co"
CLE_PUBLIQUE = "sb_publishable_srFEs1VmnrK-ThxZzR7kOQ_QPNnCQ-T"  # clé publique (déjà dans le jeu web)
FONCTION = f"{SUPABASE}/functions/v1/blog-commentaire"
DISCORD = "https://discord.gg/PAgE8Y3MSN"
MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
        "septembre", "octobre", "novembre", "décembre"]


def lire_articles(brouillons: bool):
    filtre = "" if brouillons else "&status=eq.publie"
    url = (f"{SUPABASE}/rest/v1/blog_posts?select=slug,title,description,content_md,image,status,"
           f"published_at,updated_at&order=published_at.desc{filtre}")
    if brouillons:
        # Les brouillons ne sont pas lisibles avec la clé publique : lecture via la CLI Supabase.
        import subprocess
        sortie = subprocess.run(
            ["supabase", "db", "query", "--linked",
             "select slug,title,description,content_md,image,status,published_at,updated_at "
             "from blog_posts order by published_at desc"],
            capture_output=True, text=True, check=True, cwd=RACINE.parent / "tarot").stdout
        return json.loads(sortie[sortie.index("{"):sortie.rindex("}") + 1])["rows"]
    req = urllib.request.Request(url, headers={"apikey": CLE_PUBLIQUE, "Authorization": f"Bearer {CLE_PUBLIQUE}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def date_fr(iso: str) -> str:
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return f"{d.day} {MOIS[d.month - 1]} {d.year}"


def style_du_site() -> str:
    """Reprend la feuille de style de linux.html (même habillage que le reste du site)."""
    t = (RACINE / "linux.html").read_text(encoding="utf-8")
    css = t[t.index("<style>") + 7:t.index("</style>")]
    return css.replace("url('background", "url('../background")


CSS_BLOG = """
        .article-meta { color: var(--text-muted); font-size: 0.9rem; margin: 0 0 0.8rem; opacity: 0.85; }
        .info-card h2 + .article-meta { margin-top: -0.2rem; }
        .article-corps p, .article-corps li { font-size: 1.05rem; line-height: 1.6; color: var(--text-muted); }
        .article-corps h2 { margin-top: 1.2rem; }
        .article-corps img { max-width: 100%; height: auto; border-radius: 8px; }
        .liste-articles { display: grid; gap: 0.8rem; }
        .liste-articles .info-card h2 a { color: var(--primary-gold); text-decoration: none; }
        .commentaire { border-top: 1px solid rgba(212,175,55,0.3); padding: 0.6rem 0; }
        .commentaire b { color: var(--primary-gold); }
        .commentaire time { font-size: 0.8rem; opacity: 0.7; margin-left: 0.4rem; }
        .commentaire p { white-space: pre-wrap; margin: 0.3rem 0 0; }
        .form-commentaire { display: grid; gap: 0.5rem; margin-top: 0.8rem; }
        .form-commentaire input, .form-commentaire textarea { font: inherit; padding: 0.6rem; border-radius: 6px;
            border: 1px solid var(--border-color); background: #0b0b12; color: var(--text-main); }
        .form-commentaire textarea { min-height: 7rem; resize: vertical; }
        .form-commentaire button { justify-self: start; border: 0; cursor: pointer; }
        .piege { position: absolute; left: -9999px; width: 1px; height: 1px; overflow: hidden; }
        .message-envoi { font-weight: bold; color: var(--primary-gold); min-height: 1.2em; }
"""


def page(titre: str, description: str, canonique: str, h1: str, corps: str, jsonld: dict,
         og_type="article", image="jeux-de-tarot.jpg", robots="index, follow, max-image-preview:large") -> str:
    e = html.escape
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{e(titre)}</title>
    <meta name="description" content="{e(description)}">
    <link rel="canonical" href="{canonique}">
    <meta name="robots" content="{robots}">
    <meta name="author" content="Cyril Darbost">
    <meta name="theme-color" content="#0b0b0f">
    <link rel="icon" type="image/png" sizes="192x192" href="../favicon.png">
    <link rel="icon" href="../favicon.ico" sizes="48x48">
    <link rel="apple-touch-icon" href="../apple-touch-icon.png">
    <link rel="alternate" type="application/rss+xml" title="Blog Tarot Gothique 2026" href="{SITE}/blog/flux.xml">
    <meta property="og:type" content="{og_type}">
    <meta property="og:site_name" content="Tarot Gothique">
    <meta property="og:locale" content="fr_FR">
    <meta property="og:url" content="{canonique}">
    <meta property="og:title" content="{e(titre)}">
    <meta property="og:description" content="{e(description)}">
    <meta property="og:image" content="{SITE}/{image}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{e(titre)}">
    <meta name="twitter:description" content="{e(description)}">
    <meta name="twitter:image" content="{SITE}/{image}">
    <script type="application/ld+json">
{json.dumps(jsonld, ensure_ascii=False, indent=2)}
    </script>
    <style>{style_du_site()}{CSS_BLOG}    </style>
    <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-2567840580892054" crossorigin="anonymous"></script>
</head>
<body>

    <header>
        <h1>{e(h1)}</h1>
        <nav class="main-nav">
            <a href="../">Jeu de tarot</a>
            <a href="../regles.html">Règles du Tarot</a>
            <a href="./" class="active">Blog</a>
            <a href="../galerie.html">Galerie Photo</a>
            <a href="../apropos.html">À propos & FAQ</a>
        </nav>
    </header>

    <main>
{corps}
    </main>

    <footer>
        <p>&copy; 2026 <strong>Tarot Gothique</strong> (Cyril Darbost). Tous droits réservés. | <a href="../">Jeu de tarot</a> | <a href="./">Blog</a> | <a href="../apropos.html">Mentions légales</a> | <a href="../privacy.html">Confidentialité</a> | <a href="{DISCORD}" target="_blank" rel="noopener">Discord</a></p>
    </footer>

</body>
</html>
"""


SCRIPT_COMMENTAIRES = """
    <script>
    (function () {
        var F = '__FONCTION__', post = '__SLUG__';
        var liste = document.getElementById('liste-commentaires');
        function afficher(c) {
            var d = document.createElement('div'); d.className = 'commentaire';
            var b = document.createElement('b'); b.textContent = c.author_name;
            var t = document.createElement('time'); t.dateTime = c.created_at;
            t.textContent = new Date(c.created_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });
            var p = document.createElement('p'); p.textContent = c.content;
            d.append(b, t, p); liste.appendChild(d);
        }
        fetch(F + '?post=' + post).then(function (r) { return r.json(); }).then(function (j) {
            liste.textContent = '';
            if (!j.ok || !j.commentaires.length) { liste.textContent = 'Aucun commentaire pour le moment. Soyez le premier !'; return; }
            j.commentaires.forEach(afficher);
        }).catch(function () { liste.textContent = 'Les commentaires ne peuvent pas être chargés pour le moment.'; });

        var f = document.getElementById('form-commentaire'), m = document.getElementById('message-envoi');
        var motifs = { pseudo: 'Pseudo invalide (2 à 40 caractères, sans lien).', message: 'Message trop court ou trop long (3 à 2000 caractères).',
                       liens: 'Trop de liens dans le message.', trop: 'Trop de messages envoyés, réessayez plus tard.' };
        f.addEventListener('submit', function (e) {
            e.preventDefault();
            var bouton = f.querySelector('button'); bouton.disabled = true; m.textContent = 'Envoi…';
            fetch(F, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
                action: 'publier', post_id: post, author_name: f.pseudo.value, content: f.message.value, site: f.site.value }) })
            .then(function (r) { return r.json(); }).then(function (j) {
                if (j.ok) { f.reset(); m.textContent = 'Merci ! Votre message est bien reçu : il sera affiché après modération.'; }
                else { m.textContent = motifs[j.motif] || 'Le message n’a pas pu être envoyé.'; }
            }).catch(function () { m.textContent = 'Le message n’a pas pu être envoyé. Vérifiez votre connexion.'; })
            .then(function () { bouton.disabled = false; });
        });
    })();
    </script>"""


def page_article(a: dict) -> str:
    url = f"{SITE}/blog/{a['slug']}.html"
    image = a.get("image") or "jeux-de-tarot.jpg"
    corps_md = markdown.markdown(a["content_md"] or "", extensions=["extra", "sane_lists"])
    jsonld = {
        "@context": "https://schema.org",
        "@graph": [
            {"@type": "BlogPosting", "@id": f"{url}#article", "headline": a["title"], "description": a["description"],
             "datePublished": a["published_at"], "dateModified": a["updated_at"], "inLanguage": "fr",
             "image": f"{SITE}/{image}", "mainEntityOfPage": url,
             "author": {"@type": "Person", "@id": f"{SITE}/#auteur", "name": "Cyril Darbost"},
             "publisher": {"@id": f"{SITE}/#organisation"},
             "isPartOf": {"@type": "Blog", "@id": f"{SITE}/blog/#blog", "name": "Blog Tarot Gothique 2026"}},
            {"@type": "BreadcrumbList", "itemListElement": [
                {"@type": "ListItem", "position": 1, "name": "Jeu de tarot", "item": f"{SITE}/"},
                {"@type": "ListItem", "position": 2, "name": "Blog", "item": f"{SITE}/blog/"},
                {"@type": "ListItem", "position": 3, "name": a["title"], "item": url}]},
        ],
    }
    e = html.escape
    corps = f"""
        <article class="info-card">
            <h2>{e(a['title'])}</h2>
            <p class="article-meta">Publié le <time datetime="{a['published_at']}">{date_fr(a['published_at'])}</time> par Cyril Darbost</p>
            <div class="article-corps">
{corps_md}
            </div>
            <p class="cta-linux"><a class="cta-button" href="../jouer/">Jouer gratuitement dans le navigateur</a></p>
        </article>

        <section class="info-card" id="commentaires">
            <h2>Commentaires</h2>
            <div id="liste-commentaires">Chargement des commentaires…</div>
            <form id="form-commentaire" class="form-commentaire">
                <label for="pseudo">Pseudo</label>
                <input id="pseudo" name="pseudo" required minlength="2" maxlength="40" autocomplete="nickname">
                <label for="message">Message</label>
                <textarea id="message" name="message" required minlength="3" maxlength="2000"></textarea>
                <div class="piege" aria-hidden="true"><label>Site web <input name="site" tabindex="-1" autocomplete="off"></label></div>
                <button type="submit" class="cta-button">Envoyer</button>
                <p id="message-envoi" class="message-envoi" role="status"></p>
                <p class="article-meta">Pas de compte à créer. Chaque message est relu avant d’être affiché. Pseudo et message seront publics ; voir la <a href="../privacy.html">politique de confidentialité</a>.</p>
            </form>
        </section>
{SCRIPT_COMMENTAIRES.replace('__FONCTION__', FONCTION).replace('__SLUG__', a['slug'])}
"""
    robots = "noindex, nofollow" if a["status"] != "publie" else "index, follow, max-image-preview:large"
    return page(f"{a['title']} | Blog Tarot Gothique 2026", a["description"], url, "Blog Tarot Gothique 2026",
                corps, jsonld, image=image, robots=robots)


def page_index(articles: list) -> str:
    e = html.escape
    cartes = "\n".join(f"""        <div class="info-card">
            <h2><a href="{a['slug']}.html">{e(a['title'])}</a></h2>
            <p class="article-meta">{date_fr(a['published_at'])}</p>
            <p>{e(a['description'])}</p>
            <p><a href="{a['slug']}.html">Lire l’article</a></p>
        </div>""" for a in articles) or '        <div class="info-card"><p>Premier article bientôt.</p></div>'
    corps = f"""
        <div class="info-card">
            <h2>Actualités, règles et astuces du jeu de tarot</h2>
            <p>Les nouveautés de Tarot Gothique 2026, des conseils pour progresser au tarot à 3, 4 et 5 joueurs et les coulisses du développement du jeu.</p>
        </div>
        <div class="liste-articles">
{cartes}
        </div>
"""
    jsonld = {"@context": "https://schema.org", "@type": "Blog", "@id": f"{SITE}/blog/#blog",
              "name": "Blog Tarot Gothique 2026", "url": f"{SITE}/blog/", "inLanguage": "fr",
              "publisher": {"@id": f"{SITE}/#organisation"},
              "blogPost": [{"@type": "BlogPosting", "headline": a["title"], "url": f"{SITE}/blog/{a['slug']}.html",
                            "datePublished": a["published_at"]} for a in articles]}
    return page("Blog du jeu de tarot | Tarot Gothique 2026",
                "Actualités de Tarot Gothique 2026, règles et astuces du jeu de tarot à 3, 4 et 5 joueurs, coulisses du développement.",
                f"{SITE}/blog/", "Blog Tarot Gothique 2026", corps, jsonld, og_type="website")


def flux_rss(articles: list) -> str:
    e = html.escape
    items = "".join(f"""
    <item><title>{e(a['title'])}</title><link>{SITE}/blog/{a['slug']}.html</link>
      <guid>{SITE}/blog/{a['slug']}.html</guid><description>{e(a['description'])}</description>
      <pubDate>{datetime.fromisoformat(a['published_at'].replace('Z', '+00:00')).strftime('%a, %d %b %Y %H:%M:%S %z')}</pubDate></item>""" for a in articles)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
    <title>Blog Tarot Gothique 2026</title><link>{SITE}/blog/</link>
    <description>Actualités, règles et astuces du jeu de tarot Tarot Gothique 2026.</description>
    <language>fr</language>{items}
</channel></rss>
"""


def bloc_accueil(articles: list) -> str:
    e = html.escape
    if not articles:
        return ""
    cartes = "\n".join(f"""                <article class="carte-blog">
                    <h3><a href="blog/{a['slug']}.html">{e(a['title'])}</a></h3>
                    <p class="date-blog">{date_fr(a['published_at'])}</p>
                    <p>{e(a['description'])}</p>
                </article>""" for a in articles[:3])
    return f"""
        <section class="bloc-blog" id="blog">
            <style>
                .bloc-blog {{ background: var(--card-bg, rgba(22,22,34,0.82)); border: 1px solid #d4af37; border-radius: 10px; padding: 1rem 1.2rem; margin: 1rem 0; }}
                .bloc-blog h2 {{ color: #f3d060; margin: 0 0 0.6rem; }}
                .grille-blog {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 0.8rem; }}
                .carte-blog {{ border: 1px solid rgba(212,175,55,0.35); border-radius: 8px; padding: 0.7rem 0.9rem; background: rgba(11,11,18,0.6); }}
                .carte-blog h3 {{ margin: 0 0 0.3rem; font-size: 1.05rem; }}
                .carte-blog h3 a {{ color: #f3d060; text-decoration: none; }}
                .carte-blog p {{ margin: 0.2rem 0; line-height: 1.45; }}
                .date-blog {{ font-size: 0.85rem; opacity: 0.75; }}
                .bloc-blog .tous {{ display: inline-block; margin-top: 0.7rem; color: #f3d060; font-weight: bold; }}
            </style>
            <h2>Dernières actualités du blog</h2>
            <div class="grille-blog">
{cartes}
            </div>
            <a class="tous" href="blog/">Tous les articles du blog</a>
        </section>
"""


def remplacer_entre(texte: str, debut: str, fin: str, nouveau: str, ancre_apres: str) -> str:
    """Remplace ce qui est entre deux repères ; les pose après `ancre_apres` la première fois."""
    if debut in texte:
        i, j = texte.index(debut), texte.index(fin) + len(fin)
        return texte[:i] + debut + nouveau + fin + texte[j:]
    k = texte.index(ancre_apres) + len(ancre_apres)
    return texte[:k] + "\n" + debut + nouveau + fin + texte[k:]


def main():
    brouillons = "--brouillons" in sys.argv
    articles = lire_articles(brouillons)
    for a in articles:
        if not (a.get("title") and a.get("description") and a.get("content_md")):
            sys.exit(f"Article incomplet : {a.get('slug')} (titre, description et texte obligatoires)")
    publies = [a for a in articles if a["status"] == "publie"]
    dossier = RACINE / "blog"
    for a in articles:
        (dossier / f"{a['slug']}.html").write_text(page_article(a), encoding="utf-8")
    visibles = articles if brouillons else publies
    (dossier / "index.html").write_text(page_index(visibles), encoding="utf-8")
    (dossier / "flux.xml").write_text(flux_rss(publies), encoding="utf-8")

    accueil = RACINE / "index.html"
    t = accueil.read_text(encoding="utf-8")
    ancre = t[:t.index("</section>", t.index('id="telecharger"')) + len("</section>")]
    t = remplacer_entre(t, "<!-- BLOG:DEBUT -->", "<!-- BLOG:FIN -->", bloc_accueil(visibles), ancre)
    accueil.write_text(t, encoding="utf-8")

    plan = RACINE / "sitemap.xml"
    s = plan.read_text(encoding="utf-8")
    urls = [f"""  <url>
    <loc>{SITE}/blog/</loc>
    <lastmod>{(publies[0]['updated_at'] if publies else datetime.now().isoformat())[:10]}</lastmod>
  </url>"""] + [f"""  <url>
    <loc>{SITE}/blog/{a['slug']}.html</loc>
    <lastmod>{a['updated_at'][:10]}</lastmod>
  </url>""" for a in publies]
    bloc = "\n" + "\n".join(urls) + "\n  " if publies else "\n  "
    if "<!-- BLOG:DEBUT -->" in s:
        i, j = s.index("<!-- BLOG:DEBUT -->"), s.index("<!-- BLOG:FIN -->") + len("<!-- BLOG:FIN -->")
        s = s[:i] + "<!-- BLOG:DEBUT -->" + bloc + "<!-- BLOG:FIN -->" + s[j:]
    else:
        s = s.replace("</urlset>", "  <!-- BLOG:DEBUT -->" + bloc + "<!-- BLOG:FIN -->\n</urlset>")
    plan.write_text(s, encoding="utf-8")
    print(f"{len(articles)} article(s) généré(s), {len(publies)} publié(s)" + (" — APERÇU AVEC BROUILLONS, ne pas publier" if brouillons else ""))


if __name__ == "__main__":
    main()
