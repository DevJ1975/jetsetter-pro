// File: Features/TripJournal/TripJournalView.swift
//
// Auto-generates a scrapbook from photos taken during a trip's date range.
// Stats header + chronological grid + a shareable summary card the user can
// post to social or send to friends.

import SwiftUI
import Photos

struct TripJournalView: View {

    let trip: Trip

    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var authState: AuthState = .checking
    @State private var isLoading = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    enum AuthState { case checking, granted, denied }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                if authState == .denied {
                    deniedCard
                } else if isLoading {
                    loadingCard
                } else if assets.isEmpty && MockDataService.isEnabled {
                    // Demo fallback: synthetic stats + placeholder gradient grid
                    demoStatsCard
                    demoPhotoGrid
                    shareButton
                } else if assets.isEmpty {
                    emptyCard
                } else {
                    statsCard
                    photoGrid
                    shareButton
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Trip Journal")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await refresh()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [JetsetterTheme.Colors.accent, Color(hex: "#7B3FBF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(trip.destination)  ·  \(trip.startDate, format: .dateTime.month().day()) – \(trip.endDate, format: .dateTime.month().day().year())")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 16) {
            statColumn(value: "\(assets.count)", label: "PHOTOS", icon: "photo.fill")
            Divider().frame(height: 40)
            statColumn(value: "\(trip.durationInDays)", label: "DAYS", icon: "calendar")
            Divider().frame(height: 40)
            statColumn(value: "\(daysWithPhotos)", label: "ACTIVE DAYS", icon: "sun.max.fill")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private func statColumn(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.3)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.grid.3x2.fill")
                    .font(.caption.bold())
                Text("MOMENTS")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 4),
                          GridItem(.flexible(), spacing: 4),
                          GridItem(.flexible(), spacing: 4)],
                spacing: 4
            ) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    GridCell(asset: asset, thumbnails: $thumbnails)
                }
            }
        }
    }

    // MARK: - Demo fallback (simulator)

    private var demoStatsCard: some View {
        HStack(spacing: 16) {
            statColumn(value: "24", label: "PHOTOS", icon: "photo.fill")
            Divider().frame(height: 40)
            statColumn(value: "\(trip.durationInDays)", label: "DAYS", icon: "calendar")
            Divider().frame(height: 40)
            statColumn(value: "6", label: "ACTIVE DAYS", icon: "sun.max.fill")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var demoPhotoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.grid.3x2.fill")
                    .font(.caption.bold())
                Text("MOMENTS")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 4),
                          GridItem(.flexible(), spacing: 4),
                          GridItem(.flexible(), spacing: 4)],
                spacing: 4
            ) {
                ForEach(0..<9, id: \.self) { index in
                    demoTile(index: index)
                }
            }
        }
    }

    private func demoTile(index: Int) -> some View {
        // Tasteful gradient swatches + travel iconography until real photos load.
        let palettes: [[Color]] = [
            [Color(hex: "#FF6B6B"), Color(hex: "#FFD93D")],     // sunrise
            [Color(hex: "#1E3C72"), Color(hex: "#2A5298")],     // ocean
            [Color(hex: "#11998E"), Color(hex: "#38EF7D")],     // tea green
            [Color(hex: "#FC466B"), Color(hex: "#3F5EFB")],     // neon
            [Color(hex: "#FDBB2D"), Color(hex: "#22C1C3")],     // pastel
            [Color(hex: "#E55D87"), Color(hex: "#5FC3E4")],     // candy
            [Color(hex: "#414345"), Color(hex: "#232526")],     // night
            [Color(hex: "#FFAFBD"), Color(hex: "#FFC3A0")],     // peach
            [Color(hex: "#C33764"), Color(hex: "#1D2671")]      // dusk
        ]
        let icons = ["building.2.fill", "fork.knife", "leaf.fill",
                     "sparkles", "moon.stars.fill", "camera.fill",
                     "tram.fill", "cup.and.saucer.fill", "mountain.2.fill"]
        let colors = palettes[index % palettes.count]
        let icon = icons[index % icons.count]
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            Task { await prepareShare() }
        } label: {
            Label("Share Trip Journal", systemImage: "square.and.arrow.up")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(JetsetterTheme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    // MARK: - States

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No photos from this trip yet")
                .font(.headline)
            Text("Photos you take between \(trip.startDate.formatted(.dateTime.month().day())) and \(trip.endDate.formatted(.dateTime.month().day())) will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var deniedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Photo access needed")
                .font(.headline)
            Text("Grant Photos access in Settings so JetSetter can build your trip journal automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Scanning your photos…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    // MARK: - Logic

    private var daysWithPhotos: Int {
        let calendar = Calendar.current
        let days = Set(assets.compactMap { $0.creationDate.map { calendar.startOfDay(for: $0) } })
        return days.count
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let granted = await PhotoLibraryService.shared.requestAuthorization()
        authState = granted ? .granted : .denied
        guard granted else {
            // In demo mode, show placeholder gradients so the screen isn't empty
            // when running on a simulator without bundled photos.
            if MockDataService.isEnabled {
                authState = .granted   // treat as authorized for the demo flow
            }
            return
        }
        assets = PhotoLibraryService.shared.assets(
            from: trip.startDate,
            to: trip.endDate.addingTimeInterval(86400)
        )
    }

    private func prepareShare() async {
        // Render the journal hero + stats + top photos into a single image using ImageRenderer
        let renderer = await ImageRenderer(
            content: ShareCard(trip: trip, photoCount: assets.count, days: trip.durationInDays, topImages: await topShareImages())
        )
        await MainActor.run {
            renderer.scale = 3.0
            shareImage = renderer.uiImage
            showShareSheet = true
        }
    }

    private func topShareImages() async -> [UIImage] {
        let picks = stride(from: 0, to: min(assets.count, 6), by: 1).map { assets[$0] }
        var images: [UIImage] = []
        for asset in picks {
            if let img = await PhotoLibraryService.shared.thumbnail(for: asset, targetSize: .init(width: 600, height: 600)) {
                images.append(img)
            }
        }
        return images
    }
}

// MARK: - Grid cell

private struct GridCell: View {

    let asset: PHAsset
    @Binding var thumbnails: [String: UIImage]

    var body: some View {
        ZStack {
            if let image = thumbnails[asset.localIdentifier] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemFill))
                    .overlay { ProgressView().scaleEffect(0.7) }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        guard thumbnails[asset.localIdentifier] == nil else { return }
        let image = await PhotoLibraryService.shared.thumbnail(
            for: asset,
            targetSize: CGSize(width: 240, height: 240)
        )
        await MainActor.run {
            if let image { thumbnails[asset.localIdentifier] = image }
        }
    }
}

// MARK: - Share card (rendered to image)

private struct ShareCard: View {
    let trip: Trip
    let photoCount: Int
    let days: Int
    let topImages: [UIImage]

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [JetsetterTheme.Colors.accent, Color(hex: "#7B3FBF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 600, height: 200)

                VStack(alignment: .leading, spacing: 6) {
                    Text(trip.destination.uppercased())
                        .font(.system(size: 12, weight: .black))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(trip.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(trip.startDate, format: .dateTime.month().day()) – \(trip.endDate, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(24)
            }

            // Stats row
            HStack(spacing: 0) {
                statBlock(value: "\(photoCount)", label: "PHOTOS")
                Divider().background(.white.opacity(0.2))
                statBlock(value: "\(days)", label: "DAYS")
                Divider().background(.white.opacity(0.2))
                statBlock(value: "\(trip.items.count)", label: "MOMENTS")
            }
            .frame(width: 600, height: 70)
            .background(Color.black)

            // Top photos grid
            if !topImages.isEmpty {
                let columns = 3
                let rows = (topImages.count + columns - 1) / columns
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { col in
                            let index = row * columns + col
                            if index < topImages.count {
                                Image(uiImage: topImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 199, height: 199)
                                    .clipped()
                            } else {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: 199, height: 199)
                            }
                        }
                    }
                }
            }

            // Footer
            HStack {
                Image(systemName: "airplane")
                    .foregroundStyle(.white)
                Text("Made with JetSetter Pro")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 600, height: 50)
            .background(JetsetterTheme.Colors.accent)
        }
        .frame(width: 600)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Router (picks active trip)

struct TripJournalRouterView: View {
    var body: some View {
        if let trip = nextOrLatestTrip() {
            TripJournalView(trip: trip)
        } else {
            ContentUnavailableView(
                "No trip to journal",
                systemImage: "book.closed",
                description: Text("Create a trip in the Itinerary tab to get an auto-generated photo journal.")
            )
        }
    }

    private func nextOrLatestTrip() -> Trip? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let trips = try? decoder.decode([Trip].self, from: data) else { return nil }
        // Prefer the most recently completed trip (the one a user wants to remember)
        let completed = trips.filter { $0.endDate < Date() }.sorted { $0.endDate > $1.endDate }
        if let last = completed.first { return last }
        return trips.sorted { $0.startDate < $1.startDate }.first
    }
}
