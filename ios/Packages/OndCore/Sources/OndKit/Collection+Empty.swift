extension Collection {
    /// Nil where there is nothing here. Two conventions meet: the wire sends
    /// `""` for an absent curated string, and an empty bundled seed means the
    /// resource could not be read — handed the empty list, a caller would draw
    /// "no techniques" as though the server said so, where nil leaves it
    /// waiting for the fetch.
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
