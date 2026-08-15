extension Collection {
    /// Nil where there is nothing here.
    ///
    /// Two conventions meet in this one line. The curated strings' wire
    /// convention is that empty means absent, so a technique with no safety
    /// note sends `""` rather than omitting the field. And an empty bundled
    /// seed means the resource could not be read rather than a catalogue with
    /// nothing in it — a caller handed the empty list would draw "no
    /// techniques" as though the server had said so, where nil leaves it
    /// waiting for the fetch, which is the behaviour that predates the seed.
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
