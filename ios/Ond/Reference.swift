import Foundation
import OndKit

/// The reference data every tab reads, over one cached repository.
///
/// Three models rather than one because the screens want them separately, but
/// one repository underneath because they are one fetch story: the catalogue,
/// the foundations, and the routes into both come off the same service, share a
/// cache directory, and degrade together when the server cannot be reached.
///
/// Composed here rather than inline in `OndApp` so the root holds one value
/// instead of three, and so a preview or a test can substitute the reading
/// behind all three at once.
@MainActor
struct Reference {
    let catalogue: TechniqueListModel
    let foundations: FoundationsModel
    let routes: RoutesModel

    init(baseURL: URL, identity: any UserIdentityStore) {
        let techniques = CachedTechniqueRepository(
            caching: TechniqueRepository(baseURL: baseURL, identity: identity)
        )
        catalogue = TechniqueListModel(techniques: techniques)
        foundations = FoundationsModel(topics: techniques)
        routes = RoutesModel(routes: techniques)
    }
}
