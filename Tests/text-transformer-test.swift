import Foundation

@main
struct TextTransformerTest {
    static func main() {
        print("Testing TextTransformer...")

        testCasing()
        testLines()
        testEncoding()
        testFormatting()
        testMetrics()

        print("TextTransformerTest passed successfully.")
    }

    static func testCasing() {
        assert(TextTransformEngine.transform("hello world foo", using: .camelCase) == "helloWorldFoo")
        assert(TextTransformEngine.transform("hello_world_foo", using: .pascalCase) == "HelloWorldFoo")
        assert(TextTransformEngine.transform("helloWorldFoo", using: .snakeCase) == "hello_world_foo")
        assert(TextTransformEngine.transform("HelloWorldFoo", using: .kebabCase) == "hello-world-foo")
        assert(TextTransformEngine.transform("helloWorld", using: .constantCase) == "HELLO_WORLD")
        assert(TextTransformEngine.transform("hello world", using: .titleCase) == "Hello World")
        assert(TextTransformEngine.transform("hello world. foo bar!", using: .sentenceCase) == "Hello world. Foo bar!")
        assert(TextTransformEngine.transform("HELLO WORLD", using: .lowercase) == "hello world")
        assert(TextTransformEngine.transform("hello world", using: .uppercase) == "HELLO WORLD")
        assert(TextTransformEngine.transform("hello", using: .alternatingCase) == "hElLo")
    }

    static func testLines() {
        assert(TextTransformEngine.transform("cherry\napple\nbanana", using: .sortAZ) == "apple\nbanana\ncherry")
        assert(TextTransformEngine.transform("apple\ncherry\nbanana", using: .sortZA) == "cherry\nbanana\napple")
        assert(TextTransformEngine.transform("a\nb\na\nc\nb", using: .deduplicate) == "a\nb\nc")
        assert(TextTransformEngine.transform("1\n2\n3", using: .reverseLines) == "3\n2\n1")
        assert(TextTransformEngine.transform("a\n\n  \nb", using: .stripBlankLines) == "a\nb")
        assert(TextTransformEngine.transform("first\nsecond", using: .numberLines) == "1. first\n2. second")
        assert(TextTransformEngine.transform("  hello  \n  world ", using: .trimLines) == "hello\nworld")
        assert(TextTransformEngine.transform("first\nsecond\nthird", using: .joinLines) == "first second third")
    }

    static func testEncoding() {
        let urlEncoded = TextTransformEngine.transform("hello world & more", using: .urlEncode)
        assert(urlEncoded.contains("%20"))
        assert(TextTransformEngine.transform(urlEncoded, using: .urlDecode) == "hello world & more")

        let b64 = TextTransformEngine.transform("Hello, World!", using: .base64Encode)
        assert(b64 == "SGVsbG8sIFdvcmxkIQ==")
        assert(TextTransformEngine.transform("SGVsbG8sIFdvcmxkIQ==", using: .base64Decode) == "Hello, World!")

        let htmlEncoded = TextTransformEngine.transform("<h1>\"Hello\" & 'World'</h1>", using: .htmlEntityEncode)
        assert(htmlEncoded == "&lt;h1&gt;&quot;Hello&quot; &amp; &#39;World&#39;&lt;/h1&gt;")
        assert(TextTransformEngine.transform(htmlEncoded, using: .htmlEntityDecode) == "<h1>\"Hello\" & 'World'</h1>")

        let hex = TextTransformEngine.transform("ABC", using: .hexEncode)
        assert(hex == "414243")
        assert(TextTransformEngine.transform("414243", using: .hexDecode) == "ABC")
    }

    static func testFormatting() {
        let jsonRaw = "{\"b\":2,\"a\":1}"
        let pretty = TextTransformEngine.transform(jsonRaw, using: .jsonPrettify)
        assert(pretty.contains("\n  \"a\" : 1"))
        let mini = TextTransformEngine.transform(pretty, using: .jsonMinify)
        assert(!mini.contains("\n"))

        let dirtyURL = "https://example.com/page?utm_source=newsletter&utm_medium=email&target=dashboard"
        let cleanURL = TextTransformEngine.transform(dirtyURL, using: .stripTrackingURL)
        assert(!cleanURL.contains("utm_source"))
        assert(cleanURL.contains("target=dashboard"))

        let md = "# Header\n**Bold text** with [link](https://szcast.dev) and `code`"
        let strippedMD = TextTransformEngine.transform(md, using: .stripMarkdown)
        assert(!strippedMD.contains("#"))
        assert(!strippedMD.contains("**"))
        assert(strippedMD.contains("Bold text with link and code"))

        let html = "<div>Hello <b>World</b>!</div>"
        let strippedHTML = TextTransformEngine.transform(html, using: .stripHTML)
        assert(strippedHTML == "Hello World!")

        let spaces = "Line one    with   spaces\nLine   two\t\twith tabs"
        let normalized = TextTransformEngine.transform(spaces, using: .normalizeWhitespace)
        assert(normalized == "Line one with spaces\nLine two with tabs")

        let slug = TextTransformEngine.transform("Hello World! 2026 Guide & Release", using: .slugify)
        assert(slug == "hello-world-2026-guide-release")
    }

    static func testMetrics() {
        let text = "Hello world!\nThis is line 2."
        let metrics = TextMetrics(text: text)
        assert(metrics.lines == 2)
        assert(metrics.words == 6)
        assert(metrics.characters == text.count)
        assert(metrics.bytes == text.utf8.count)

        let emptyMetrics = TextMetrics(text: "")
        assert(emptyMetrics.words == 0)
        assert(emptyMetrics.lines == 0)
        assert(emptyMetrics.characters == 0)
    }
}
