#!/usr/bin/env bash
# tests/maccatalyst/make-hybrid.sh — write the Blazor Hybrid Mac fixture for tests/maccatalyst/run.sh.
#
#   bash tests/maccatalyst/make-hybrid.sh <dir>     prints the csproj path it wrote
#
# A MAUI Blazor Hybrid app with one target (net*-maccatalyst): its screens are Razor pages in a web
# view, reached from a menu of links. Home is good; Crowded has two buttons drawn on top of each
# other; Broken throws while it renders, so the stock error bar shows. Its mockups anchor controls
# with data-testid, which a Mac never shows to mac2: the check runs without names (owner decision A,
# 2026-10-07). Beside it: docs/mockups/ and tests/.artifacts/verify/list.json. Never checked in.
set -eu
D="${1:?usage: make-hybrid.sh <dir>}"
rm -rf "$D"; mkdir -p "$D/src/TfMacHybrid/Platforms/MacCatalyst" "$D/src/TfMacHybrid/Components/Pages" "$D/src/TfMacHybrid/wwwroot" \
  "$D/docs/mockups" "$D/tests/.artifacts/verify"
P="$D/src/TfMacHybrid"
TFM="net$(dotnet --version | cut -d. -f1,2)-maccatalyst"

cat > "$P/TfMacHybrid.csproj" <<XML
<Project Sdk="Microsoft.NET.Sdk.Razor">
  <PropertyGroup>
    <TargetFrameworks>$TFM</TargetFrameworks>
    <OutputType>Exe</OutputType>
    <UseMaui>true</UseMaui>
    <SingleProject>true</SingleProject>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <EnableDefaultCssItems>false</EnableDefaultCssItems>
    <ApplicationTitle>TfMacHybrid</ApplicationTitle>
    <ApplicationId>com.techieflow.machybrid</ApplicationId>
    <ApplicationDisplayVersion>1.0</ApplicationDisplayVersion>
    <ApplicationVersion>1</ApplicationVersion>
    <SupportedOSPlatformVersion>15.0</SupportedOSPlatformVersion>
    <RuntimeIdentifier>maccatalyst-arm64</RuntimeIdentifier>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Maui.Controls" Version="\$(MauiVersion)" />
    <PackageReference Include="Microsoft.AspNetCore.Components.WebView.Maui" Version="\$(MauiVersion)" />
  </ItemGroup>
</Project>
XML

cat > "$P/Platforms/MacCatalyst/Program.cs" <<'CS'
using UIKit;
namespace TfMacHybrid;
public class Program { static void Main(string[] args) => UIApplication.Main(args, null, typeof(AppDelegate)); }
CS
cat > "$P/Platforms/MacCatalyst/AppDelegate.cs" <<'CS'
using Foundation;
namespace TfMacHybrid;
[Register("AppDelegate")]
public class AppDelegate : MauiUIApplicationDelegate { protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp(); }
[Register("SceneDelegate")]
public class SceneDelegate : MauiUISceneDelegate { }
CS
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
using Microsoft.AspNetCore.Components.WebView.Maui;
namespace TfMacHybrid;
public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var b = MauiApp.CreateBuilder().UseMauiApp<App>();
        b.Services.AddMauiBlazorWebView();
        return b.Build();
    }
}
public class App : Application
{
    protected override Window CreateWindow(IActivationState state) => new Window(new ContentPage { Content = new BlazorWebView {
        HostPage = "wwwroot/index.html",
        RootComponents = { new RootComponent { Selector = "#app", ComponentType = typeof(Components.Routes) } } } })
        { Width = 1000, Height = 700, Title = "TfMacHybrid" };
}
CS
cat > "$P/wwwroot/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8" /><title>TfMacHybrid</title><base href="/" />
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; }
  nav { display: flex; gap: 16px; padding: 12px 20px; background: #eef; }
  main { padding: 20px; }
  #blazor-error-ui { display: none; position: fixed; bottom: 0; left: 0; right: 0; padding: 10px 20px; background: lightyellow; }
</style></head>
<body>
  <div id="app">Loading...</div>
  <div id="blazor-error-ui">An unhandled error has occurred. <a href="" class="reload">Reload</a></div>
  <script src="_framework/blazor.webview.js" autostart="false"></script>
</body></html>
HTML
cat > "$P/Components/_Imports.razor" <<'R'
@using Microsoft.AspNetCore.Components.Routing
@using Microsoft.AspNetCore.Components.Web
@using TfMacHybrid.Components
R
cat > "$P/Components/Routes.razor" <<'R'
<Router AppAssembly="typeof(MauiProgram).Assembly">
  <Found Context="routeData"><RouteView RouteData="routeData" DefaultLayout="typeof(MainLayout)" /></Found>
</Router>
R
cat > "$P/Components/MainLayout.razor" <<'R'
@inherits LayoutComponentBase
<nav><a href="">Home</a><a href="crowded">Crowded</a><a href="broken">Broken</a></nav>
<main>@Body</main>
R
cat > "$P/Components/Pages/Home.razor" <<'R'
@page "/"
<h1 data-testid="home-title">Home</h1>
<p data-testid="home-total">3 posts</p>
<button data-testid="home-refresh">Refresh</button>
R
cat > "$P/Components/Pages/Crowded.razor" <<'R'
@page "/crowded"
<h1>Crowded</h1>
<div style="position: relative; height: 60px">
  <button data-testid="save" style="position: absolute; left: 0; top: 0; width: 200px; height: 40px">Save</button>
  <button data-testid="cancel" style="position: absolute; left: 60px; top: 0; width: 200px; height: 40px">Cancel</button>
</div>
R
cat > "$P/Components/Pages/Broken.razor" <<'R'
@page "/broken"
<h1>Broken</h1>
@code { protected override void OnInitialized() => throw new InvalidOperationException("the fixture's broken screen"); }
R

mock() { local n="$1"; shift
  { echo "<!doctype html><html><body>"; for id in "$@"; do echo "<div data-testid=\"$id\">$id</div>"; done; echo "</body></html>"; } > "$D/docs/mockups/$n.html"; }
mock home home-title home-total home-refresh
mock crowded save cancel
mock broken broken-title
python3 - "$D/tests/.artifacts/verify/list.json" <<'PY'
import json, sys
names = ["Home", "Crowded", "Broken"]
s = lambda i, n: {"name": n, "route": "/" if n == "Home" else f"/{n.lower()}", "mockup": f"docs/mockups/{n.lower()}.html", "rows": [f"REQ-UI-10{i}"]}
r = lambda i, n: {"id": f"REQ-UI-10{i}", "title": f"{n} screen", "class": "UI", "screen": n, "route": "/" if n == "Home" else f"/{n.lower()}",
                  "status_raw": "Implemented", "perf_budget": "", "remarks": ""}
json.dump({"scope": "ui", "screens": [s(i, n) for i, n in enumerate(names, 1)], "rows": [r(i, n) for i, n in enumerate(names, 1)]},
          open(sys.argv[1], "w"), indent=1)
PY
echo "src/TfMacHybrid/TfMacHybrid.csproj"
