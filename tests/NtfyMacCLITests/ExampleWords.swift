/// Splits a documented command line the way a shell would, enough for the examples.
enum ExampleWords {
  /// Splits on spaces outside single and double quotes.
  static func split(_ line: String) -> [String] {
    var words: [String] = []
    var current = ""
    var quote: Character?
    for character in line {
      if let open = quote {
        if character == open { quote = nil } else { current.append(character) }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == " " {
        if !current.isEmpty { words.append(current) }
        current = ""
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty { words.append(current) }
    return words
  }
}
