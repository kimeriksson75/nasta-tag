import MapKit
import NastaTagCore
import SwiftUI

/// Destinationerna. Du anger en adress, appen hittar vägen dit med alla trafikslag.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var editing: Place?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.places) { place in
                        Button { editing = place } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.label).font(.headline)
                                    Text(place.detail).foregroundStyle(.secondary)
                                    if place.weekdaysOnly {
                                        Text("Bara vardagar").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { model.places.remove(atOffsets: $0) }
                    Button("Lägg till plats") { adding = true }
                } header: {
                    Text("Platser")
                } footer: {
                    Text("Är du vid en av dem väljer appen nästa av sig själv, så Hem ger Jobbet och tvärtom.")
                }
            }
            .navigationTitle("Inställningar")
            .toolbar { Button("Klar") { dismiss() } }
            .sheet(isPresented: $adding) { PlaceForm(place: nil) }
            .sheet(item: $editing) { PlaceForm(place: $0) }
        }
    }
}

/// Ny plats eller ändra en befintlig: namn, adress och om den bara gäller vardagar.
struct PlaceForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let place: Place?

    @State private var label = ""
    @State private var weekdaysOnly = false
    @State private var address: String?
    @State private var coordinate: Coordinate?
    @State private var search = AddressSearch()
    @State private var problem: String?
    @State private var resolving = false

    private var suggestedLabel: String {
        ["Hem", "Jobbet"].first { name in !model.places.contains { $0.label == name } } ?? ""
    }

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedLabel.isEmpty && coordinate != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Namn") {
                    TextField("Till exempel Hem", text: $label)
                }
                Section {
                    TextField("Gata och nummer", text: $search.query)
                        .textContentType(.fullStreetAddress)
                        .autocorrectionDisabled()
                    if let address, coordinate != nil, search.query == address {
                        Label("Adressen hittades", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if search.query != address {
                        ForEach(search.results, id: \.self) { result in
                            Button { pick(result) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(resolving)
                        }
                    }
                    if let problem { Text(problem).foregroundStyle(.red) }
                } header: {
                    Text("Adress")
                }
                Section {
                    Toggle("Bara vardagar", isOn: $weekdaysOnly)
                }
                if let place {
                    Section {
                        Button("Ta bort plats", role: .destructive) {
                            model.places.removeAll { $0.id == place.id }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(place?.label ?? "Ny plats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Spara") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let place else {
            label = suggestedLabel
            weekdaysOnly = label == "Jobbet"
            return
        }
        label = place.label
        weekdaysOnly = place.weekdaysOnly
        address = place.address
        coordinate = place.coordinate
        search.query = place.address ?? ""
    }

    /// Bara en riktig adress räknas: förslaget slås upp till en punkt som måste ligga i Stockholm.
    private func pick(_ result: MKLocalSearchCompletion) {
        resolving = true
        problem = nil
        Task {
            defer { resolving = false }
            guard let item = try? await MKLocalSearch(request: .init(completion: result)).start().mapItems.first else {
                problem = "Hittade inte adressen. Prova att skriva den på ett annat sätt."
                return
            }
            let point = Coordinate(lat: item.placemark.coordinate.latitude, lon: item.placemark.coordinate.longitude)
            guard isInStockholm(point) else {
                problem = "Adressen ligger utanför Stockholm."
                return
            }
            let subtitle = result.subtitle.replacingOccurrences(of: #",?\s*(Sweden|Sverige)$"#, with: "", options: .regularExpression)
            let text = [result.title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            address = text
            coordinate = point
            search.query = text
        }
    }

    private func save() {
        guard let coordinate else { return }
        if let place, let index = model.places.firstIndex(where: { $0.id == place.id }) {
            model.places[index].label = trimmedLabel
            model.places[index].weekdaysOnly = weekdaysOnly
            model.places[index].address = address
            model.places[index].coordinate = coordinate
            model.places[index].station = nil
        } else {
            model.places.append(Place(label: trimmedLabel, weekdaysOnly: weekdaysOnly,
                                      address: address, coordinate: coordinate))
            if model.activeId == nil { model.activeId = model.places.last?.id }
        }
        model.refreshSoon()
        dismiss()
    }
}

/// Adressförslag medan du skriver, avgränsade till Stockholmstrakten.
@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if query.trimmingCharacters(in: .whitespaces).count < 3 { results = [] } else { completer.queryFragment = query }
        }
    }
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(center: .init(latitude: 59.33, longitude: 18.07),
                                              span: .init(latitudeDelta: 1.2, longitudeDelta: 1.8))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
