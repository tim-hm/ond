/// The speech bubble that stands for the coach, written once.
///
/// Four surfaces draw it — the tab, the coach's empty room, its offer, and the
/// door on an exercise's own screen — and until this existed each held its own
/// string literal with a comment asking the next person to keep them in step.
/// Three of the four are in different features, so a retune reached them only if
/// whoever made it read the comment.
///
/// At `ios/Ond/` rather than in `OndUI`: it is this app's name for one of its
/// own destinations, and the design system knows nothing about a coach. The
/// symbols the phone shares with the *watch* stay as literals on both sides —
/// escalating those means a package, and one string does not earn a file there.
enum CoachGlyph {
    static let symbol = "bubble.left"
}
