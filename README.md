# counselor 👑 <img src="man/figures/logo.png" align="right" height="139" alt="" />

<img src="https://media1.giphy.com/media/v1.Y2lkPTc5MGI3NjExOW90cmx6d3M0MXhhYjZ5MjMxZjJyNWxqZ2pxdXMzdHl5bnoyOG9ybyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/Kxzh8JurnisGhzsyk5/giphy.gif" alt="Good morning my neighbors - Coming to America" width="280" align="right"/>

> *"Good morning, my neighbors!"*
>
> — Now let's review this code before it enters the kingdom.

Voice-powered code review for human oversight of AI-assisted development.

<br clear="both"/>

## 🍟 The McDowell's Approach

They have the Golden Arches. We have the Golden Arcs.

They auto-commit AI-generated code without review. We engage in thoughtful voice conversation first.

{counselor} intercepts git commits and engages you in a voice conversation to review code changes before they proceed. Built for developers who use AI coding assistants (like Claude Code, Copilot, Cursor) and want to maintain meaningful human control over what gets committed.

**The developer always has final say.** Nothing commits without your explicit voice approval. You are the ruler of your codebase — *as Prince Akeem would say, you must choose for yourself.*

## 🎤 Why Voice?

- **Hands stay on keyboard** — no context switching to review UIs
- **Natural conversation** — ask questions, get clarification, discuss concerns
- **Forced attention** — you can't just click "approve" without engaging
- **Audit trail** — every session is logged with full transcript

Think of it as your royal counselor — the one who actually tells you the truth, not just what you want to hear.

## 📦 Installation

```r
# Install from GitHub
pak::pak("dalyanalytics/counselor")

# Or with devtools
devtools::install_github("dalyanalytics/counselor")
```

## ⚙️ Setup

### 1. Get API Keys 🔑

You'll need three API keys:

| Service | Purpose | Get it at |
|---------|---------|-----------|
| Anthropic | Claude for conversation intelligence | [console.anthropic.com](https://console.anthropic.com/) |
| Deepgram | Speech-to-text | [console.deepgram.com](https://console.deepgram.com/) |
| Cartesia | Text-to-speech | [cartesia.ai](https://cartesia.ai/) |

### 2. Configure Environment

Copy the template and add your keys:

```bash
cp .Renviron.example .Renviron
# Edit .Renviron with your actual keys
```

Or set them in R:

```r
usethis::edit_r_environ()
# Add your keys, then restart R
```

### 3. Install Git Hook 🪝

In any project where you want voice reviews:

```r
counselor::install_hooks()
```

Now every `git commit` will trigger a voice review session.

## 👑 Usage

### Automatic (via git hook)

```bash
git add .
git commit -m "Add new feature"
# Voice review starts automatically
# Say "approve" to proceed, "reject" to abort, or "goodbye" to exit gracefully
```

### Manual Review

```r
# Review currently staged changes
counselor::review_commit()

# Review without voice (for testing)
counselor::review_commit(voice = FALSE)
```

### Freeform Voice Session

```r
# Start a voice chat (no git context)
counselor::start_session()
```

### Skip Review When Needed

```bash
# Skip for a single commit (the royal court will be disappointed)
COUNSELOR_SKIP=1 git commit -m "Quick fix"
```

## 🗣️ Voice Commands

During a review session:

| Say | Effect |
|-----|--------|
| "approve", "looks good", "ship it", "lgtm" | ✅ Approve and proceed with commit |
| "reject", "abort", "cancel", "wait" | ❌ Abort the commit |
| "goodbye", "exit", "bye", "I'm done" | 👋 End session gracefully (commit stays staged) |
| Any question | 💬 AI explains that part of the diff |

The "goodbye" option is perfect for when you need to step away or want to review manually without making a decision yet.

## 🔍 What Gets Reviewed

The AI analyzes your staged changes and highlights:

- **Security concerns**: SQL injection, eval/parse usage, hardcoded credentials
- **Shiny-specific issues**: Reactive dependencies, renderUI risks
- **Risky operations**: File deletion, system commands, external downloads
- **Sensitive files**: .env, credentials, keys being modified

## 🛡️ Security Module

{counselor} includes a comprehensive security module to protect against potentially dangerous operations triggered by voice input:

```r
# Validate voice input against command blacklist
counselor::validate_voice_input("please review the auth changes")  # OK
counselor::validate_voice_input("run sudo rm -rf /")  # Blocked!

# Check if an operation needs confirmation
counselor::check_risky_operation("delete the old test files")
# Returns: list(risky = TRUE, patterns = "delete|remove|rm\\s", ...)

# Request voice confirmation for risky operations
if (counselor::request_voice_confirmation("delete all test files")) {
  # User confirmed verbally
}

# Sanitize code before sending to LLM (masks API keys, passwords)
counselor::sanitize_code_for_review('api_key <- "sk-1234567890"')
# Returns: 'api_key = "[REDACTED]"'

# Safe eval wrapper with function allowlist
counselor::safe_eval("1 + 1")  # OK
counselor::safe_eval("system('ls')")  # Blocked!

# Audit security events
counselor::audit_security_logs(days = 30)
```

**Blocked patterns include**: `rm -rf`, `sudo`, `system()`, `eval($())`, credential exposure, and more.

**Risky patterns that request confirmation**: file deletion, `git push --force`, `DROP TABLE`, package installations.

All security events are logged to `~/.counselor/security_logs/` for auditing.

## 💰 Cost Tracking

Sessions are logged with token usage and cost:

```r
# See your usage
counselor::cost_summary()

# View detailed logs
counselor::read_logs(months = 3)
```

Typical session cost: **~$0.02-0.05**

## 🎛️ Configuration

### Change Voice 🔊

Cartesia offers multiple voices. Find voice IDs at [play.cartesia.ai](https://play.cartesia.ai/):

```r
counselor::voice_speak("Hello!", voice_id = "your-preferred-voice-id")
```

### Use Different Model

```r
counselor::review_commit(model = "claude-sonnet-4-20250514")
```

### Hook Management

```r
# Check hook status
counselor::hook_status()

# Remove hooks
counselor::remove_hooks()

# Restore backup hook
counselor::remove_hooks(restore_backup = TRUE)
```

## 🐆 Technical Stack

- **R**: Package interface, git integration via {git2r}, conversation via {ellmer}
- **Python** (via {reticulate}): Voice I/O using Pipecat services
- **Deepgram**: Nova-2 model for speech-to-text
- **Cartesia**: Sonic-2 model for text-to-speech
- **Claude**: Conversation intelligence via {ellmer}

## 📋 Requirements

- R >= 4.1.0
- Python >= 3.10
- Working microphone and speakers
- macOS, Linux, or Windows

## 🔧 Troubleshooting

### "No speech detected"

- Check your microphone permissions
- Ensure your mic is set as default input device
- Try `counselor::test_voice(test_listen = TRUE)`

### Python dependency errors

```r
# Check Python config
reticulate::py_config()

# Force reinstall
reticulate::py_install(c("pipecat-ai[cartesia,deepgram]", "pyaudio"))
```

### PyAudio installation issues (macOS)

```bash
brew install portaudio
pip install pyaudio
```

### Hook not triggering

```r
# Verify installation
counselor::hook_status()

# Check hook is executable
# In terminal: ls -la .git/hooks/pre-commit
```

## 🔒 Privacy & Security

- **Local processing**: Audio is processed via API calls, not stored
- **No training**: Your code/voice is not used to train models
- **Logs are local**: Session transcripts stay on your machine (`~/.counselor/logs/`)
- **Keys are yours**: You control your own API keys
- **Security auditing**: All blocked commands are logged for review

## 💇 Philosophy

Prince Akeem didn't want an arranged marriage. He wanted to find someone who would challenge him, question him, and choose him for who he really was.

Your codebase deserves the same consideration. Don't just accept whatever the AI assistant gives you. Engage with it. Question it. Understand it. Then — and only then — commit.

{counselor} is your barbershop moment. The place where real talk happens before you make your move.

## 📜 License

MIT

## 🌹 Author

Jasmine Daly ([@dalyanalytics](https://github.com/dalyanalytics))

Built for the 2026 RainbowR conference talk on maintaining human oversight in AI-assisted development.

> *"Zamunda, Wakanda, Connecticut — I don't know where you from..."*
> — Tracy Morgan, Coming 2 America

Well, this one's from Connecticut. And unlike the fictional kingdoms of Zamunda and Wakanda, we don't have vibranium or royal rose bearers — but we do have {counselor}.

---

*"Just let your Soul Glo!"* ✨
