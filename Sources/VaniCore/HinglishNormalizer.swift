import Foundation

/// Fixes Whisper's script mistakes in code-switched Hindi/English dictation:
/// when a segment is decoded as Hindi, embedded ENGLISH words come out as
/// Devanagari transliterations ("ship it now" → "शिप इट नौ"). The policy is
/// script-per-language — English words stay in Latin script, Hindi words stay
/// in Devanagari — so this maps known transliterations back to their Latin
/// forms.
///
/// Deterministic and dictionary-driven on purpose: only exact curated hits
/// are replaced, never algorithmic transliteration. A wrong "fix" of a real
/// Hindi word is worse than leaving a transliteration, so any Devanagari
/// spelling that collides with a genuine Hindi word is deliberately absent
/// (कल, बात, नाम, बस, मेल, लेट, गोल, सेव, गुड, बिल, बार, दिन, हाल, आम, पास —
/// and नौ, which is Hindi "nine", is only mapped inside explicit phrases
/// like "राइट नौ" where the English reading is unambiguous).
public enum HinglishNormalizer {

    /// Multi-token phrases, matched before single words. Needed where a
    /// token is only safe to convert in context: नौ alone is Hindi "nine",
    /// but after इट/राइट/डू/स्टॉप it can only be English "now".
    static let phrases: [(devanagari: String, latin: String)] = [
        ("शिप इट नौ", "ship it now"),
        ("इट नौ", "it now"),
        ("राइट नौ", "right now"),
        ("डू इट नाउ", "do it now"),
        ("थैंक यू", "thank you"),
        ("गुड मॉर्निंग", "good morning"),
        ("गुड नाइट", "good night"),
        ("गुड लक", "good luck"),
    ]

    /// Devanagari transliteration → Latin form. Exact whole-word matches
    /// only. Curated for precision over recall: every key is a spelling
    /// that, as a standalone word, can only be the English loanword.
    static let words: [String: String] = [
        // The field-reported core.
        "शिप": "ship", "इट": "it", "नाउ": "now", "परफेक्ट": "perfect",

        // Work & scheduling.
        "मीटिंग": "meeting", "मीटिंग्स": "meetings", "प्रोजेक्ट": "project",
        "प्रोजेक्ट्स": "projects", "अपडेट": "update", "अपडेट्स": "updates",
        "डिस्कस": "discuss", "डिटेल": "detail", "डिटेल्स": "details",
        "कॉल": "call", "कॉल्स": "calls", "ईमेल": "email", "फोन": "phone",
        "टाइम": "time", "डेडलाइन": "deadline", "ऑफिस": "office",
        "ऑफ़िस": "office", "वीकेंड": "weekend", "प्लान": "plan",
        "प्लानिंग": "planning", "चेक": "check", "फाइनल": "final",
        "रिपोर्ट": "report", "क्लाइंट": "client", "क्लाइंट्स": "clients",
        "टीम": "team", "मैनेजर": "manager", "इशू": "issue", "इशूज": "issues",
        "शेड्यूल": "schedule", "रीशेड्यूल": "reschedule", "कैलेंडर": "calendar",
        "रिमाइंडर": "reminder", "अपॉइंटमेंट": "appointment", "टास्क": "task",
        "डॉक्यूमेंट": "document", "प्रेजेंटेशन": "presentation",
        "स्लाइड": "slide", "स्लाइड्स": "slides", "रिव्यू": "review",
        "फीडबैक": "feedback", "अप्रूव": "approve", "अप्रूवल": "approval",
        "कन्फर्म": "confirm", "कैंसल": "cancel", "प्रायोरिटी": "priority",
        "अर्जेंट": "urgent", "इंपॉर्टेंट": "important", "एजेंडा": "agenda",
        "फॉलोअप": "followup", "डिस्कशन": "discussion", "नोट्स": "notes",

        // Software & engineering.
        "बिल्ड": "build", "कोड": "code", "बग": "bug", "बग्स": "bugs",
        "फीचर": "feature", "फीचर्स": "features", "रिलीज": "release",
        "रिलीज़": "release", "फिक्स": "fix", "टेस्ट": "test",
        "टेस्टिंग": "testing", "लॉन्च": "launch", "डिप्लॉय": "deploy",
        "डिप्लॉयमेंट": "deployment", "कमिट": "commit", "ब्रांच": "branch",
        "मर्ज": "merge", "रिक्वेस्ट": "request", "रिस्पॉन्स": "response",
        "एरर": "error", "डीबग": "debug", "डेटाबेस": "database",
        "क्वेरी": "query", "एपीआई": "API", "कॉन्फिग": "config",
        "सेटअप": "setup", "सेटिंग्स": "settings", "वर्जन": "version",
        "अपग्रेड": "upgrade", "सर्वर": "server", "डेटा": "data",
        "डाटा": "data", "प्रोडक्शन": "production", "डेवलपर": "developer",
        "डेवलपमेंट": "development", "डिजाइन": "design", "डिज़ाइन": "design",
        "लॉग": "log", "लॉग्स": "logs", "स्क्रिप्ट": "script",

        // Computing & devices.
        "डाउनलोड": "download", "अपलोड": "upload", "इंस्टॉल": "install",
        "फाइल": "file", "फाइल्स": "files", "फोल्डर": "folder",
        "बैकअप": "backup", "पासवर्ड": "password", "लॉगिन": "login",
        "लॉगआउट": "logout", "अकाउंट": "account", "नंबर": "number",
        "मैसेज": "message", "मैसेजेस": "messages", "वीडियो": "video",
        "फोटो": "photo", "फोटोज": "photos", "स्क्रीन": "screen",
        "स्क्रीनशॉट": "screenshot", "कीबोर्ड": "keyboard", "माउस": "mouse",
        "लैपटॉप": "laptop", "बैटरी": "battery", "चार्ज": "charge",
        "चार्जर": "charger", "इंटरनेट": "internet", "वाईफाई": "wifi",
        "ब्राउज़र": "browser", "ब्राउजर": "browser", "वेबसाइट": "website",
        "लिंक": "link", "पेज": "page", "ऐप": "app", "ऐप्स": "apps",
        "सॉफ्टवेयर": "software", "हार्डवेयर": "hardware", "सिस्टम": "system",
        "प्रोसेस": "process", "मेमोरी": "memory", "स्पीड": "speed",
        "नेटवर्क": "network", "डिवाइस": "device", "मोबाइल": "mobile",
        "कैमरा": "camera", "स्पीकर": "speaker", "ब्लूटूथ": "bluetooth",
        "नोटिफिकेशन": "notification", "अलार्म": "alarm", "क्लाउड": "cloud",
        "सिंक": "sync", "रिफ्रेश": "refresh", "रीलोड": "reload",
        "डिलीट": "delete", "कॉपी": "copy", "पेस्ट": "paste", "एडिट": "edit",
        "सर्च": "search", "फिल्टर": "filter", "प्रिंट": "print",
        "स्कैन": "scan", "स्टार्ट": "start", "स्टॉप": "stop",
        "रीस्टार्ट": "restart", "ऑनलाइन": "online", "ऑफलाइन": "offline",
        "इम्पोर्ट": "import", "एक्सपोर्ट": "export", "प्रोफाइल": "profile",
        "स्टेटस": "status",

        // Business & daily professional life.
        "कंपनी": "company", "स्टार्टअप": "startup", "बिजनेस": "business",
        "मार्केटिंग": "marketing", "सेल्स": "sales", "टारगेट": "target",
        "ग्रोथ": "growth", "रेवेन्यू": "revenue", "प्रॉफिट": "profit",
        "बजट": "budget", "इनवॉइस": "invoice", "पेमेंट": "payment",
        "डील": "deal", "कॉन्ट्रैक्ट": "contract", "पार्टनर": "partner",
        "कस्टमर": "customer", "सर्विस": "service", "सपोर्ट": "support",
        "ऑर्डर": "order", "डिलीवरी": "delivery", "टिकट": "ticket",
        "बुकिंग": "booking", "इंटरव्यू": "interview", "जॉब": "job",
        "सैलरी": "salary", "बॉस": "boss", "एचआर": "HR",
        "प्रॉब्लम": "problem", "सॉल्यूशन": "solution", "आइडिया": "idea",
        "क्वेश्चन": "question", "आंसर": "answer", "चैट": "chat",
        "ग्रुप": "group", "पोस्ट": "post", "शेयर": "share",
        "कमेंट": "comment", "ब्रेक": "break", "लंच": "lunch",
        "डिनर": "dinner", "ब्रेकफास्ट": "breakfast", "ट्रैफिक": "traffic",
        "कैब": "cab", "फ्लाइट": "flight", "होटल": "hotel",
        "एयरपोर्ट": "airport", "हॉस्पिटल": "hospital", "डॉक्टर": "doctor",
        "स्कूल": "school", "कॉलेज": "college", "क्लास": "class",
        "एग्जाम": "exam", "रिजल्ट": "result", "शॉपिंग": "shopping",
        "मूवी": "movie", "म्यूजिक": "music", "गेम": "game", "गेम्स": "games",

        // Common short interjections / adjectives (loan-only spellings).
        "ओके": "okay", "सॉरी": "sorry", "थैंक्स": "thanks", "प्लीज": "please",
        "नाइस": "nice", "ग्रेट": "great", "बेस्ट": "best", "रेडी": "ready",
        "डन": "done", "फास्ट": "fast", "क्विक": "quick", "सिंपल": "simple",
        "ईजी": "easy", "फ्री": "free", "बिजी": "busy", "अपसेट": "upset",
    ]

    /// Matches a Devanagari phrase only when not glued to more Devanagari
    /// letters on either side, so it never fires mid-word.
    private static func replacePhrase(
        _ phrase: String, with latin: String, in text: String
    ) -> String {
        let pattern = "(?<![\\p{Devanagari}])" + NSRegularExpression.escapedPattern(for: phrase)
            + "(?![\\p{Devanagari}])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: latin))
    }

    /// Returns `text` with known English-word transliterations restored to
    /// Latin script. Hindi words, punctuation, and spacing are untouched;
    /// text without Devanagari passes through unchanged.
    public static func normalize(_ text: String) -> String {
        let hasDevanagari = text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        guard hasDevanagari else { return text }

        var result = text
        for (devanagari, latin) in phrases {
            result = replacePhrase(devanagari, with: latin, in: result)
        }

        // Whole-word pass: Foundation's word enumeration handles Devanagari
        // boundaries (and leaves punctuation outside the ranges), so exact
        // dictionary hits swap in place with everything around them intact.
        var replacements: [(Range<String.Index>, String)] = []
        result.enumerateSubstrings(in: result.startIndex..., options: .byWords) { word, range, _, _ in
            if let word, let latin = words[word] {
                replacements.append((range, latin))
            }
        }
        for (range, latin) in replacements.reversed() {
            result.replaceSubrange(range, with: latin)
        }
        return result
    }
}
