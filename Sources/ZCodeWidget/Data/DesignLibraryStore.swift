import Foundation

/// One color in a design direction's palette.
struct DesignSwatch: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var hex: String

    init(id: String = UUID().uuidString, name: String, hex: String) {
        self.id = id
        self.name = name
        self.hex = hex
    }
}

/// A real-world site that exemplifies a design direction.
struct DesignReference: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var url: String?

    init(id: String = UUID().uuidString, name: String, url: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// A design direction: palette, typography, imagery, layout, page-by-page
/// application notes, UI details, and reference sites.
struct DesignEntry: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var tagline: String
    var tags: [String]          // filter chips; kept lowercase
    var brandFit: String
    var swatches: [DesignSwatch]
    var typography: String
    var imagery: String
    var layout: String
    var notesHome: String
    var notesListing: String
    var notesDetail: String
    var notesCheckout: String
    var uiNotes: String
    var references: [DesignReference]
    var isBuiltin: Bool

    init(id: String = UUID().uuidString,
         name: String,
         tagline: String = "",
         tags: [String] = [],
         brandFit: String = "",
         swatches: [DesignSwatch] = [],
         typography: String = "",
         imagery: String = "",
         layout: String = "",
         notesHome: String = "",
         notesListing: String = "",
         notesDetail: String = "",
         notesCheckout: String = "",
         uiNotes: String = "",
         references: [DesignReference] = [],
         isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.tags = tags
        self.brandFit = brandFit
        self.swatches = swatches
        self.typography = typography
        self.imagery = imagery
        self.layout = layout
        self.notesHome = notesHome
        self.notesListing = notesListing
        self.notesDetail = notesDetail
        self.notesCheckout = notesCheckout
        self.uiNotes = uiNotes
        self.references = references
        self.isBuiltin = isBuiltin
    }
}

/// Loads/saves ~/.zcode/design-library.json and seeds the curated built-in
/// directions. Same conventions as PromptLibraryStore: the file is
/// user-visible and editable, so it survives reinstalls and can be shared.
final class DesignLibraryStore: ObservableObject {
    @Published var entries: [DesignEntry] = []
    @Published var loadError: String?

    /// Default: user-visible. Overridable for tests.
    static var libraryPath = NSHomeDirectory() + "/.zcode/design-library.json"
    static let tags = ["minimal", "luxury", "streetwear", "heritage", "performance", "playful", "boho"]

    private var fileURL: URL { URL(fileURLWithPath: Self.libraryPath) }

    func load() {
        loadError = nil
        if FileManager.default.fileExists(atPath: Self.libraryPath) {
            do {
                let data = try Data(contentsOf: fileURL)
                entries = try Self.decoder.decode([DesignEntry].self, from: data)
                return
            } catch {
                loadError = "Could not read design-library.json: \(error.localizedDescription)"
                entries = []
            }
        }
        entries = Self.builtins
        save()
    }

    func save() {
        do {
            let data = try Self.encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Could not write design-library.json: \(error.localizedDescription)"
        }
    }

    func upsert(_ entry: DesignEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        save()
    }

    func remove(_ entry: DesignEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// A user-editable copy of a built-in (new id, not marked built-in).
    func duplicate(_ entry: DesignEntry) -> DesignEntry {
        var copy = entry
        copy.id = UUID().uuidString
        copy.isBuiltin = false
        copy.name = entry.name + " copy"
        return copy
    }

    /// Re-seed any curated built-ins the user deleted (custom entries are kept).
    func restoreDefaults() {
        for builtin in Self.builtins where !entries.contains(where: { $0.id == builtin.id }) {
            entries.append(builtin)
        }
        save()
    }

    /// Built-ins first, then user entries, alphabetical within each group.
    var sorted: [DesignEntry] {
        entries.sorted {
            let lhs = ($0.isBuiltin ? 0 : 1, $0.name.lowercased())
            let rhs = ($1.isBuiltin ? 0 : 1, $1.name.lowercased())
            return lhs < rhs
        }
    }

    /// All tags present in the library (built-in set + any user tags).
    var allTags: [String] {
        var result = Self.tags
        for entry in entries {
            for tag in entry.tags where !result.contains(tag) {
                result.append(tag)
            }
        }
        return result
    }

    // MARK: - Export

    /// The entry as a copy-pasteable design brief.
    static func briefMarkdown(for entry: DesignEntry) -> String {
        var lines: [String] = []
        lines.append("# \(entry.name)")
        if !entry.tagline.isEmpty { lines.append("> \(entry.tagline)") }
        lines.append("")
        if !entry.swatches.isEmpty {
            lines.append("**Palette:** " + entry.swatches
                .map { "\($0.name) `\($0.hex)`" }
                .joined(separator: " · "))
            lines.append("")
        }
        if !entry.typography.isEmpty { lines.append("**Typography:** \(entry.typography)") }
        if !entry.imagery.isEmpty { lines.append("**Imagery:** \(entry.imagery)") }
        if !entry.layout.isEmpty { lines.append("**Layout:** \(entry.layout)") }
        if !entry.brandFit.isEmpty {
            lines.append("")
            lines.append("**Best for:** \(entry.brandFit)")
        }
        if ![entry.notesHome, entry.notesListing, entry.notesDetail, entry.notesCheckout]
            .allSatisfy({ $0.isEmpty }) {
            lines.append("")
            lines.append("## Page applications")
            if !entry.notesHome.isEmpty { lines.append("- **Home:** \(entry.notesHome)") }
            if !entry.notesListing.isEmpty { lines.append("- **Category/PLP:** \(entry.notesListing)") }
            if !entry.notesDetail.isEmpty { lines.append("- **Product/PDP:** \(entry.notesDetail)") }
            if !entry.notesCheckout.isEmpty { lines.append("- **Cart/Checkout:** \(entry.notesCheckout)") }
        }
        if !entry.uiNotes.isEmpty {
            lines.append("")
            lines.append("## UI details")
            lines.append(entry.uiNotes)
        }
        if !entry.references.isEmpty {
            lines.append("")
            lines.append("**References:** " + entry.references
                .map { ref -> String in
                    guard let url = ref.url else { return ref.name }
                    return "[\(ref.name)](\(url))"
                }
                .joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Curated library

    static let builtins: [DesignEntry] = [
        DesignEntry(
            id: "builtin.design.editorial-minimal",
            name: "Editorial Minimal",
            tagline: "Fashion-as-art restraint — whitespace is the luxury.",
            tags: ["minimal", "ecommerce"],
            brandFit: "Minimalist basics, premium contemporary, slow/sustainable fashion.",
            swatches: [
                DesignSwatch(name: "Bone", hex: "#FAF8F5"),
                DesignSwatch(name: "Ink", hex: "#141414"),
                DesignSwatch(name: "Greige", hex: "#E5E0D8"),
                DesignSwatch(name: "Rust accent", hex: "#9C4A2F"),
            ],
            typography: "High-contrast serif display (Fraunces, Editorial New) + neutral sans UI (Instrument Sans). Wide-tracked uppercase micro-labels.",
            imagery: "Clean studio shots on seamless backdrops, soft daylight, generous negative space; one full-bleed lookbook hero per season.",
            layout: "Asymmetric editorial grid, hairline rules, oversized index numbers, near-print composition.",
            notesHome: "Full-bleed seasonal hero, one line of copy, one text-link CTA. No badges, no urgency.",
            notesListing: "2-column large imagery, minimal filter bar, wide row spacing. Hover swaps flat-lay to model shot.",
            notesDetail: "60/40 split — image stack left, quiet sticky buy module right; fabric/care in an accordion.",
            notesCheckout: "Slide-in drawer, monochrome, serif totals, text-only continue link; single focused checkout page.",
            uiNotes: "Black-fill primary button, 2px radius; secondary actions as underlined text links. Centered logo, categories split left/right. Very high whitespace. Mobile: single column, full-screen menu, sticky bottom add-to-bag.",
            references: [
                DesignReference(name: "COS", url: "https://www.cos.com"),
                DesignReference(name: "Toteme", url: "https://toteme.com"),
                DesignReference(name: "Everlane", url: "https://www.everlane.com"),
                DesignReference(name: "ARKET", url: "https://www.arket.com"),
            ]),
        DesignEntry(
            id: "builtin.design.quiet-luxury",
            name: "Quiet Luxury",
            tagline: "Hushed, cinematic, old-money warmth — everything whispers.",
            tags: ["luxury", "ecommerce"],
            brandFit: "Luxury, occasionwear, high AOV, 30+ clientele.",
            swatches: [
                DesignSwatch(name: "Ivory", hex: "#F5F0E8"),
                DesignSwatch(name: "Champagne", hex: "#EAE0D0"),
                DesignSwatch(name: "Taupe", hex: "#C8BBA6"),
                DesignSwatch(name: "Charcoal", hex: "#2B2926"),
                DesignSwatch(name: "Gold", hex: "#A88B5C"),
            ],
            typography: "Refined serif (Cormorant Garamond, Canela) + letterspaced small-cap sans (Jost).",
            imagery: "Large art-directed campaign photography, muted tones, fabric close-ups, subtle film grain; video as ambience, not promotion.",
            layout: "Cinematic full-viewport sections, centered symmetry, slow cross-fade transitions.",
            notesHome: "Full-screen campaign still or muted video loop, tiny centered nav, no visible CTA until scroll.",
            notesListing: "3-column muted grid, generous gutters, hover reveals alternate styling shot; prices set small and letterspaced.",
            notesDetail: "Fabric-macro gallery with zoom, 'The Making' tab alongside Details; measurements rendered as a spec sheet.",
            notesCheckout: "Single-page checkout with concierge microcopy; gift-wrap and monogram options surfaced inline.",
            uiNotes: "Thin-bordered ghost buttons, letterspaced uppercase labels, slow fade fill on hover. Very high whitespace. Mobile: elegant full-screen menu overlay, generous tap targets.",
            references: [
                DesignReference(name: "The Row", url: "https://www.therow.com"),
                DesignReference(name: "Khaite", url: "https://khaite.com"),
                DesignReference(name: "Celine", url: "https://www.celine.com"),
                DesignReference(name: "Moda Operandi", url: "https://www.modaoperandi.com"),
            ]),
        DesignEntry(
            id: "builtin.design.brutalist-streetwear",
            name: "Brutalist Streetwear",
            tagline: "Loud, high-contrast, anti-design confidence — the site is a poster.",
            tags: ["streetwear", "ecommerce"],
            brandFit: "Streetwear, hype drops, limited runs, Gen-Z audiences.",
            swatches: [
                DesignSwatch(name: "Black", hex: "#0A0A0A"),
                DesignSwatch(name: "White", hex: "#F2F2F2"),
                DesignSwatch(name: "Volt", hex: "#DFFF00"),
                DesignSwatch(name: "Safety Orange", hex: "#FF4D00"),
            ],
            typography: "Oversized condensed grotesque (Anton, Druk, Archivo Expanded) + monospace labels and prices (Space Mono).",
            imagery: "Raw flash photography, harsh crops, logo/sticker overlays, product on plain backdrops.",
            layout: "Exposed grids with thick 2px borders, marquee tickers, text overlapping imagery.",
            notesHome: "Full-bleed drop announcement with countdown ticker and marquee strip of upcoming releases.",
            notesListing: "Tight 3–4 column grid, size availability inline on hover, sold-out items visible — scarcity is the message.",
            notesDetail: "Numbered spec-sheet layout (01/FABRIC, 02/FIT) in mono; sticky bold buy module with stock counter.",
            notesCheckout: "Full-page cart (not a drawer) with free-shipping progress bar, order notes, restock notifications.",
            uiNotes: "Chunky solid buttons with hard offset shadows, all-uppercase. Announcement marquee + image-led mega-menu. Low–medium whitespace. Mobile: swipeable carousels, bottom-sheet cart.",
            references: [
                DesignReference(name: "SSENSE", url: "https://www.ssense.com"),
                DesignReference(name: "Palace", url: "https://www.palaceskateboards.com"),
                DesignReference(name: "Brain Dead", url: "https://wearebraindead.com"),
                DesignReference(name: "END.", url: "https://www.endclothing.com"),
            ]),
        DesignEntry(
            id: "builtin.design.heritage-archive",
            name: "Heritage Archive",
            tagline: "Vintage workwear warmth — a mail-order catalog, rebuilt.",
            tags: ["heritage", "ecommerce"],
            brandFit: "Vintage, workwear, denim, heritage outdoor.",
            swatches: [
                DesignSwatch(name: "Paper", hex: "#F2EBDD"),
                DesignSwatch(name: "Rust", hex: "#B4552D"),
                DesignSwatch(name: "Olive", hex: "#6B6B47"),
                DesignSwatch(name: "Indigo", hex: "#3B4A5C"),
            ],
            typography: "Slab serif or condensed gothic (Alfa Slab One, Knockout) + typewriter mono for specs and dates (IBM Plex Mono).",
            imagery: "Grainy archival photography, film-scan borders, stitched/patched label graphics, flat-lays on kraft paper.",
            layout: "Catalog grid with bordered cells, ruled dividers, stamp-like badges (EST., Made in USA).",
            notesHome: "Split hero — campaign photo left, new-arrivals ticker right; brand-story strip with archive photos beneath.",
            notesListing: "Catalog grid on paper texture; filter chips styled like postal stamps; mono item numbers.",
            notesDetail: "Construction close-ups (stitching, hardware), 'Built to last' spec table, care/repair section — durability is the selling point.",
            notesCheckout: "Receipt-styled cart in mono type, line items like an invoice, handwritten thank-you note.",
            uiNotes: "Stamp/pill buttons with letterpress feel; classic top nav + utility strip (shipping, returns, phone). Medium whitespace. Mobile: compact 2-column grid, ledger-style filter accordion.",
            references: [
                DesignReference(name: "Carhartt WIP", url: "https://www.carhartt-wip.com"),
                DesignReference(name: "RRL", url: "https://www.ralphlauren.com/rl"),
                DesignReference(name: "Grailed", url: "https://www.grailed.com"),
                DesignReference(name: "Pendleton", url: "https://www.pendleton-usa.com"),
            ]),
        DesignEntry(
            id: "builtin.design.performance-tech",
            name: "Performance Tech",
            tagline: "Energetic and engineered — the site moves like the clothes.",
            tags: ["performance", "ecommerce"],
            brandFit: "Activewear, athleisure, run/training performance brands.",
            swatches: [
                DesignSwatch(name: "Graphite", hex: "#0E1116"),
                DesignSwatch(name: "Panel", hex: "#161B23"),
                DesignSwatch(name: "Cobalt", hex: "#2E6BFF"),
                DesignSwatch(name: "Coral", hex: "#FF5A3C"),
            ],
            typography: "Condensed industrial sans, uppercase (Archivo Black/Archivo Narrow, Roboto Condensed); big numerals for sizes and prices.",
            imagery: "Action and motion photography, sweat-and-motion video loops, top-down product flats, tech-callout diagrams.",
            layout: "Full-bleed video hero, horizontal scroll shelves, dense spec-driven sections.",
            notesHome: "Video hero plus activity tiles (Run/Train/Yoga) as the primary navigation metaphor.",
            notesListing: "Dense 4-column grid with quick filters by activity and feature; star ratings visible in-grid.",
            notesDetail: "Benefit-first bullets, interactive tech hotspots on the garment photo, video demo slot, size finder front and center.",
            notesCheckout: "Compact drawer with express-pay buttons dominant — speed communicates performance.",
            uiNotes: "Solid accent-fill rounded CTA; nav transparent over the hero, solidifies on scroll. Medium whitespace. Mobile: sticky bottom add-to-cart, swipeable category tabs.",
            references: [
                DesignReference(name: "Nike", url: "https://www.nike.com"),
                DesignReference(name: "lululemon", url: "https://shop.lululemon.com"),
                DesignReference(name: "Gymshark", url: "https://www.gymshark.com"),
                DesignReference(name: "Alo Yoga", url: "https://www.aloyoga.com"),
            ]),
        DesignEntry(
            id: "builtin.design.playful-dtc",
            name: "Playful DTC",
            tagline: "Joyful, candy-colored, personality-first — the brand is a friend.",
            tags: ["playful", "ecommerce"],
            brandFit: "Gen-Z/millennial DTC, fun contemporary, accessories. Tolerates average photography best.",
            swatches: [
                DesignSwatch(name: "Tomato", hex: "#FF5436"),
                DesignSwatch(name: "Butter", hex: "#FFD23F"),
                DesignSwatch(name: "Sky", hex: "#7EC8FF"),
                DesignSwatch(name: "Mint", hex: "#9FE7C0"),
                DesignSwatch(name: "Cream", hex: "#FFF8EC"),
            ],
            typography: "Chunky friendly sans (Bricolage Grotesque, PP Neue Machina) + humanist body (Karla).",
            imagery: "Bright lifestyle shots, real-customer/UGC photos, playful product styling, animated sticker badges.",
            layout: "Rounded cards, sticker badges, soft shadows, scrolling marquees, color-blocked sections.",
            notesHome: "Color-blocked sections, rotating 'shop by vibe' chips, playful announcement marquee.",
            notesListing: "2–3 column rounded cards with per-product color swatch dots; New!/Back-in-stock stickers.",
            notesDetail: "Emoji-scale reviews, 'Complete the look' outfit builder, photo reviews pinned near the buy button.",
            notesCheckout: "Gamified free-shipping progress bar, gift-note field, warm one-tap upsells.",
            uiNotes: "Pill buttons with hover bounce, thick dark outlines as the secondary style. Sticky announcement bar. Medium whitespace. Mobile: oversized tap targets, sticky cart button.",
            references: [
                DesignReference(name: "Telfar", url: "https://www.telfar.net"),
                DesignReference(name: "Ganni", url: "https://www.ganni.com"),
                DesignReference(name: "Lisa Says Gah", url: "https://lisasaysgah.com"),
                DesignReference(name: "Baggu", url: "https://baggu.com"),
            ]),
        DesignEntry(
            id: "builtin.design.romantic-boho",
            name: "Romantic Boho",
            tagline: "Warm, feminine, sun-washed nostalgia — golden hour as a website.",
            tags: ["boho", "ecommerce"],
            brandFit: "Boho, feminine contemporary, occasion/bridesmaid, sustainable capsule brands.",
            swatches: [
                DesignSwatch(name: "Oat", hex: "#FAF4EC"),
                DesignSwatch(name: "Terracotta", hex: "#C97B5A"),
                DesignSwatch(name: "Sage", hex: "#A8B5A0"),
                DesignSwatch(name: "Blush", hex: "#EED5CE"),
            ],
            typography: "Elegant serif with italic accents (Playfair Display, Canela) + humanist sans (Karla).",
            imagery: "Golden-hour lifestyle photography, film grain, linen/fabric textures, journal-style flatlays.",
            layout: "Collage composition with overlapping images, arch-shaped image masks, soft curves over hard rectangles.",
            notesHome: "Full-width seasonal mood hero, then alternating editorial story blocks ('The Dress Edit', 'Meet the Makers').",
            notesListing: "Soft grid with hover 'styled with' suggestions; category headers as italic script over photos.",
            notesDetail: "Romantic close-ups, styling notes, community fit notes ('fits true to size'), wishlist prominent.",
            notesCheckout: "Gentle drawer with save-for-later wishlisting; fabric-swatch samples offered at checkout.",
            uiNotes: "Soft rounded buttons with thin borders; underlined links; airy top bar with serif logotype. High whitespace. Mobile: image-led cards, thumb-friendly bottom filter sheet.",
            references: [
                DesignReference(name: "Free People", url: "https://www.freepeople.com"),
                DesignReference(name: "Sézane", url: "https://www.sezane.com"),
                DesignReference(name: "Reformation", url: "https://www.thereformation.com"),
                DesignReference(name: "Dôen", url: "https://www.doen.com"),
            ]),
    ]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()
}
