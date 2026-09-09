import Foundation

@main
enum AIPromptTemplateTests {
    static func main() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let context = AIPromptTemplateEngine.ExpansionContext(
            clipboardHistory: [], selection: "", now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: zone, input: " hello {date} & café \n", makeUUID: { "test-uuid" })
        let cases: [(String, String)] = [
            ("Translate: {input}", "Translate:  hello {date} & café \n"),
            ("{input | trim | uppercase}", "HELLO {DATE} & CAFÉ"),
            ("{input | trim | lowercase}", "hello {date} & café"),
            ("{input | trim | percent-encode}", "hello%20%7Bdate%7D%20%26%20caf%C3%A9"),
            ("{input | raw}", " hello {date} & café \n"),
            ("{input | json-stringify}", " hello {date} & café \\n"),
            ("{clipboard}/{clipboard offset=5}/{selection}/{selectedText}", "///"),
            ("{date format=\"yyyy-MM-dd\"}", "1970-01-01"),
            ("{time format=\"HH:mm\" offset=\"+3h +30m\"}", "03:30"),
            ("{date format=\"yyyy-MM-dd\" offset=\"+1y +2M -1d\"}", "1971-02-28"),
            ("{day}", "Thursday"),
            ("{uuid}/{uuid | uppercase}", "test-uuid/TEST-UUID"),
            ("{argument default=\"hello\" | uppercase}", "HELLO"),
            ("{argument name=\"Recipient\"}", "{argument name=\"Recipient\"}"),
            ("{argument options=\"a, b\"}", "{argument options=\"a, b\"}"),
            ("a{cursor}b{cursor}c", "abc"),
            ("{snippet:Old}/{snippet name=\"Old\"}", "{snippet:Old}/{snippet name=\"Old\"}"),
            ("{input | missing}", "{input | missing}"),
            ("{input invalid=x}", "{input invalid=x}"),
            ("{argument name=x name=y}", "{argument name=x name=y}"),
            ("{date format=\"yyyy\" locale=\"fr\"}", "{date format=\"yyyy\" locale=\"fr\"}"),
            ("{input", "{input"),
            ("literal {{input}}", "literal { hello {date} & café \n}"),
            ("{cursor | raw}", "{cursor | raw}"),
            ("{clipboard offset=-1}", "{clipboard offset=-1}")
        ]
        for (source, expected) in cases {
            let actual = AIPromptTemplateEngine.expand(text: source, context: context)
            precondition(actual == expected, "\(source): \(actual.debugDescription) != \(expected.debugDescription)")
        }
        print("\(cases.count) AI prompt template checks passed")
    }
}
