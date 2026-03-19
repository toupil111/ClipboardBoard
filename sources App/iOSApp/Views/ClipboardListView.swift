import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel

    var body: some View {
        List {
            Section {
                if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("同步失败", systemImage: "icloud.slash", description: Text(errorMessage))
                }

                ForEach(viewModel.filteredItems) { item in
                    NavigationLink(value: item) {
                        ClipboardRowView(item: item) {
                            viewModel.copy(item)
                        } shareAction: {
                            viewModel.prepareShare(for: item)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("最近 50 条")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "搜索文本或文件")
        .navigationTitle("粘贴板")
        .navigationDestination(for: ClipboardEntry.self) { item in
            ClipboardDetailView(item: item) {
                viewModel.copy(item)
            } shareAction: {
                viewModel.prepareShare(for: item)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.refresh()
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.shareErrorMessage != nil },
            set: { if !$0 { viewModel.shareErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.shareErrorMessage ?? "")
        }
        .sheet(item: $viewModel.selectedShareURL) { url in
            ShareSheet(activityItems: [url])
        }
    }
}
