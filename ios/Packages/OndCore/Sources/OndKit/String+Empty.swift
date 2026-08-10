extension String {
    /// Nil where there is nothing here, for the curated strings whose wire
    /// convention is that empty means absent.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
