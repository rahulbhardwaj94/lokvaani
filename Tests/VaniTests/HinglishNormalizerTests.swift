import Foundation
import VaniCore

func hinglishNormalizerTests() {
    func norm(_ s: String) -> String { HinglishNormalizer.normalize(s) }

    // The exact field example: English words restored to Latin, the Hindi
    // (including Whisper's होघा misspelling) left byte-for-byte alone.
    expect(
        norm("शिप इट नौ, क्यूंकि परफेक्ट कभी नहीं होगा"),
        "ship it now, क्यूंकि perfect कभी नहीं होगा"
    )
    expect(
        norm("शिप इट नौ, क्यूंकि परफेक्ट कभी नहीं होघा"),
        "ship it now, क्यूंकि perfect कभी नहीं होघा"
    )

    // Pure Hindi passes through untouched.
    expect(norm("कल हम बात करेंगे और नाम बताएँगे।"), "कल हम बात करेंगे और नाम बताएँगे।")
    expect(norm("मुझे घर जाना है क्योंकि देर हो गई।"), "मुझे घर जाना है क्योंकि देर हो गई।")

    // Pure English passes through untouched (early return, no Devanagari).
    expect(norm("Ship it now, because perfect never comes."),
           "Ship it now, because perfect never comes.")

    // Ambiguous Devanagari spellings that are genuine Hindi words are never
    // replaced: नौ alone is "nine", बस is "enough", कल / बात / नाम / मेल are
    // real Hindi. (नौ converts only inside explicit phrases like इट नौ.)
    expect(norm("मुझे नौ बजे मिलना है"), "मुझे नौ बजे मिलना है")
    expect(norm("बस करो, बहुत हुआ"), "बस करो, बहुत हुआ")
    expect(norm("उन दोनों में अच्छा मेल है"), "उन दोनों में अच्छा मेल है")

    // Dictionary hits inside a Hindi sentence, with punctuation preserved.
    expect(norm("मीटिंग कल है? नहीं, प्रोजेक्ट अपडेट भेजो!"),
           "meeting कल है? नहीं, project update भेजो!")
    expect(norm("(फाइल) सर्वर पर अपलोड करो।"), "(file) server पर upload करो।")

    // Devanagari word boundaries: a mapped spelling embedded inside a longer
    // Devanagari word does not fire (कोड inside कोडांतरण stays put).
    expect(norm("कोडांतरण एक शब्द है"), "कोडांतरण एक शब्द है")
    expect(norm("कोड लिखो"), "code लिखो")

    // Multi-token phrases.
    expect(norm("राइट नौ बताओ"), "right now बताओ")
    expect(norm("थैंक यू, कल मिलते हैं"), "thank you, कल मिलते हैं")

    // Mixed-script input already partially Latin stays consistent.
    expect(norm("please परफेक्ट मत बनो, शिप करो"), "please perfect मत बनो, ship करो")
}
