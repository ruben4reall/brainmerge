# Tâches · brainmerge

> Suivi partagé. Cocher ce qui est fait, ajouter ce qu'on découvre.
> Vue d'ensemble de tous les projets : `~/projects-hub/bin/projects-status`

## À faire

- [ ] Ruben : dans Brainmerge, ouvrir Edit sur un compte et cliquer « Swap names » (les noms sont inversés par rapport aux e-mails de Claude Code) ; puis ne plus ouvrir le compte secondaire avec les copies de Claude faites main (Claude plus ancien sur les mêmes données), les mettre à la corbeille une fois le compte fermé
- [ ] Vérifier à la main dans l'app installée : survol et clic sur toute la ligne, Cmd-1 à Cmd-4, « Show » qui ramène une fenêtre fermée
- [ ] Rejouer S2 et S3 (vraies sessions Claude Code des deux comptes) quand les profils CLI sont reconnectés
- [ ] Réglages GitHub à faire par Ruben : protéger main (fusion par PR, CI verte), téléverser l'aperçu social (docs/brand/banner-1280x640.png), description et sujets du dépôt, activer « Report a vulnerability »
- [ ] Codex et autres assistants (CODEX_HOME, AGENTS.md, notify) derrière une abstraction « provider » ; rattacher les sessions Claude Code du Terminal à leur compte (aujourd'hui une seule ligne pour tous : le compte n'est que dans l'environnement, jamais lu ; piste : un lanceur `brainmerge claude <compte>` qui marque son argv)
- [ ] Refaire la capture 21-usage.png avec la section RAM et disque (elle montre la vraie RAM du Mac qui capture ; les tailles disque d'un home de démo sont minuscules)
- [ ] Vérifier à la main dans l'app installée l'écran Usage : RAM du Mac proche de Moniteur d'activité, RAM par compte, ligne Terminal, tailles disque et « Measure again »
- [ ] Calibrer la détection de connexion sur une vraie connexion (un compte de test au clavier)
- [ ] Envoyer à Anthropic la demande d'autorisation pour la mascotte (lettre dans ~/brainmerge-private/docs/anthropic-brand-request.md) avant la sortie publique ; si refus, remplacer la créature (un seul fichier)
- [ ] Trouver un nom à la créature avec Ruben
- [ ] v0.1 « Ton montage, automatisé » : identités, cerveau local, attribution, doctor, interface, tests, build signée et notarisée
- [ ] v0.2 « Deux machines » : synchro git, projets par nom, conflits arbitrés
- [ ] v0.3 « Vitrine » : kit de départ, barre de menus, cask Homebrew, Sparkle, README anglais, lettre au support d'Anthropic, lancement public
- [ ] Windows en natif, après la v1

## Fait

- [x] 2026-09-25 : RAM et disque par compte (0.6.0, non publiée) : RAM du Mac comptée comme Moniteur d'activité, RAM de chaque compte par l'empreinte de ses processus (cartes, sous-titre et alerte au même chiffre), sessions Claude Code du Terminal sur une ligne honnête, taille disque de chaque compte depuis les métadonnées (liens jamais suivis, historique partagé compté une fois, copie teintée par ses blocs propres), gardes de sécurité ajoutées
- [x] 2026-09-25 : v0.5.0 publiée, notarisée et installée : barre latérale cliquable sur toute la ligne avec survol et Open/Show visibles, animation de démarrage du personnage qui marche, e-mail Claude Code de chaque compte (3 champs d'affichage lus, jamais stockés) avec échange des noms inversés, compte principal modifiable sans quitter Claude et app à sa couleur, apps faites main reconnues et signalées ; un seul bouton violet par écran (teinte globale de la 0.4.0 retirée) ; captures toujours arrêtées à la fin du script

- [x] 2026-09-25 : notarisation de la 0.4.0 acceptée par Apple (soumission 00621551), DMG agrafés et remplacés dans la release, consignes d'installation mises à jour (site, README, notes de release)

- [x] 2026-09-25 : v0.4.0 publiée (signée Developer ID, soumise à la notarisation), installée dans /Applications, doctor vert ; site vitrine en ligne sur https://brainmerge.vercel.app (Vercel perso, mesure d'audience, page d'accueil du dépôt)

- [x] 2026-09-24 : signature Developer ID via le compte Xcode de Ruben (export developer-id avec signature cloud), release.sh qui signe, notarise, agrafe et produit dist/Brainmerge.dmg
- [x] 2026-09-24 : écran Mémoire en graphe vivant façon Obsidian (bulles par compte, liens, projets, pulsations, survol, clic, double-clic, frise en second onglet), branche memory-graph

- [x] 2026-09-24 : v0.3 « utile pour de vrai » : plusieurs mémoires (une par compte au choix), état connecté, feuille d'édition et vrai app par compte, mises à jour vivantes des copies teintées, lecture d'usage 13 fois plus légère, désinstallation propre, finitions de l'audit design, README réécrit autour du problème, 0.3.0 installée
- [x] 2026-09-24 : plan C « finitions v0.2 » : DA violette sobre et pro, écran Usage (tokens locaux), RAM par compte et alerte, identité de marque, DMG propre et déplacement vers Applications, fichiers de contribution, revue finale corrigée, 0.2.0 installée
- [x] 2026-09-24 : plan B écrit et exécuté, app SwiftUI macOS 26 (accueil guidé, comptes, mémoire, réglages), DMG, recette sur le Mac de Ruben par l'app
- [x] 2026-09-24 : cadrage, conformité vérifiée, nom Brainmerge, spec de conception v1
- [x] 2026-09-24 : spec validée par Ruben, questions ouvertes tranchées (section 17)
- [x] 2026-09-24 : plan A « cœur et ligne de commande » écrit et relu
- [x] 2026-09-24 : plan A, tâches 1 à 15 exécutées en TDD sur la branche v0.1, ligne de commande complète
- [x] 2026-09-24 : revue finale par un relecteur frais, 8 corrections en TDD, 77 tests verts, v0.1 fusionnée dans main
- [x] 2026-09-24 : direction artistique retenue après six maquettes (esprit Claude, verre, aura, créature), fiche DA et spec § 10 à jour
