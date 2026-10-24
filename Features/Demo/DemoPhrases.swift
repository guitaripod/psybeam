#if DEBUG
/// A short scripted exchange in every supported language, for screenshots and
/// screen recordings. Even lines are the traveler's, odd lines the local's
/// replies; each is the same sentence in every language, so a demo can show
/// any line in the listener's language and its source in the speaker's.
enum DemoPhrases {
    static let lines: [String: [String]] = [
        "en": [
            "Excuse me, where’s the nearest pharmacy?",
            "It’s just around the corner, on the left.",
            "Thank you! Is it open right now?",
            "Yes, it’s open until nine tonight.",
        ],
        "es": [
            "Disculpe, ¿dónde está la farmacia más cercana?",
            "Está justo a la vuelta de la esquina, a la izquierda.",
            "¡Gracias! ¿Está abierta ahora?",
            "Sí, abre hasta las nueve de la noche.",
        ],
        "fr": [
            "Excusez-moi, où est la pharmacie la plus proche\u{00A0}?",
            "C’est juste au coin de la rue, sur la gauche.",
            "Merci\u{00A0}! Elle est ouverte en ce moment\u{00A0}?",
            "Oui, elle est ouverte jusqu’à 21\u{00A0}heures ce soir.",
        ],
        "de": [
            "Entschuldigung, wo ist die nächste Apotheke?",
            "Gleich um die Ecke, auf der linken Seite.",
            "Danke! Hat sie gerade geöffnet?",
            "Ja, heute Abend bis 21\u{00A0}Uhr.",
        ],
        "it": [
            "Mi scusi, dov’è la farmacia più vicina?",
            "È proprio dietro l’angolo, sulla sinistra.",
            "Grazie! È aperta adesso?",
            "Sì, è aperta fino alle nove stasera.",
        ],
        "pt": [
            "Com licença, onde fica a farmácia mais próxima?",
            "Fica logo ali na esquina, à esquerda.",
            "Obrigado! Ela está aberta agora?",
            "Está, sim. Fica aberta até as nove da noite.",
        ],
        "nl": [
            "Pardon, waar is de dichtstbijzijnde apotheek?",
            "Die is hier vlak om de hoek, aan de linkerkant.",
            "Dank u! Is die nu open?",
            "Ja, vanavond tot negen uur.",
        ],
        "ru": [
            "Извините, где ближайшая аптека?",
            "Прямо за углом, слева.",
            "Спасибо! А она сейчас открыта?",
            "Да, сегодня до девяти вечера.",
        ],
        "pl": [
            "Przepraszam, gdzie jest najbliższa apteka?",
            "Zaraz za rogiem, po lewej stronie.",
            "Dziękuję! Czy jest teraz otwarta?",
            "Tak, dziś do dziewiątej wieczorem.",
        ],
        "tr": [
            "Affedersiniz, en yakın eczane nerede?",
            "Hemen köşeyi dönünce, solda.",
            "Teşekkürler! Şu an açık mı?",
            "Evet, bu akşam dokuza kadar açık.",
        ],
        "el": [
            "Συγγνώμη, πού είναι το πλησιέστερο φαρμακείο;",
            "Είναι ακριβώς στη γωνία, στα αριστερά.",
            "Ευχαριστώ! Είναι ανοιχτό τώρα;",
            "Ναι, είναι ανοιχτό μέχρι τις εννιά απόψε.",
        ],
        "ar": [
            "لو سمحت، أين أقرب صيدلية؟",
            "بعد المنعطف مباشرةً، على اليسار.",
            "شكرًا! هل هي مفتوحة الآن؟",
            "نعم، مفتوحة حتى التاسعة مساءً.",
        ],
        "he": [
            "סליחה, איפה בית המרקחת הכי קרוב?",
            "ממש מעבר לפינה, בצד שמאל.",
            "תודה! הוא פתוח עכשיו?",
            "כן, הוא פתוח עד תשע בערב.",
        ],
        "hi": [
            "माफ़ कीजिए, सबसे नज़दीकी दवा की दुकान कहाँ है?",
            "बस मोड़ के पास ही है, बाईं तरफ़।",
            "शुक्रिया! क्या वह अभी खुली है?",
            "हाँ, आज रात नौ बजे तक खुली है।",
        ],
        "ja": [
            "すみません、一番近い薬局はどこですか？",
            "すぐそこの角を曲がって、左側にありますよ。",
            "ありがとうございます！今開いていますか？",
            "はい、今夜は9時まで開いています。",
        ],
        "ko": [
            "실례합니다, 가장 가까운 약국이 어디예요?",
            "바로 저 모퉁이 돌아서 왼쪽에 있어요.",
            "감사합니다! 지금 문 열었나요?",
            "네, 오늘 밤 9시까지 열어요.",
        ],
        "zh-Hans": [
            "请问，最近的药店在哪里？",
            "就在拐角那儿，左手边。",
            "谢谢！现在还开着吗？",
            "开着呢，今晚营业到九点。",
        ],
        "zh-Hant": [
            "請問，最近的藥局在哪裡？",
            "就在轉角那邊，左手邊。",
            "謝謝！現在還有開嗎？",
            "有喔，今晚營業到九點。",
        ],
        "th": [
            "ขอโทษครับ ร้านขายยาที่ใกล้ที่สุดอยู่ที่ไหนครับ",
            "อยู่ตรงหัวมุมนี่เองค่ะ ทางซ้ายมือ",
            "ขอบคุณครับ ตอนนี้เปิดอยู่ไหมครับ",
            "เปิดค่ะ เปิดถึงสามทุ่มคืนนี้",
        ],
        "vi": [
            "Xin lỗi, hiệu thuốc gần nhất ở đâu ạ?",
            "Ngay góc đường đằng kia, bên tay trái.",
            "Cảm ơn! Bây giờ tiệm có mở cửa không?",
            "Có, tối nay mở đến chín giờ.",
        ],
        "id": [
            "Permisi, apotek terdekat di mana, ya?",
            "Tepat di tikungan itu, di sebelah kiri.",
            "Terima kasih! Sekarang sudah buka?",
            "Sudah, buka sampai jam sembilan malam ini.",
        ],
        "fi": [
            "Anteeksi, missä on lähin apteekki?",
            "Ihan tuossa kulman takana, vasemmalla.",
            "Kiitos! Onko se nyt auki?",
            "On, tänään yhdeksään asti.",
        ],
        "sv": [
            "Ursäkta, var ligger närmaste apotek?",
            "Precis runt hörnet, till vänster.",
            "Tack! Har det öppet nu?",
            "Ja, till nio i kväll.",
        ],
    ]

    /// The phrase-table key for a language tag: Chinese splits by script, so a
    /// Traditional-Chinese storefront never shows Simplified captions.
    static func key(for tag: String) -> String {
        let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.lowercased() }
        guard let base = parts.first else { return "en" }
        if base == "zh" {
            return parts.contains(where: { ["hant", "tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
        }
        return lines[base] == nil ? "en" : base
    }

    /// Line `index` (wrapping) in the language keyed `key`.
    static func line(_ index: Int, in key: String) -> String {
        let table = lines[key] ?? lines["en"] ?? []
        guard !table.isEmpty else { return "" }
        return table[((index % table.count) + table.count) % table.count]
    }
}
#endif
