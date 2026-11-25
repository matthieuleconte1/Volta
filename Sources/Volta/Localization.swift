import Foundation

/// App language. French is the source language: every string is written in French in the code
/// and looked up here for English.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: L("Système")
        case .fr: "Français"
        case .en: "English"
        }
    }

    /// Whether the system prefers French (any French locale); otherwise English.
    static var systemIsFrench: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")
    }
}

enum Localization {
    /// Read on any thread; set on the main thread when the setting changes.
    nonisolated(unsafe) static var english = !AppLanguage.systemIsFrench

    static func apply(_ language: AppLanguage) {
        english = switch language {
        case .system: !AppLanguage.systemIsFrench
        case .fr: false
        case .en: true
        }
    }

    /// French → English.
    static let en: [String: String] = [
        // Components
        "Processeur": "Processor",
        "Graphique": "Chart",
        "Écran": "Display",
        "Puce": "Chip",
        "Autres": "Other",
        "rétroéclairage": "backlight",
        "bus, contrôleur mémoire…": "fabric, memory controller…",
        "dalle, SSD, Wi-Fi, USB…": "panel, SSD, Wi-Fi, USB…",

        // Header, flow
        "Consommation du Mac": "Mac power draw",
        "Il y a %d s": "%d s ago",
        "Il y a %d min %02d": "%d min %02d ago",
        "Sur secteur": "On AC power",
        "En charge": "Charging",
        "Charge%@plein dans %@": "Charging%@full in %@",
        "Sur secteur%@chargée": "On AC power%@charged",
        "Sur secteur%@charge en pause": "On AC power%@charging paused",
        "Sur batterie%@%@ restantes": "On battery%@%@ left",
        "Sur batterie": "On battery",
        "Collecte des mesures…": "Collecting samples…",
        "Secteur": "Mains",
        "alimentation": "power supply",
        "consomme": "draws",
        "Chargeur": "Charger",
        "branché": "plugged in",
        "débranché": "unplugged",
        "Batterie %d %%": "Battery %d %%",
        "en charge": "charging",
        "se décharge": "discharging",
        "au repos": "idle",

        // Breakdown, apps
        "Répartition": "Breakdown",
        "Les plus gourmandes": "Top consumers",
        "Mesure en cours…": "Measuring…",
        "Aucune app ne consomme pour l'instant": "No app is drawing power right now",
        "CPU %@ · GPU %@ — clic droit pour les actions": "CPU %@ · GPU %@ — right-click for actions",
        "Basculer vers l'app": "Switch to App",
        "Afficher dans le Finder": "Show in Finder",
        "Copier le chemin": "Copy Path",
        "Quitter": "Quit",
        "Forcer à quitter": "Force Quit",

        // Tabs, battery, ports
        "Apps": "Apps",
        "Batterie": "Battery",
        "Ports & USB": "Ports & USB",
        "Santé": "Health",
        "Cycles": "Cycles",
        "Capacité": "Capacity",
        "%@%d mAh (neuve : %d)": "%@%d mAh (new: %d)",
        "Température": "Temperature",
        "Tension · courant": "Voltage · current",
        "Inconnu": "Unknown",
        "Puissance nominale": "Rated power",
        "Profil négocié": "Negotiated profile",
        "Entrée mesurée": "Measured input",
        "Aucune batterie détectée": "No battery detected",
        "Aucun port ni appareil USB détecté": "No port or USB device detected",
        "macOS ne mesure pas la consommation réelle de chaque port : la valeur USB est le budget réservé par l'appareil. Leur conso réelle est incluse dans « Autres ».":
            "macOS doesn't measure each port's actual draw: the USB value is the budget the device reserved. Their actual draw is included in “Other”.",
        "fournit ≤ %.1f W": "supplies ≤ %.1f W",
        "libre": "free",
        "connecté": "connected",
        "chargeur": "charger",
        "Appareil USB": "USB device",

        // Footer, menus
        "Énergie consommée et puissance moyenne depuis le lancement de Volta (ou la dernière remise à zéro). Clic droit pour remettre à zéro.":
            "Energy used and average power since Volta launched (or the last reset). Right-click to reset.",
        "Remettre à zéro le compteur d'énergie": "Reset Energy Counter",
        "Moniteur d'activité": "Activity Monitor",
        "Réglages": "Settings",
        "Réglages…": "Settings…",
        "Quitter Volta": "Quit Volta",
        "Valeur affichée": "Shown value",
        "%.2f Wh · moy. ": "%.2f Wh · avg. ",

        // Menu bar metrics
        "Puissance du chargeur": "Charger power",
        "Flux batterie": "Battery flow",

        // Alerts
        "Consommation élevée": "High power draw",
        "%@ en moyenne depuis %d min": "%@ on average for %d min",

        // Settings
        "Barre des menus": "Menu Bar",
        "Icône de charge": "Charging icon",
        "Position de l'icône": "Icon position",
        "Alerte": "Alert",
        "La valeur passe en orange au-delà du seuil": "The value turns orange above the threshold",
        "La valeur prend l'accent au-delà du seuil": "The value takes the accent above the threshold",
        "Désactivée": "Off",
        "Alerte prolongée": "Sustained alert",
        "Notification après 2 min au-delà du seuil, avec l'app responsable": "Notifies after 2 min above the threshold, naming the app responsible",
        "Sur batterie seulement": "On battery only",
        "Mesures": "Measurements",
        "Rafraîchissement": "Refresh",
        "Panneau ouvert. Fermé : toutes les 5 s": "Panel open. Closed: every 5 s",
        "Historique": "History",
        "Sections": "Sections",
        "Flux": "Flow",
        "Détails": "Details",
        "Apparence": "Appearance",
        "Style": "Style",
        "Palette": "Palette",
        "Accent": "Accent",
        "Verre": "Glass",
        "Teinte du verre": "Glass tint",
        "Chiffres": "Numbers",
        "Thème": "Theme",
        "Le cadre reste noir dans tous les thèmes": "The frame stays black in every theme",
        "Nuit automatique": "Automatic night",
        "Passe en rouge aux heures choisies, quel que soit le thème": "Turns red at the chosen hours, whatever the theme",
        "Horaires": "Hours",
        "Choisis deux heures différentes": "Pick two different hours",
        "Intensité du rouge": "Red intensity",
        "Ne s'applique qu'en version nuit. Un rouge profond garde la vision de nuit et n'envoie aucune lumière bleue.":
            "Only applies at night. A deep red keeps your night vision and emits no blue light.",
        "La nuit, l'accent est verrouillé sur le rouge": "At night the accent is locked to red",
        "Une seule à la fois": "One at a time",
        "Densité": "Density",
        "Flux d'énergie": "Energy flow",
        "Canal : animé par Core Animation, panneau ouvert seulement": "Channel: animated by Core Animation, only while the panel is open",
        "Animations": "Animations",
        "Confiées à Core Animation : quasi gratuites": "Handed to Core Animation: nearly free",
        "Général": "General",
        "Langue": "Language",
        "Système": "System",
        "Ouvrir au démarrage": "Open at login",
        "À autoriser dans Réglages Système › Général › Ouverture": "Allow it in System Settings › General › Login Items",
        "Version": "Version",
        "Vérifier": "Check",
        "Vérification…": "Checking…",
        "Télécharger %@": "Download %@",
        "Interroge la dernière release GitHub de Volta": "Looks up Volta's latest GitHub release",
        "Volta est à jour": "Volta is up to date",
        "Une nouvelle version est disponible": "A new version is available",
        "Vérification impossible (hors ligne ?)": "Couldn't check (offline?)",
        "Réinitialiser": "Reset",
        "Réinitialiser l'apparence": "Reset Appearance",
        "Couleur du système": "System color",

        // Option labels
        "Classique": "Classic",
        "Océan": "Ocean",
        "Néon": "Neon",
        "Pastel": "Pastel",
        "Mono": "Mono",
        "À gauche": "Left",
        "À droite": "Right",
        "Canal": "Channel",
        "Points": "Dots",
        "Givré": "Frosted",
        "Transparent": "Clear",
        "Aucune": "None",
        "Légère": "Light",
        "Marquée": "Strong",
        "Aérée": "Roomy",
        "Compacte": "Compact",
        "Arrondie": "Rounded",
        "Standard": "Standard",
        "Serif": "Serif",
        "Empilé": "Stacked",
        "Total": "Total",
        "Complètes": "Full",
        "Discrètes": "Subtle",
        "Atelier Glyphe": "Atelier Glyphe",
        "Liquid Glass, palette et accent réglables.": "Liquid Glass, adjustable palette and accent.",
        "Cadre noir en retrait, un seul accent, titres élargis, couches lisibles et ressorts. La nuit, tout passe en rouge.":
            "Inset black frame, a single accent, wide titles, readable layers and springs. At night everything turns red.",
        "Auto": "Auto",
        "Jour": "Day",
        "Sombre": "Dark",
        "Nuit": "Night",
        "Orange": "Orange",
        "Ambre": "Amber",
        "Vert": "Green",
        "Corail": "Coral",
        "Violet": "Violet",
    ]
}

/// Localizes a French source string (returned as is in French, or when no translation exists).
func L(_ french: String) -> String {
    guard Localization.english else { return french }
    return Localization.en[french] ?? french
}

/// Localizes a French format string, then formats it.
func L(_ french: String, _ args: CVarArg...) -> String {
    String(format: L(french), arguments: args)
}
