#!/usr/bin/env bash
# tests/maccatalyst/make-app.sh — write the Mac Catalyst fixture app for tests/maccatalyst/run.sh.
#
#   bash tests/maccatalyst/make-app.sh <dir>     prints the csproj path it wrote
#
# A MAUI app with one target (net*-maccatalyst) and four Shell tabs, the native twin of the web
# fixture in tests/verify/make-fixtures.py: Home is good, Posts is good and holds a list, Empty has
# a list with no rows, Overlap has two buttons drawn on top of each other and an empty label.
# Controls carry AutomationId, which the Mac sees as the accessibility identifier mac2 finds them
# by. Beside it: docs/mockups/<screen>.html anchoring the same ids with data-testid, and
# tests/.artifacts/verify/list.json naming the four screens. C# only, no XAML: the fewest files
# that build. Nothing here is checked in; the folder lives under tests/.artifacts/.
set -eu
D="${1:?usage: make-app.sh <dir>}"
rm -rf "$D"; mkdir -p "$D/src/TfMacFixture/Platforms/MacCatalyst" "$D/docs/mockups" "$D/tests/.artifacts/verify"
P="$D/src/TfMacFixture"
TFM="net$(dotnet --version | cut -d. -f1,2)-maccatalyst"

cat > "$P/TfMacFixture.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>$TFM</TargetFrameworks>
    <OutputType>Exe</OutputType>
    <UseMaui>true</UseMaui>
    <SingleProject>true</SingleProject>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <ApplicationTitle>TfMacFixture</ApplicationTitle>
    <ApplicationId>com.techieflow.macfixture</ApplicationId>
    <ApplicationDisplayVersion>1.0</ApplicationDisplayVersion>
    <ApplicationVersion>1</ApplicationVersion>
    <SupportedOSPlatformVersion>15.0</SupportedOSPlatformVersion>
    <RuntimeIdentifier>maccatalyst-arm64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Maui.Controls" Version="\$(MauiVersion)" />
  </ItemGroup>
</Project>
XML

cat > "$P/Platforms/MacCatalyst/Program.cs" <<'CS'
using UIKit;
namespace TfMacFixture;
public class Program { static void Main(string[] args) => UIApplication.Main(args, null, typeof(AppDelegate)); }
CS
cat > "$P/Platforms/MacCatalyst/AppDelegate.cs" <<'CS'
using Foundation;
namespace TfMacFixture;
[Register("AppDelegate")]
public class AppDelegate : MauiUIApplicationDelegate { protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp(); }
[Register("SceneDelegate")]
public class SceneDelegate : MauiUISceneDelegate { }
CS
# The scene manifest: on macOS 27 UIKit stops an app that has not adopted the scene life cycle at its
# first window (EXC_BREAKPOINT in _UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption),
# and the stock `dotnet new maui` Info.plist has none.
cat > "$P/Platforms/MacCatalyst/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>UIDeviceFamily</key><array><integer>2</integer></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><true/>
    <key>UISceneConfigurations</key><dict>
      <key>UIWindowSceneSessionRoleApplication</key><array><dict>
        <key>UISceneConfigurationName</key><string>__MAUI_DEFAULT_SCENE_CONFIGURATION__</string>
        <key>UISceneDelegateClassName</key><string>SceneDelegate</string>
      </dict></array>
    </dict>
  </dict>
</dict></plist>
XML

cat > "$P/MauiProgram.cs" <<'CS'
namespace TfMacFixture;
public static class MauiProgram
{
    public static MauiApp CreateMauiApp() => MauiApp.CreateBuilder().UseMauiApp<App>().Build();
}
public class App : Application
{
    protected override Window CreateWindow(IActivationState state) => new Window(new AppShell()) { Width = 1100, Height = 760, Title = "TfMacFixture" };
}
public class AppShell : Shell
{
    public AppShell()
    {
        var bar = new TabBar();
        foreach (var (title, page) in new (string, Func<Page>)[] { ("Home", Home), ("Posts", Posts), ("Empty", Empty), ("Overlap", Overlap) })
            bar.Items.Add(new ShellContent { Title = title, Route = title.ToLowerInvariant(), ContentTemplate = new DataTemplate(page) });
        Items.Add(bar);
    }
    static Label L(string id, string text) => new Label { AutomationId = id, Text = text, FontSize = 18 };
    static Page Home() => new ContentPage { Title = "Home", Content = new VerticalStackLayout { Padding = 30, Spacing = 14, Children = {
        L("greeting", "Hello from the fixture"), L("total", "3 posts"), new Button { AutomationId = "refresh", Text = "Refresh" } } } };
    static Page Posts() => new ContentPage { Title = "Posts", Content = new VerticalStackLayout { Padding = 30, Spacing = 14, Children = {
        L("posts-title", "Posts"),
        new CollectionView { AutomationId = "post-list", HeightRequest = 300, ItemsSource = new[] { "First post", "Second post", "Third post" },
            ItemTemplate = new DataTemplate(() => { var l = new Label { FontSize = 16, Padding = 6 }; l.SetBinding(Label.TextProperty, "."); return l; }) } } } };
    static Page Empty() => new ContentPage { Title = "Empty", Content = new VerticalStackLayout { Padding = 30, Spacing = 14, Children = {
        L("empty-title", "Nothing here"),
        new CollectionView { AutomationId = "empty-list", HeightRequest = 300, ItemsSource = Array.Empty<string>(),
            ItemTemplate = new DataTemplate(() => new Label()) } } } };
    static Page Overlap()
    {
        var g = new Grid { Padding = 30, RowDefinitions = { new RowDefinition(60), new RowDefinition(60) } };
        g.Add(new Button { AutomationId = "save", Text = "Save", WidthRequest = 220, HorizontalOptions = LayoutOptions.Start }, 0, 0);
        g.Add(new Button { AutomationId = "cancel", Text = "Cancel", WidthRequest = 220, HorizontalOptions = LayoutOptions.Start, TranslationX = 60 }, 0, 0);
        g.Add(new Label { AutomationId = "status", Text = "" , FontSize = 18 }, 0, 1);
        return new ContentPage { Title = "Overlap", Content = g };
    }
}
CS

mock() { # name ids...
  local n="$1"; shift
  { echo "<!doctype html><html><body><h1>$n</h1>"; for id in "$@"; do echo "<div data-testid=\"$id\">$id</div>"; done; echo "</body></html>"; } > "$D/docs/mockups/$n.html"
}
mock home greeting total refresh
mock posts posts-title post-list
mock empty empty-title empty-list
mock overlap save cancel status

python3 - "$D/tests/.artifacts/verify/list.json" <<'PY'
import json, sys
names = ["Home", "Posts", "Empty", "Overlap"]
s = lambda i, n: {"name": n, "route": f"//{n.lower()}", "mockup": f"docs/mockups/{n.lower()}.html", "rows": [f"REQ-UI-00{i}"]}
r = lambda i, n: {"id": f"REQ-UI-00{i}", "title": f"{n} screen", "class": "UI", "screen": n, "route": f"//{n.lower()}",
                  "status_raw": "Implemented", "perf_budget": "", "remarks": ""}
json.dump({"scope": "ui", "screens": [s(i, n) for i, n in enumerate(names, 1)], "rows": [r(i, n) for i, n in enumerate(names, 1)]},
          open(sys.argv[1], "w"), indent=1)
PY
echo "src/TfMacFixture/TfMacFixture.csproj"
