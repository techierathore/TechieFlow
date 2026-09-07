# tf-cdp-relay.ps1 — relay a Windows loopback port to every interface (Sitting 4c, 2026-09-06).
#
#   powershell.exe -File tf-cdp-relay.ps1 -ListenPort 9223 -TargetPort 9222
#
# A MAUI Blazor Hybrid app's WebView2 opens its DevTools port on 127.0.0.1 only, so WSL cannot
# reach it. This relay listens on every interface and forwards to the loopback port, so Playwright
# in WSL can attach with connectOverCDP('http://<windows host ip>:9223'). Started and stopped by
# tf-verify-boot.sh; proven on MyDiary's Windows head, 2026-09-06 (the DevGuide run).
param(
  [int]$ListenPort = 9223,
  [string]$TargetHost = '127.0.0.1',
  [int]$TargetPort = 9222
)

Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;

public static class TcpRelay {
    public static void Start(int listenPort, string targetHost, int targetPort) {
        var listener = new TcpListener(IPAddress.Any, listenPort);
        listener.Start();
        while (true) {
            var client = listener.AcceptTcpClient();
            var t = new Thread(() => Handle(client, targetHost, targetPort));
            t.IsBackground = true;
            t.Start();
        }
    }

    private static void Handle(TcpClient client, string targetHost, int targetPort) {
        try {
            using (client)
            using (var target = new TcpClient(targetHost, targetPort)) {
                using (var cs = client.GetStream())
                using (var ts = target.GetStream()) {
                    var t1 = new Thread(() => Pump(cs, ts));
                    t1.IsBackground = true;
                    t1.Start();
                    Pump(ts, cs);
                    t1.Join();
                }
            }
        } catch {}
    }

    private static void Pump(System.IO.Stream src, System.IO.Stream dst) {
        var buf = new byte[65536];
        try {
            int n;
            while ((n = src.Read(buf, 0, buf.Length)) > 0) {
                dst.Write(buf, 0, n);
                dst.Flush();
            }
        } catch {}
        try { dst.Close(); } catch {}
    }
}
"@

Write-Host "relay listening on 0.0.0.0:$ListenPort -> $TargetHost`:$TargetPort"
[TcpRelay]::Start($ListenPort, $TargetHost, $TargetPort)
