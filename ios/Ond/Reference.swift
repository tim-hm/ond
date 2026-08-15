import Foundation
import OndKit

/// The reference data every tab reads, over one cached repository.
///
/// Three models rather than one because the screens want them separately, but
/// one repository underneath because they are one fetch story: the catalogue,
/// the foundations, and the occasions into both come off the same service, share a
/// cache directory, and degrade together when the server cannot be reached.
///
/// Composed here rather than inline in `OndApp` so the root holds one value
/// instead of three, and so a preview or a test can substitute the reading
/// behind all three at once.
@MainActor
struct Reference {
    let catalogue: TechniqueListModel
    let foundations: FoundationsModel
    let occasions: OccasionCatalogueModel

    init(baseURL: URL, identity: any UserIdentityStore) {
        let references = CachedReferenceRepository(
            caching: TechniqueRepository(baseURL: baseURL, identity: identity)
        )
        catalogue = TechniqueListModel(techniques: references)
        foundations = FoundationsModel(topics: references)
        occasions = OccasionCatalogueModel(occasions: references)
    }

    /// Refreshes every public reference source together. Each model owns and
    /// deduplicates its request, so view loads may safely overlap this call.
    func refresh() async {
        async let catalogueRefresh: Void = catalogue.refresh()
        async let foundationsRefresh: Void = foundations.refresh()
        async let routesRefresh: Void = occasions.refresh()
        _ = await (catalogueRefresh, foundationsRefresh, routesRefresh)
    }
}
