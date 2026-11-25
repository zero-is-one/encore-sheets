import SwiftUI
import WidgetKit

private struct PracticeEntry: TimelineEntry {
    let date: Date
    let reached: Int
    let total: Int
}

private struct PracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PracticeEntry {
        PracticeEntry(date: Date(), reached: 1, total: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (PracticeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PracticeEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> PracticeEntry {
        let defaults = UserDefaults(suiteName: "group.app.encoresheets.encoresheets")
        return PracticeEntry(date: Date(), reached: defaults?.integer(forKey: "widgetReached") ?? 0,
                             total: defaults?.integer(forKey: "widgetTotal") ?? 0)
    }
}

private struct PracticeWidgetView: View {
    let entry: PracticeEntry
    @Environment(\.widgetFamily) private var family

    private var practice: URL { URL(string: "encoresheets://practice")! }
    private var library: URL { URL(string: "encoresheets://library")! }

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.background, for: .widget)
        } else {
            content.padding()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Practice", systemImage: "music.note").font(.headline)
            if entry.total > 0 {
                Text("\(entry.reached) of \(entry.total) goals reached")
                    .font(.subheadline)
                ProgressView(value: Double(entry.reached), total: Double(entry.total))
            } else {
                Text("No practice goals").font(.subheadline)
            }
            if family == .systemMedium {
                HStack {
                    Link("Library", destination: library)
                    Spacer()
                    Link("Practice", destination: practice)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(practice)
    }
}

@main
struct EncorePracticeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EncorePracticeWidget", provider: PracticeProvider()) { entry in
            PracticeWidgetView(entry: entry)
        }
        .configurationDisplayName("EncoreSheets Practice")
        .description("Check your practice goals and open your score library.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
