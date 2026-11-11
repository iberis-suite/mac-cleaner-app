# Security Policy

## Supported versions

Only the latest release of Mac Cleaner receives security fixes.

| Version | Supported |
| ------- | --------- |
| 0.2.x   | Yes       |
| < 0.2   | No        |

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report it privately through GitHub: open the **Security** tab of this repository and click **Report a vulnerability**
(https://github.com/iberis-suite/mac-cleaner-app/security/advisories/new).

Include the macOS version, the app version, the steps to reproduce and the impact you observed.
You will get a first answer within 7 days. Once a fix is released, the advisory is published with credit to the reporter, unless you prefer to stay anonymous.

## Scope

Mac Cleaner runs locally and sends no data over the network, with one exception: the speed test. Only when you click **Test speed** does it run `networkQuality`, the tool built into macOS, which measures throughput against Apple's servers; nothing else is sent, and no third-party service is used. Showing the Wi-Fi name requires macOS location access, asked once and used for nothing else. It deletes files only after a preview and an explicit confirmation, and asks for an administrator password through the macOS dialog only for system maintenance tasks. Issues that bypass the preview, delete files outside the listed items, or escalate privileges are in scope.
