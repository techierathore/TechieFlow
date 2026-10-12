// three windows, each with its own web view, attached in turn; Cmd+= must reach all three
var lstViews = new[] { new WebKit.WKWebView(), new WebKit.WKWebView(), new WebKit.WKWebView() };
foreach (var objView in lstViews) YourApp.BlazorZoom.Attach(objView);
YourApp.BlazorZoom.ZoomBy(1);
Console.WriteLine(string.Join(" ", lstViews.Select(v => ((double)v.PageZoom).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture))));
