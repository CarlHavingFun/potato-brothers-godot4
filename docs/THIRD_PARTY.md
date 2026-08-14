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
