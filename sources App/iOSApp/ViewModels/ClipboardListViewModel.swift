import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class ClipboardListViewModel: ObservableObject {
    @Published var items: [ClipboardEntry] = ClipboardEntry.mockItems
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var shareErrorMessage: String?
    @Published var selectedShareURL: URL?
    @Published var selectedEntry: ClipboardEntry?
    @Published var searchText = ""

    private let syncService: ClipboardSyncServing
    private let cacheStore: ClipboardCacheStore
    private let sharedInboxStore: SharedClipboardInboxStore

    init(
        syncService: ClipboardSyncServing = CloudKitClipboardSyncService(),
        cacheStore: ClipboardCacheStore = .shared,
        sharedInboxStore: SharedClipboardInboxStore = .shared
    ) {
        self.syncService = syncService
        self.cacheStore = cacheStore
        self.sharedInboxStore = sharedInboxStore
    }

    var filteredItems: [ClipboardEntry] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.previewText.localizedCaseInsensitiveContains(searchText)
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteItems = try await syncService.fetchLatest(limit: 50)
            let sharedItems = await sharedInboxStore.loadEntries()
            items = merge(sharedItems: sharedItems, remoteItems: remoteItems)
            try await cacheStore.saveWidgetItems(items)
            WidgetCenter.shared.reloadAllTimelines()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copy(_ entry: ClipboardEntry) {
        UIPasteboard.general.string = entry.copyText ?? entry.previewText
    }

    func prepareShare(for entry: ClipboardEntry) {
        selectedEntry = entry
        guard entry.type.isFileLike else {
            selectedShareURL = nil
            shareErrorMessage = "当前条目不是文件内容。"
            return
        }

        guard let fileURL = ClipboardFileLocator.localFileURL(for: entry) else {
            selectedShareURL = nil
            shareErrorMessage = "该文件还未同步到本机，请下拉刷新后再试。"
            return
        }

        shareErrorMessage = nil
        selectedShareURL = fileURL
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "clipboardboard" else { return }
        if url.host == "copy",
           let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
           let id = UUID(uuidString: idString),
           let item = items.first(where: { $0.id == id }) {
            copy(item)
            return
        }

        if url.host == "open",
           let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
           let id = UUID(uuidString: idString),
           let item = items.first(where: { $0.id == id }) {
            selectedEntry = item
            prepareShare(for: item)
        }
    }

    private func merge(sharedItems: [ClipboardEntry], remoteItems: [ClipboardEntry]) -> [ClipboardEntry] {
        var map = [UUID: ClipboardEntry]()

        for item in remoteItems + sharedItems {
            map[item.id] = item
        }

        return Array(map.values)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(50)
            .map { $0 }
    }
}
