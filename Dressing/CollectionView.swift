import SwiftData
import SwiftUI

// MARK: - Onglet Collection : tout ce que tu possèdes

struct CollectionView: View {
    @Query(sort: \Garment.createdAt, order: .reverse) private var garments: [Garment]
    var onShowInWardrobe: (UUID) -> Void
    @State private var filter: Category? = Demo.state == "jerseys" ? .jersey : nil
    @State private var search = ""
    @State private var sort = Sort.recent
    @State private var adding = Demo.state == "add"
    @State private var path: [Garment] = []

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Plus récents", name = "Nom", value = "Valeur", season = "Saison"
        var id: String { rawValue }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !garments.isEmpty {
                        Summary(garments: garments)
                            .padding(.horizontal, 20)
                        filterBar
                    }
                    if shown.isEmpty && !garments.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(shown) { g in
                            NavigationLink(value: g) { GarmentTile(garment: g) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 8)
            }
            .overlay {
                if garments.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun habit", systemImage: "tshirt")
                    } description: {
                        Text("Prends tes habits et tes maillots en photo pour construire ta collection.")
                    } actions: {
                        Button("Ajouter un habit") { adding = true }.primaryButton()
                    }
                }
            }
            .navigationTitle("Collection")
            .searchable(text: $search, prompt: "Club, joueur, marque…")
            .navigationDestination(for: Garment.self) { g in
                GarmentDetailView(garment: g, onShowInWardrobe: { onShowInWardrobe(g.id) })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Trier par", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Trier")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ajouter un habit")
                }
            }
            .sheet(isPresented: $adding) { AddGarmentView(initialCategory: filter ?? .jersey) }
            .onAppear {
                if Demo.state == "detail", let g = garments.first(where: { $0.category == .jersey && $0.signed }) { path = [g] }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tout", count: garments.count, selected: filter == nil) { filter = nil }
                ForEach(Category.allCases) { c in
                    let n = garments.filter { $0.category == c }.count
                    if n > 0 { chip(c.label, count: n, selected: filter == c) { filter = c } }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        let label = HStack(spacing: 5) {
            Text(title)
            Text("\(count)").opacity(0.7)
        }
        .font(.subheadline.weight(.medium))
        if selected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
        }
    }

    private var shown: [Garment] {
        let q = search.trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var list = garments.filter { (filter == nil || $0.category == filter) && (q.isEmpty || $0.searchText.contains(q)) }
        switch sort {
        case .recent: break
        case .name: list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .value: list.sort { ($0.value ?? $0.purchasePrice ?? 0) > ($1.value ?? $1.purchasePrice ?? 0) }
        case .season: list.sort { $0.season > $1.season }
        }
        return list
    }
}

/// « 12 pièces · 8 maillots » et la valeur de la collection.
struct Summary: View {
    let garments: [Garment]

    var body: some View {
        let total = garments.reduce(0.0) { $0 + ($1.value ?? $1.purchasePrice ?? 0) }
        let paid = garments.reduce(0.0) { $0 + ($1.purchasePrice ?? 0) }
        let jerseys = garments.filter { $0.category == .jersey }.count
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Valeur de la collection").font(.subheadline).foregroundStyle(.secondary)
                Text(Money.format(total)).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                if paid > 0 && total != paid {
                    let diff = total - paid
                    Text("\(diff >= 0 ? "+" : "−")\(Money.format(abs(diff))) depuis l’achat")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(diff >= 0 ? .green : .red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(garments.count)").font(.title2.weight(.semibold)).monospacedDigit()
                Text(garments.count > 1 ? "pièces" : "pièce").font(.footnote).foregroundStyle(.secondary)
                Text("dont \(jerseys) maillot\(jerseys > 1 ? "s" : "")").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct GarmentTile: View {
    let garment: Garment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if let img = ImageStore.load(garment.imageFile) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
                }
            }
            .aspectRatio(0.82, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if garment.favorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(garment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(garment.subtitle.isEmpty ? garment.category.singular : garment.subtitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fiche d'un habit

struct GarmentDetailView: View {
    @Bindable var garment: Garment
    var onShowInWardrobe: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                let files = PhotoView.allCases.compactMap { garment.file($0) }
                TabView {
                    ForEach(files, id: \.self) { f in
                        if let img = ImageStore.load(f) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(.vertical, 12)
                                .padding(.bottom, files.count > 1 ? 24 : 0)
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: files.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 360)
                VStack(alignment: .leading, spacing: 4) {
                    Text(garment.title).font(.title2.bold())
                    if !garment.subtitle.isEmpty {
                        Text(garment.subtitle).font(.headline).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            if garment.category == .jersey {
                Section("Maillot") {
                    row("Club", garment.club)
                    row("Saison", garment.season)
                    row("Type", garment.kit.label)
                    row("Version", garment.version.short)
                    row("Joueur", garment.player)
                    row("Numéro", garment.number)
                    row("Compétition", garment.competition)
                    if garment.signed { LabeledContent("Signé") { Image(systemName: "signature").foregroundStyle(.tint) } }
                }
            }
            Section("Détails") {
                row("Catégorie", garment.category.singular)
                row("Nom", garment.category == .jersey ? "" : garment.name)
                row("Marque", garment.brand)
                row("Taille", garment.size)
                row("Couleur", garment.color)
                row("État", garment.condition.label)
            }
            Section("Valeur") {
                LabeledContent("Prix payé", value: Money.format(garment.purchasePrice))
                LabeledContent("Valeur actuelle", value: Money.format(garment.value))
                if let p = garment.purchasePrice, let v = garment.value, p > 0 {
                    let d = v - p
                    LabeledContent("Évolution") {
                        Text("\(d >= 0 ? "+" : "−")\(Money.format(abs(d))) (\(Int((d / p * 100).rounded())) %)")
                            .foregroundStyle(d >= 0 ? .green : .red)
                    }
                }
            }
            if !garment.notes.isEmpty {
                Section("Notes") { Text(garment.notes) }
            }
            Section {
                LabeledContent("Ajouté le", value: garment.createdAt.formatted(date: .long, time: .omitted))
            }
        }
        .navigationTitle(garment.category.singular)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { garment.favorite.toggle() } label: {
                    Image(systemName: garment.favorite ? "star.fill" : "star")
                }
                .accessibilityLabel(garment.favorite ? "Retirer des favoris" : "Ajouter aux favoris")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Modifier", systemImage: "pencil") { editing = true }
                    if let onShowInWardrobe {
                        Button("Voir dans la penderie", systemImage: "hanger") { onShowInWardrobe() }
                    }
                    Divider()
                    Button("Supprimer", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Options")
            }
        }
        .sheet(isPresented: $editing) { EditGarmentView(garment: garment) }
        .confirmationDialog("Supprimer \(garment.title) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                garment.allFiles.forEach(ImageStore.delete)
                context.delete(garment)
                try? context.save()
                dismiss()
            }
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty { LabeledContent(label, value: value) }
    }
}

struct EditGarmentView: View {
    let garment: Garment
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GarmentDraft()

    var body: some View {
        NavigationStack {
            GarmentForm(draft: $draft, image: ImageStore.load(garment.imageFile))
                .navigationTitle("Modifier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") { draft.apply(to: garment); dismiss() }
                    }
                }
        }
        .onAppear { draft = GarmentDraft(garment) }
    }
}
