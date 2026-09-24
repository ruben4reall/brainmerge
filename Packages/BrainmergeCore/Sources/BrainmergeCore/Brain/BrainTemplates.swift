import Foundation

public enum BrainTemplates {
    public static func brainMD(_ language: BrainLanguage) -> String {
        switch language {
        case .en: return en
        case .fr: return fr
        }
    }

    static let en = """
    # Shared brain

    This folder is the memory of the Claude accounts Brainmerge attaches to it, on this machine and on other machines when it is synced. Brainmerge keeps it in git; each account commits under its own name.

    ## How to use it

    - The memory of the current project lives in `memory/<project>/`: Claude Code's auto memory, linked here by Brainmerge. Keep `MEMORY.md` as a short index, one topic file per fact.
    - Write down what a future session could not rediscover: decisions, preferences, deadlines, corrections. Skip what the code or the git history already says.
    - When it matters, say which identity wrote a note: `identity: <slug>` in the file's frontmatter.
    - Never write secrets here (passwords, API keys, tokens): this folder is versioned and may be synced.

    """

    static let fr = """
    # Cerveau partagé

    Ce dossier est la mémoire des comptes Claude que Brainmerge y rattache, sur cette machine et sur les autres quand il est synchronisé. Brainmerge le garde dans git ; chaque compte commit sous son propre nom.

    ## Comment s'en servir

    - La mémoire du projet en cours vit dans `memory/<projet>/` : la mémoire automatique de Claude Code, reliée ici par Brainmerge. Garder `MEMORY.md` comme un index court, une fiche par fait.
    - Noter ce qu'une prochaine session ne pourrait pas redécouvrir : décisions, préférences, échéances, corrections. Ignorer ce que le code ou l'historique git disent déjà.
    - Quand ça compte, dire quelle identité a écrit une fiche : `identity: <slug>` dans le frontmatter du fichier.
    - Ne jamais écrire de secret ici (mots de passe, clés, jetons) : ce dossier est versionné et peut être synchronisé.

    """
}
