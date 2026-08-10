# Swift CLIKit

The shared foundation for the ArrayPress family of metadata CLIs. Every tool — `yt-meta`, `tmdb-meta`, `discogs-meta` — gets the same credential store, the same output rules, the same exit codes and the same cache from this one package.

Built for tools whose main caller is an **agent or a script**, not a person. That constraint drives most of the design: output defaults to JSON when piped, errors are machine-readable and carry a repair hint, exit codes are a stable contract, and payloads are curated rather than dumped.

## Features

- 🔑 **Shared credential store** — one `0600` JSON file for every tool, namespaced by service, with environment overrides
- 🧾 **Machine-readable errors** — JSON envelope on stderr with `code`, `service`, `message` and an actionable `hint`
- 🔢 **Stable exit codes** — callers branch on `$?` instead of parsing prose
- 🖨️ **Dual-audience output** — JSON when piped, readable text on a terminal; no flag required either way
- ✂️ **Field selection** — `--fields` narrows any payload, keeping responses cheap
- 💾 **TTL disk cache** — repeat lookups served locally, off the failure path entirely
- 🍎 **Swift 6** · Apple silicon · macOS 14+ · strict concurrency

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-cli-kit.git", from: "0.1.0")
```

```swift
.product(name: "CLIKit", package: "swift-cli-kit")
```

## Exit Codes

These are a public contract. Append new ones; never renumber.

| Code | Meaning | Caller should |
|------|---------|---------------|
| `0` | Success | — |
| `1` | Not found | Give up on this input |
| `2` | Usage error | Fix the arguments |
| `3` | Auth required | Run the `hint` command |
| `4` | Rate limited | Back off and retry |
| `5` | Upstream/network failure | Retry later |
| `6` | Parse failure | Upgrade the tool — the site changed |

The `1` / `6` split is the one that matters most. "This video has no transcript" and "our extractor broke" both look like a missing result, but the first means stop and the second means file a bug.

```sh
yt-meta transcript "$URL" || case $? in
  1) echo "no transcript exists" ;;
  4) sleep 60 ;;
  6) brew upgrade yt-meta ;;
esac
```

Argument mistakes exit `2` whichever layer catches them. ArgumentParser's own
default is `64` (BSD `sysexits.h`), so for a while a tool answered the same
class of mistake two different ways depending on whether our validation or the
parser noticed first — ``CLIRunner`` is the entry point that normalises it. Use
it instead of `@main` on the root command:

```swift
@main
enum Main {
    static func main() async { await CLIRunner.run(TMDBMeta.self) }
}
```

## Building a Tool

Declare the service, adopt `CLICommand`, and the rest is wired for you.

```swift
import ArgumentParser
import CLIKit

@main
struct TMDBMeta: AsyncParsableCommand, ServiceProviding {

    static let service = ServiceSpec(
        id: "tmdb",
        displayName: "TMDB",
        toolName: "tmdb-meta",
        credentials: [
            CredentialSpec(key: "api_key", label: "API key", envNames: ["TMDB_API_KEY"])
        ],
        signupURL: "https://www.themoviedb.org/settings/api"
    )

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tmdb-meta",
            subcommands: [Movie.self, AuthCommand<TMDBMeta>.self]
        )
    }
}

struct Movie: CLICommand {
    static let serviceID = "tmdb"

    @Argument var id: Int
    @OptionGroup var common: CommonOptions

    func execute() async throws {
        let key = try CredentialResolver(service: TMDBMeta.service).require("api_key")
        let movie = try await TMDBMetadata.movie(id, configuration: .init(apiKey: key))
        try common.emitter.emit(MoviePayload(movie, full: common.full))
    }
}
```

`AuthCommand<TMDBMeta>` provides `auth login`, `auth status` and `auth logout` from the `ServiceSpec` alone. Adopting `CLICommand` maps any thrown `CLIError` onto the right exit code and envelope.

## Discovery: `describe` and `mcp`

Add two lines to a tool's subcommand list and it becomes self-describing:

```swift
subcommands: [
    Movie.self,
    AuthCommand<TMDBFetch>.self,
    DescribeCommand<TMDBFetch>.self,
    MCPCommand<TMDBFetch>.self,
]
```

### `<tool> describe --json`

A machine-readable manifest: every invocable command, its arguments, permitted
values, defaults, output formats and exit codes.

```json
{
  "tool": "yt-fetch", "version": "0.2.0", "service": "youtube", "requiresAuth": false,
  "formats": ["json","ndjson","text","csv","markdown"],
  "exitCodes": {"1":"the resource does not exist; do not retry", "…":"…"},
  "commands": [
    { "invocation": "yt-fetch search", "path": ["search"], "summary": "Search YouTube.",
      "arguments": [
        {"kind":"positional","name":"query","required":true},
        {"kind":"option","name":"--sort","values":["relevance","date","views","rating"],"defaultValue":"relevance"}
      ] }
  ]
}
```

It is **derived from ArgumentParser's own `--experimental-dump-help`**, not
hand-maintained — a hand-written manifest is wrong the first time someone adds a
flag. Commands are flattened with a `path` array so a caller never walks a tree
to find an invocation, and `--help`/`--version` are stripped since they belong to
the parser rather than the tool.

Aggregate every tool's manifest and you have the index a directory site needs,
generated rather than curated.

### `<tool> mcp`

A Model Context Protocol server on stdio, with one MCP tool per command,
generated from the same manifest:

```json
{ "mcpServers": { "youtube": { "command": "yt-fetch", "args": ["mcp"] } } }
```

Three decisions worth knowing:

- **It re-executes itself per call.** stdout is the protocol channel, so a
  command writing its payload there would corrupt the stream. A subprocess keeps
  them apart and preserves the exit code and stderr envelope exactly as a shell
  caller sees them.
- **Failures come back as tool content with `isError`, not JSON-RPC errors.** The
  stderr envelope carries the `hint` that lets a model repair itself; a transport
  fault would throw that away.
- **Format flags are hidden over MCP.** The transport always wants the piped
  default, and offering `--text` invites a model to request prose it then has to
  parse.

Credentials are resolved inside the process, so an MCP client never holds them —
unlike a server configured with keys pasted into its JSON.

One caveat worth weighing before wiring up two dozen of these: MCP tool
definitions occupy the model's context permanently, whereas a CLI costs nothing
until invoked. Register the servers you use constantly; leave the rest as CLIs.

## Field selection

`--fields` narrows any payload to the named top-level keys, in whichever form
gets typed:

```sh
yt-fetch video dQw4w9WgXcQ --fields title,author     # commas
yt-fetch video dQw4w9WgXcQ --fields title author     # spaces
```

Both work. The commas matter more than they look: `--fields` parses up to the
next option, so `title,author` arrived as a single name, matched nothing, and
printed `{}` with exit 0 — a mistake wearing the costume of an answer.

Unknown names stay ignored, deliberately: a caller narrowing output across
several services should not have to know which fields each one exposes. But
when *every* name is unknown the result is empty, so that case warns on stderr
and lists what the payload actually has:

```
warning: --fields matched nothing; this payload has: author, category, channelId, …
```

stdout still carries the JSON, so a pipeline is unaffected and `--quiet`
silences the warning.

## The combined index

`agentic-index` collects every tool's `describe --json` into one document:

```sh
$ agentic-index --dir /opt/homebrew/bin --text
7 tools · 78 commands

  discogs-fetch  0.1.0  Search the Discogs catalogue and marketplace.
  domaincheck    0.1.0  Check whether domains are available to register.
  feed-fetch     0.1.0  Read RSS, Atom, RDF and JSON feeds as structured data.
  gen            0.1.0  Generate secure passwords, passphrases and UUIDs.
  hn-fetch       0.1.0  Read Hacker News listings, comment threads and search.
  readable       0.1.0  Convert web pages to clean Markdown.
  yt-fetch       0.2.0  Fetch YouTube transcripts, video, channel and comment metadata.

$ agentic-index yt-fetch readable feed-fetch -o index.json
```

A directory rendered from this is generated rather than curated — publishing a tool updates the listing, and nothing is maintained twice. It is also what an agent should fetch instead of discovering binaries one at a time: one request, every command, every argument, every exit code.

Two details worth knowing:

- **No timestamp by default.** A rebuild that changes nothing produces a byte-identical file, so CI does not churn the repository. Pass `--stamp` when you want one.
- **A broken tool is skipped, not fatal.** It is reported on stderr and the run exits `5`, so CI can decide whether a partial index is publishable. One unbuildable binary should not empty the directory.

`ToolIndex.build(from:)` is public, so the merge is usable directly and is tested independently of any binary.

## Credentials

Resolution order — **environment first, then the store**:

1. `TMDB_API_KEY` (or whatever the `ServiceSpec` declares)
2. `~/.config/arraypress/credentials.json`

Environment wins so CI, containers and one-off overrides never touch persistent state — and so the value your *library* reads through its own `Configuration.default` is the value the CLI uses.

```json
{
  "version": 1,
  "credentials": {
    "tmdb":    { "api_key": "…" },
    "discogs": { "token": "…" }
  }
}
```

One shared file is what makes many small binaries workable: `tmdb-meta auth login` and `discogs-meta auth login` write to the same place, and any tool can report on the others.

```sh
tmdb-meta auth login              # prompts, echo disabled
echo "$KEY" | tmdb-meta auth login --stdin --key api_key
tmdb-meta auth status             # exits 3 if a required credential is missing
```

Secrets are never accepted as command-line arguments — an argument is visible in `ps` and written to shell history.

### Why not the Keychain

Keychain ACLs are bound to code signature, and a SwiftPM or Homebrew-bottled binary is **ad-hoc signed**: its identity changes on every rebuild and every version bump. An item written by one build prompts when read by the next, and `brew upgrade` re-triggers it.

That breaks worst under this project's shape, where many separate binaries share one store — `tmdb-meta` writing an item that `discogs-meta` reads is a cross-identity access, and therefore a GUI prompt.

The decisive problem is headless use. An agent invoking these tools from a background process, over SSH, or in CI meets either a locked keychain (`errSecInteractionNotAllowed`) or a dialog that hangs the call — worse than a clean failure.

The security gap is also narrower than it looks: the login keychain is unlocked for the whole session, so both it and a `0600` file are readable by any process running as you. Keychain's real edge is encryption at rest against offline disk access, which FileVault already covers.

`CredentialStore` is a protocol precisely so a Keychain backend can be added — reasonable if you sign with a stable Developer ID — without touching a single service CLI.

## Output

| stdout is | Default format |
|-----------|----------------|
| A pipe | Compact JSON |
| A terminal | Readable text |

Overridable with `--json`, `--text`, `--ndjson`, `--csv`, `--markdown`.

In text mode, list results render as an **aligned table** for payloads adopting `TableRenderable`:

```
ID           TITLE                                            LENGTH  VIEWS       PUBLISHED
───────────  ───────────────────────────────────────────────  ──────  ──────────  ───────────
PXC_PYeB6F8  Rick Astley - Angels On My Side (Live at The O…  3:51    45K views   1 month ago
LaOUkDBDjW8  Rick Astley - Dance (Live at The O2, London, 2…  3:54    20K views   1 month ago
```

The table fits the terminal by shrinking the **widest flexible column only** — a type declares which columns may shorten, so an identifier stays copyable while a title gives up its space. Widths are measured in display cells rather than characters, so emoji and CJK don't misalign every row after them. Adoption is opt-in: a community post or a comment is a paragraph, and forcing one into a column would truncate the only part that matters.

`--csv` and `--markdown` flatten records into a table. Columns are the **union** of keys across every record, sorted — so a record missing an optional field can't shorten the table or shift other rows into the wrong columns. Nested arrays and objects are JSON-encoded into their cell rather than dropped, because a dense cell is recoverable and a missing one isn't. CSV follows RFC 4180 (CRLF, doubled quotes); Markdown escapes pipes and folds newlines to `<br>` so one cell can't break a row. Keys are sorted so output is byte-stable across runs, and piped JSON is compact — for a caller paying by the token, pretty-printing whitespace is pure cost.

```swift
struct MoviePayload: Codable, TextRenderable {
    let title: String
    let year: Int

    func renderText() -> String { "\(title) (\(year))" }
}

try common.emitter.emit(payload)      // one result
try common.emitter.emitAll(payloads)  // array, or NDJSON lines
```

Diagnostics, warnings and prompts all go to **stderr**, so piping stdout into a parser never has to strip chatter.

## Cache

```swift
let cache = DiskCache(tool: "yt-meta", isEnabled: !common.noCache)

let payload = try await cache.cached("transcript/\(id)/en", ttl: 7 * 24 * 3600) {
    TranscriptPayload(try await YouTubeTranscript.fetch(id))
}
```

Entries are plain files under `~/.cache/arraypress/<tool>/`, inspectable with `ls` and resettable with `rm -rf`. A corrupt, missing or unwritable entry degrades to a live fetch — the cache is never a reason for a command to fail.

Include every input that changes the result in the key, including flags that change the payload shape: a cached slim result must never be served to a caller that asked for `--full`.

## Requirements

- macOS 14+ on Apple silicon
- Swift 6.0+

## Naming Convention

Every tool in the family is `<service>-fetch` — `yt-fetch`, `tmdb-fetch`, `reddit-fetch`, `web-fetch`. The suffix is a family marker, not a description of any one tool.

It matters because it is guessable: a caller that has met one tool can infer the binary name of the next without being told, which is worth more across two dozen binaries than precision in any single one. `-fetch` rather than `-meta` because these return content — transcripts, comments, posts — not only metadata.

The same predictability applies inside each tool: identical global flags (`--json`, `--fields`, `--full`, `--no-cache`), the same `auth` subcommand even for services needing no credentials, and the same exit codes.

## License

MIT — see [LICENSE](LICENSE).
