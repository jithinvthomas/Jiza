# Trading development connection

The Trading screen links to `https://trade.jiza.app`, the protected Cloudflare hostname for the existing Jiza Trading server on this PC. Source repository: `https://github.com/jithinvthomas/Jiza-Trading`. Existing running checkout: `C:\Users\jithi\trading-platform`.

It opens in a separate tab so Trading keeps its own authentication origin and frame protection. The preview does not receive passwords, sessions, exchange keys or trading data. It neither starts trades nor changes server settings.

For iPhone, configure a reachable authenticated HTTPS Trading address in the native app's Trading server field. Localhost is only for the PC preview. Follow the Trading repository's `docs/SECURITY.md` for its Tunnel/Access deployment setup; no public endpoint was created for this preview connection.
