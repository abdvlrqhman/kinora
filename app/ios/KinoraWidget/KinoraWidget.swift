import SwiftUI
import WidgetKit

/// Continue watching on the home screen: up to three titles Kinora wrote
/// (as JSON, through the shared app group). A row opens its title.
struct WatchItem: Decodable, Hashable {
  let title: String
  let sub: String
  let progress: Double
  let open: String
  let poster: String?

  /// kinora://title/series/tt1?homeWidget (the plugin hands it to Kinora).
  var url: URL? { URL(string: "kinora:/\(open)?homeWidget") }
}

struct WatchEntry: TimelineEntry {
  let date: Date
  let items: [WatchItem]
}

struct WatchProvider: TimelineProvider {
  static let group = "group.io.github.abdvlrqhman.kinora"

  static func load() -> [WatchItem] {
    guard let json = UserDefaults(suiteName: group)?.string(forKey: "items"),
          let data = json.data(using: .utf8),
          let items = try? JSONDecoder().decode([WatchItem].self, from: data)
    else { return [] }
    return items
  }

  func placeholder(in context: Context) -> WatchEntry {
    WatchEntry(date: Date(), items: [
      WatchItem(title: "Kinora", sub: "S1 E3, 30m left", progress: 0.4, open: "/", poster: nil),
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
    let items = Self.load()
    completion(items.isEmpty && context.isPreview ? placeholder(in: context) : WatchEntry(date: Date(), items: items))
  }

  // Kinora asks for a reload when what you're watching changes.
  func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
    completion(Timeline(entries: [WatchEntry(date: Date(), items: Self.load())], policy: .never))
  }
}

private let lime = Color(red: 0xBE / 255, green: 0xF2 / 255, blue: 0x64 / 255)
private let haze = Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0x9E / 255)

struct Poster: View {
  let path: String?
  var body: some View {
    Group {
      if let path, let image = UIImage(contentsOfFile: path) {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        Color(white: 0.08)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

struct Progress: View {
  let value: Double
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.2))
        Capsule().fill(lime).frame(width: geo.size.width * max(0, min(1, value)))
      }
    }
    .frame(height: 3)
  }
}

struct Row: View {
  let item: WatchItem
  var body: some View {
    HStack(spacing: 12) {
      Poster(path: item.poster).frame(width: 34, height: 51)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
        Text(item.sub).font(.system(size: 12)).foregroundColor(haze).lineLimit(1)
        if item.progress > 0 { Progress(value: item.progress).padding(.top, 3) }
      }
      Spacer(minLength: 0)
    }
  }
}

struct WatchView: View {
  @Environment(\.widgetFamily) var family
  let entry: WatchEntry

  var body: some View {
    let items = Array(entry.items.prefix(family == .systemLarge ? 3 : 2))
    VStack(alignment: .leading, spacing: 10) {
      Text("Continue watching").font(.system(size: 12, weight: .bold)).foregroundColor(lime)
      if items.isEmpty {
        Text("Nothing to continue yet. What you start watching in Kinora shows up here.")
          .font(.system(size: 13)).foregroundColor(haze)
        Spacer(minLength: 0)
      } else if family == .systemSmall, let first = items.first {
        Poster(path: first.poster).frame(maxWidth: .infinity, maxHeight: .infinity)
        Text(first.title).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
        if first.progress > 0 { Progress(value: first.progress) }
      } else {
        ForEach(items, id: \.self) { item in
          if let url = item.url { Link(destination: url) { Row(item: item) } } else { Row(item: item) }
        }
        Spacer(minLength: 0)
      }
    }
    .widgetURL(family == .systemSmall ? entry.items.first?.url : URL(string: "kinora://home?homeWidget"))
    .modifier(Background())
  }
}

/// True black behind the widget (iOS 17 asks for it this way).
struct Background: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(Color.black, for: .widget)
    } else {
      content.padding().background(Color.black)
    }
  }
}

@main
struct KinoraWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "KinoraWidget", provider: WatchProvider()) { entry in
      WatchView(entry: entry)
    }
    .configurationDisplayName("Continue watching")
    .description("Pick up where you left off.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
