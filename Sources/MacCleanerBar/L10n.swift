import Foundation

enum L {
    static let fr = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")

    static func t(_ key: String) -> String {
        (fr ? frDict[key] : enDict[key]) ?? key
    }

    static var gb: String { fr ? "Go" : "GB" }
    static var mb: String { fr ? "Mo" : "MB" }
    static var kb: String { fr ? "Ko" : "KB" }

    private static func num(_ v: Double, _ digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: fr ? "fr_FR" : "en_US")
        f.numberStyle = .decimal
        f.groupingSeparator = fr ? "\u{202F}" : ","
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v)
    }

    static func human(kb k: Double) -> String {
        if k >= 1_048_576 { return "\(num(k / 1_048_576, 1)) \(gb)" }
        if k >= 1024 { return "\(num(k / 1024, 0)) \(mb)" }
        return "\(num(k, 0)) \(kb)"
    }

    static func human(bytes b: Int64) -> String {
        human(kb: Double(b) / 1024)
    }

    static func rpm(_ v: Double) -> String {
        num((v / 10).rounded() * 10, 0)
    }

    static func fans(_ count: Int, rpm r: Double?) -> String {
        if count == 0 { return t("noFan") }
        let word = count > 1 ? t("fans") : t("fan")
        guard let r else { return "\(count) \(word)" }
        return "\(count)\u{00A0}\(word) · " + "\(rpm(r)) \(t("rpm"))".replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private static let frDict: [String: String] = [
        "disk": "Disque",
        "memory": "Mémoire",
        "heat": "Chaleur",
        "freeDisk": "%@ libres",
        "used": "utilisée",
        "heatNormal": "Normale",
        "heatHigh": "Élevée",
        "heatHot": "Très chaude",
        "fan": "ventilateur",
        "fans": "ventilateurs",
        "noFan": "Sans ventilateur",
        "rpm": "tr/min",
        "auto": "Tout nettoyer",
        "caches": "Caches",
        "temp": "Fichiers inutiles",
        "trash": "Corbeille",
        "ram": "Libérer la RAM",
        "ramUsed": "%d %% utilisée",
        "ramDone": "Mémoire libre : %d %% → %d %%",
        "ramFailed": "Libération de la RAM annulée",
        "tools": "Outils",
        "uninstall": "Désinstaller une app",
        "large": "Gros fichiers",
        "downloads": "Anciens téléchargements",
        "duplicates": "Doublons",
        "startup": "Démarrage",
        "dev": "Projets dev",
        "system": "Système",
        "menu": "Ouvrir le menu complet dans le Terminal",
        "preview": "Aperçu",
        "cancel": "Annuler",
        "clean": "Nettoyer",
        "close": "Fermer",
        "running": "En cours…",
        "done": "Terminé",
        "estimating": "Calcul…",
        "freedMonth": "Libéré ce mois : %@",
        "login": "Lancer à l'ouverture de session",
        "quit": "Quitter",
        "missing": "Le moteur mac-cleaner est introuvable. Installe-le avec :",
        "noOutput": "(aucune sortie)",
        "exitCode": "Code de sortie : %d",
        "search": "Rechercher une app",
        "noApps": "Aucune app",
        "leftovers": "Fichiers à mettre à la corbeille",
        "total": "Total",
        "toTrash": "Mettre à la corbeille",
        "selectApp": "Choisis une app pour voir ses fichiers restants.",
        "uninstalled": "%@ est dans la corbeille.",
    ]

    private static let enDict: [String: String] = [
        "disk": "Disk",
        "memory": "Memory",
        "heat": "Heat",
        "freeDisk": "%@ free",
        "used": "used",
        "heatNormal": "Normal",
        "heatHigh": "High",
        "heatHot": "Very hot",
        "fan": "fan",
        "fans": "fans",
        "noFan": "Fanless",
        "rpm": "rpm",
        "auto": "Clean everything",
        "caches": "Caches",
        "temp": "Junk files",
        "trash": "Trash",
        "ram": "Free up RAM",
        "ramUsed": "%d %% used",
        "ramDone": "Free memory: %d %% → %d %%",
        "ramFailed": "Freeing RAM was cancelled",
        "tools": "Tools",
        "uninstall": "Uninstall an app",
        "large": "Large files",
        "downloads": "Old downloads",
        "duplicates": "Duplicates",
        "startup": "Startup",
        "dev": "Dev projects",
        "system": "System",
        "menu": "Open the full menu in Terminal",
        "preview": "Preview",
        "cancel": "Cancel",
        "clean": "Clean",
        "close": "Close",
        "running": "Running…",
        "done": "Done",
        "estimating": "Measuring…",
        "freedMonth": "Freed this month: %@",
        "login": "Launch at login",
        "quit": "Quit",
        "missing": "The mac-cleaner engine was not found. Install it with:",
        "noOutput": "(no output)",
        "exitCode": "Exit code: %d",
        "search": "Search apps",
        "noApps": "No apps",
        "leftovers": "Files to move to the Trash",
        "total": "Total",
        "toTrash": "Move to Trash",
        "selectApp": "Pick an app to see its leftover files.",
        "uninstalled": "%@ is in the Trash.",
    ]
}
