// ch_010 (Chatur TF-010): the real blazor-zoom.cs.txt compiled against stand-ins for the Mac types
#pragma warning disable CS8981
global using nfloat = System.Runtime.InteropServices.NFloat;
namespace Foundation { public class NSObject { } public class NSString { } }
namespace ObjCRuntime { public class Selector { public Selector(string a) { } } }
namespace WebKit { public class WKWebView { public nfloat PageZoom { get; set; } = 1; } }
namespace UIKit
{
    using Foundation;
    public enum UIMenuSystemElementGroupPreference { Removed }
    public enum UIMenuIdentifier { Format, View, None }
    public enum UIMenuOptions { DisplayInline }
    public enum UIKeyModifierFlags { Command }
    public static class UIMenuIdentifierExt { public static NSString? GetConstant(this UIMenuIdentifier a) => new(); }
    public class UIMainMenuSystemConfiguration { public UIMenuSystemElementGroupPreference TextFormattingPreference { get; set; } public UIMenuSystemElementGroupPreference InspectorPreference { get; set; } }
    public class UIMainMenuSystem { public static UIMainMenuSystem SharedSystem { get; } = new(); public void SetBuildConfiguration(UIMainMenuSystemConfiguration a, Action<IUIMenuBuilder> b) { } }
    public class UIMenuSystem { public static UIMenuSystem MainSystem { get; } = new(); public IntPtr Handle => IntPtr.Zero; }
    public interface IUIMenuBuilder { UIMenuSystem? System { get; } void RemoveMenu(NSString a); UIMenu? GetMenu(NSString a); void ReplaceMenu(NSString a, UIMenu b); }
    public class UIMenuElement { public string Title { get; set; } = ""; }
    public class UIMenu : UIMenuElement { public UIMenuElement[] Children { get; set; } = Array.Empty<UIMenuElement>(); public static UIMenu Create(string a, object? b, UIMenuIdentifier c, UIMenuOptions d, UIMenuElement[] e) => new(); public UIMenu GetMenuByReplacingChildren(UIMenuElement[] a) => this; }
    public class UIKeyCommand : UIMenuElement { public static UIKeyCommand Create(string a, object? b, ObjCRuntime.Selector c, string d, UIKeyModifierFlags e, object? f) => new(); }
}
public class Preferences { public static Preferences Default { get; } = new(); readonly Dictionary<string, object> d = new(); public T Get<T>(string k, T v) => d.TryGetValue(k, out var o) ? (T)o : v; public void Set<T>(string k, T v) => d[k] = v!; }
