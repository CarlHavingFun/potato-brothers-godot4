# Third-party development tools

These tools are committed for reproducible development and excluded from game
exports.

| Tool | Version | Source revision | License |
| --- | --- | --- | --- |
| GdUnit4 | 6.2.0 | `d18770221c2df4a3c991a42fdce7907df40eea75` | MIT |
| Godot MCP/CLI addon | 0.8.2 | `5bd9d454a091c0418eb019cfef93bcc48e061708` | MIT |

The complete Godot MCP 0.8.2 Windows AMD64 release package supplied by the
project owner is committed at `tools/vendor/godot-mcp/0.8.2/`. Its checked-in
SHA-256 manifest verifies the archive. A generated working copy at
`bin/godot-mcp.exe` remains ignored. Both the CLI and the editor addon's
loopback-only streamable HTTP endpoint are valid local development transports.

## Runtime fonts

| Font | Version / identity | Official upstream source | License |
| --- | --- | --- | --- |
| Anybody Medium | `Anybody Medium`, Version 1.114, SHA-256 `2E55DEB23DE0524FACB40FAFAAA63ADC18A5C6FCE8105D5BBBD61C3BA221AA0B`; Copyright 2020 The Anybody Project Authors | https://github.com/Etcetera-Type-Co/Anybody/blob/master/fonts/ttf/Anybody-Medium.ttf | SIL OFL 1.1; full text: `assets/font/licenses/Anybody-OFL.txt` |
| Noto Sans CJK SC Medium | `Noto Sans CJK SC Medium`, Version 2.004, SHA-256 `CA094F6B0001FB048CA39DDD797A0CDB0179E1E55C6561E111C49C3E6A61D7B7`; © 2014-2021 Adobe (http://www.adobe.com/). | https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Medium.otf | SIL OFL 1.1; full text: `assets/font/licenses/NotoSansCJK-OFL.txt` |

The shipped `assets/font/brotato_font_stack.tres` uses Anybody Medium for
Latin/digits and Noto Sans CJK SC Medium as its Simplified Chinese fallback.
