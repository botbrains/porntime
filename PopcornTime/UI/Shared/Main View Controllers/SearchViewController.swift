

import UIKit
import AlamofireImage
import PopcornKit

class SearchViewController: MainViewController, UISearchBarDelegate {
    
    #if os(iOS)
    
    @IBOutlet var searchBar: UISearchBar!
    @IBOutlet var toolbar: UIToolbar!
    @IBOutlet var segmentedControl: UISegmentedControl!
    
    #elseif os(tvOS)
    
    var searchBar: UISearchBar!
    var searchController: UISearchController!
    var searchContainerViewController: UISearchContainerViewController?
    
    #endif

    let searchDelay: TimeInterval = 0.25
    var workItem: DispatchWorkItem!
    private var activeSearchToken = UUID()
    
    var fetchType: Trakt.MediaType = .movies
    
    override func load(page: Int) {
        filterSearchText(searchBar?.text ?? "")
    }
    
    
    override func minItemSize(forCellIn collectionView: UICollectionView, at indexPath: IndexPath) -> CGSize? {
        if UIDevice.current.userInterfaceIdiom == .tv {
            return CGSize(width: 250, height: fetchType == .people ? 400 : 460)
        } else {
            return CGSize(width: 108, height: fetchType == .people ? 160 : 185)
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        #if os(iOS)
        if segmentedControl.numberOfSegments == 2 {
            switch selectedScope {
            case 0:
                fetchType = .movies
            case 1:
                fetchType = .people
            default:
                return
            }
            filterSearchText(searchBar.text ?? "")
            return
        }
        #endif

        switch selectedScope {
        case 0:
            fetchType = .movies
        case 1:
            fetchType = .shows
        case 2:
            fetchType = .people
        default: return
        }
        filterSearchText(searchBar.text ?? "")
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        workItem?.cancel()
        
        workItem = DispatchWorkItem {
            self.filterSearchText(searchText)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + searchDelay, execute: workItem)
    }
    
    func filterSearchText(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)

        activeSearchToken = UUID()
        collectionViewController.error = nil
        collectionViewController.isLoading = !query.isEmpty
        collectionViewController.dataSources = [[]]
        collectionView?.reloadData()
        
        if query.isEmpty { return }

        let searchToken = activeSearchToken
        
        let completion: ([AnyHashable]?, NSError?) -> Void = { [weak self] (data, error) in
            guard let self = self, self.activeSearchToken == searchToken else { return }

            self.collectionViewController.dataSources = [data ?? []]
            self.collectionViewController.error = error
            self.collectionViewController.isLoading = false
            self.collectionView?.reloadData()
        }
        
        switch fetchType {
        case .movies:
            JackettManager.shared.load(page: 1, query: query) { results, error in
                completion(results?.map(AnyHashable.init), error)
            }
        case .shows:
            JackettManager.shared.load(page: 1, query: query) { results, error in
                completion(results?.map(AnyHashable.init), error)
            }
        case .people:
            TraktManager.shared.search( forPerson: query) { people, error in
                completion(people as? [AnyHashable], error)
            }
        default:
            return
        }
    }
    
    override func collectionView(isEmptyForUnknownReason collectionView: UICollectionView) {
        if let background: ErrorBackgroundView = .fromNib(),
            let text = searchBar.text, !text.isEmpty {
            
            let openQuote = Locale.current.quotationBeginDelimiter ?? "\""
            let closeQuote = Locale.current.quotationEndDelimiter ?? "\""
            
            background.setUpView(title: "No results".localized, description: .localizedStringWithFormat("We didn't turn anything up for %@. Try something else.".localized, "\(openQuote + text + closeQuote)"))
            
            collectionView.backgroundView = background
        }
    }
}
