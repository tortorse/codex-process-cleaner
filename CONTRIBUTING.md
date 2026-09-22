# Contributing

Bug reports and pull requests are welcome.

Please keep the safety rules intact:

- Never classify a process as closeable from its name alone.
- Keep Codex, ChatGPT UI processes, and the cleaner protected.
- Do not require administrator privileges.
- Use `SIGTERM`; do not add forced termination as a default action.

Before opening a pull request, run:

```bash
./scripts/build-release.sh
codesign --verify --deep --strict build/CodexProcessCleaner.app
lipo -info build/CodexProcessCleaner.app/Contents/MacOS/CodexProcessCleaner
```
