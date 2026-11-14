import Foundation

@main
@MainActor
struct URLSanitizerTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        // 1. Google / Marketing UTM Stripping
        let utmURL = "https://example.com/blog/article?utm_source=twitter&utm_medium=social&utm_campaign=launch&id=42"
        let res1 = URLSanitizer.sanitize(utmURL)
        expect(res1.hasModifications, "UTM link is modified")
        expect(res1.removedParameters.count == 3, "Removed 3 UTM parameters")
        expect(res1.cleanURL == "https://example.com/blog/article?id=42", "Preserved id parameter: \(res1.cleanURL)")

        // 2. YouTube si Parameter
        let ytURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abcdef123456"
        let res2 = URLSanitizer.sanitize(ytURL)
        expect(res2.hasModifications, "YouTube link modified")
        expect(res2.removedParameters == ["si"], "Removed si parameter")
        expect(res2.cleanURL == "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Clean YouTube URL")

        // 3. Facebook & Instagram Click IDs
        let fbURL = "https://shop.example.com/item?fbclid=IwAR123456789&sku=99"
        let res3 = URLSanitizer.sanitize(fbURL)
        expect(res3.removedParameters == ["fbclid"], "Removed fbclid")
        expect(res3.cleanURL == "https://shop.example.com/item?sku=99", "Preserved sku parameter")

        // 4. Amazon Tracking Parameters
        let amzURL = "https://www.amazon.com/dp/B08N5WRWNW?ref_=cm_sw_r_cp_ud_dp&tag=affil-20&pd_rd_w=xyz"
        let res4 = URLSanitizer.sanitize(amzURL)
        expect(res4.hasModifications, "Amazon link modified")
        expect(res4.removedParameters.count == 3, "Removed all 3 tracking parameters")
        expect(res4.cleanURL == "https://www.amazon.com/dp/B08N5WRWNW", "Clean Amazon URL: \(res4.cleanURL)")

        // 5. Google Redirect Unwrapping
        let googleRedirect = "https://www.google.com/url?q=https%3A%2F%2Fnews.ycombinator.com%2Fitem%3Fid%3D12345%26utm_source%3Dfeed&sa=D&sntz=1"
        let res5 = URLSanitizer.sanitize(googleRedirect)
        expect(res5.wasUnwrapped, "Google redirect was unwrapped")
        expect(res5.cleanURL == "https://news.ycombinator.com/item?id=12345", "Unwrapped destination with utm stripped: \(res5.cleanURL)")

        // 6. Slack Redirect Unwrapping
        let slackRedirect = "https://slack-redir.net/link?url=https%3A%2F%2Fgithub.com%2Fsauravsz%2Fszcast"
        let res6 = URLSanitizer.sanitize(slackRedirect)
        expect(res6.wasUnwrapped, "Slack redirect was unwrapped")
        expect(res6.cleanURL == "https://github.com/sauravsz/szcast", "Clean destination from Slack redirect")

        // 7. Outlook SafeLinks Unwrapping
        let outlookRedirect = "https://safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Freport%3Futm_medium%3Demail&data=05%7C01"
        let res7 = URLSanitizer.sanitize(outlookRedirect)
        expect(res7.wasUnwrapped, "Outlook SafeLink was unwrapped")
        expect(res7.cleanURL == "https://example.com/report", "Clean destination from SafeLink: \(res7.cleanURL)")

        // 8. Already Clean URL
        let cleanURL = "https://wikipedia.org/wiki/Swift_(programming_language)"
        let res8 = URLSanitizer.sanitize(cleanURL)
        expect(!res8.hasModifications, "Already clean URL has no modifications")
        expect(res8.cleanURL == cleanURL, "Clean URL matches original")

        // 9. URL Detection and Extraction from Text
        let sentence = "Check this out: https://example.com/page?utm_source=twitter and let me know!"
        expect(URLSanitizer.containsURL(sentence), "containsURL detects embedded URL")
        let extracted = URLSanitizer.extractURL(from: sentence)
        expect(extracted == "https://example.com/page?utm_source=twitter", "Extracted exact URL from text: \(extracted ?? "")")
        let res9 = URLSanitizer.sanitize(sentence)
        expect(res9.cleanURL == "https://example.com/page", "Sanitized embedded URL: \(res9.cleanURL)")

        // 10. URL with angle brackets
        let bracketed = "<https://github.com/swiftlang?utm_source=gh>"
        let res10 = URLSanitizer.sanitize(bracketed)
        expect(res10.cleanURL == "https://github.com/swiftlang", "Sanitized bracketed URL")

        // 11. Empty input
        let res11 = URLSanitizer.sanitize("")
        expect(!res11.hasModifications, "Empty input handled safely")

        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
