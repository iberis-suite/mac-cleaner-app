import Foundation

enum L {
    static let fr = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")

    static func t(_ key: String) -> String {
        (fr ? frDict[key] : enDict[key]) ?? key
    }

    static var gb: String { fr ? "Go" : "GB" }
    static var mb: String { fr ? "Mo" : "MB" }
    static var kb: String { fr ? "Ko" : "KB" }

    static func human(kb k: Double) -> String {
        if k >= 1_048_576 { return String(format: "%.1f %@", k / 1_048_576, gb) }
        if k >= 1024 { return String(format: "%.1f %@", k / 1024, mb) }
        return String(format: "%.0f %@", k, kb)
    }

    static func human(bytes b: Int64) -> String {
        human(kb: Double(b) / 1024)
    }

    private static let frDict: [String: String] = [
        "disk": "Disque",
        "memory": "Mémoire",
        "used": "utilisés",
        "free": "libre",
        "auto": "Nettoyage auto",
        "caches": "Caches",
        "temp": "Fichiers temporaires",
        "trash": "Corbeille",
        "ram": "Libérer la RAM",
        "large": "Gros fichiers",
        "dev": "Projets dev",
        "menu": "Menu complet",
        "advanced": "Dans le Terminal",
        "preview": "Aperçu",
        "cancel": "Annuler",
        "clean": "Nettoyer",
        "close": "Fermer",
        "running": "En cours…",
        "done": "Terminé",
        "history": "Historique",
        "freed30": "Libéré ces 30 derniers jours : %@",
        "noHistory": "Aucun nettoyage encore",
        "login": "Lancer à l'ouverture de session",
        "quit": "Quitter",
        "missing": "Le moteur mac-cleaner est introuvable. Installe-le avec :",
        "noOutput": "(aucune sortie)",
        "exitCode": "Code de sortie : %d",
    ]

    private static let enDict: [String: String] = [
        "disk": "Disk",
        "memory": "Memory",
        "used": "used",
        "free": "free",
        "auto": "Auto clean",
        "caches": "Caches",
        "temp": "Temporary files",
        "trash": "Trash",
        "ram": "Free up RAM",
        "large": "Large files",
        "dev": "Dev projects",
        "menu": "Full menu",
        "advanced": "In Terminal",
        "preview": "Preview",
        "cancel": "Cancel",
        "clean": "Clean",
        "close": "Close",
        "running": "Running…",
        "done": "Done",
        "history": "History",
        "freed30": "Freed in the last 30 days: %@",
        "noHistory": "No cleanup yet",
        "login": "Launch at login",
        "quit": "Quit",
        "missing": "The mac-cleaner engine was not found. Install it with:",
        "noOutput": "(no output)",
        "exitCode": "Exit code: %d",
    ]
}
