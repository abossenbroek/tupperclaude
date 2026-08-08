# Set up tupperclaude with an AI assistant

Copy the prompt below into Claude Code, Warp, Codex, Cursor, Gemini CLI, or any coding
agent with shell access. It walks the agent through installing and configuring
tupperclaude on your machine, asking you before anything is changed, and testing the
result at the end.

You stay in control the whole way: the agent proposes, you approve.

**Prefer to do it yourself?** [INSTALL.md](INSTALL.md) has the same steps by hand, and
`claude-docker-configure` is an interactive wizard that asks the same questions.

---

## The prompt

````text
Help me install and set up "tupperclaude" — a zsh plugin that runs Claude Code inside a
sandboxed Docker container.

Repo: https://github.com/abossenbroek/tupperclaude

Work through the steps in order. Follow these rules the whole way:

RULES
- Show me each command before you run it.
- Ask me before you change any file of mine. Always back up ~/.zshrc before editing it.
- Ask me before starting the image build. It takes about 15 minutes and 9 GB of disk.
- Never invent a secret. If a step needs an auth key or a password-manager reference,
  stop and ask me for it.
- If something fails, stop and show me the exact error. Do not work around it.
- Do not run `claude-docker-configure`. It is an interactive wizard that needs a real
  terminal and will refuse to run from a tool call. Ask me the questions yourself
  (STEP 4) instead.

STEP 1 — Check what I already have

Run these and show me the results as a short table:

  docker --version
  docker info >/dev/null 2>&1 && echo "docker daemon: running" || echo "docker daemon: NOT running"
  zsh --version
  jq --version
  git --version
  uname -m

Then tell me whether my CPU is arm64 (Apple Silicon) or amd64 (Intel). I need that later.

Docker and jq are required. If either is missing, stop and tell me how to install it.
If the Docker daemon is not running, tell me to start Docker Desktop.

STEP 2 — Find my zsh plugin manager

Look at ~/.zshrc and my home directory and tell me which of these I use:

  oh-my-zsh   the directory ~/.oh-my-zsh exists
  zinit       "zinit" appears in ~/.zshrc
  antidote    "antidote" appears in ~/.zshrc
  sheldon     the file ~/.config/sheldon/plugins.toml exists
  zplug       the directory ~/.zplug exists
  antigen     "antigen" appears in ~/.zshrc
  none        none of the above

If you find more than one, ask me which to use. Do not guess.

STEP 3 — Install the plugin

Use the option matching my manager. Show me the exact edit and wait for my approval.

  oh-my-zsh:
    git clone https://github.com/abossenbroek/tupperclaude \
      ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/tupperclaude
    then add tupperclaude to the plugins=(...) line in ~/.zshrc

  zinit:      add to ~/.zshrc:  zinit light abossenbroek/tupperclaude
  antidote:   add to my plugins file:  abossenbroek/tupperclaude
  sheldon:    run: sheldon add tupperclaude --github abossenbroek/tupperclaude
  zplug:      add to ~/.zshrc:  zplug "abossenbroek/tupperclaude", use:"tupperclaude.plugin.zsh"
  antigen:    add to ~/.zshrc:  antigen bundle abossenbroek/tupperclaude
  none:       git clone https://github.com/abossenbroek/tupperclaude ~/.tupperclaude
              then add to ~/.zshrc:  source ~/.tupperclaude/tupperclaude.plugin.zsh

Then check it loaded:

  zsh -i -c 'claude-docker-status --version'

This must print a version. If the command is not found, stop — the plugin did not load.

STEP 4 — Ask me how to configure it

Ask me these ONE AT A TIME and wait for each answer. Give me the recommendation in
brackets if I am unsure.

  1. Networking. [tailscale]
     - tailscale: each project gets its own Tailscale node, so the sandbox can reach
       your private network.
     - default: plain Docker networking. Simpler, no Tailscale account needed.

  2. Only if I chose tailscale — how should the auth key be supplied?
     - I will export TS_AUTHKEY myself, or
     - a 1Password reference such as op://Private/Tailscale/authkey
     Do NOT make up a key. Ask me for the exact value or reference.

  3. Include the AWS CLI in the image? [no]
  4. Include the Google Cloud SDK? [no]
  5. Include Kubernetes tools — kubectl, helm, k9s? [no]
  6. Only if I said yes to Kubernetes — which Helm major: 3, 4, or both? [3]

Then write my answers to ~/.tupperclaude.zsh, showing me the file first:

  zstyle ':omz:plugins:tupperclaude' network tailscale
  zstyle ':omz:plugins:tupperclaude' op-ref 'op://Private/Tailscale/authkey'
  zstyle ':omz:plugins:tupperclaude' aws on
  zstyle ':omz:plugins:tupperclaude' gcloud on
  zstyle ':omz:plugins:tupperclaude' k8s on
  zstyle ':omz:plugins:tupperclaude' helm both

Include ONLY the lines matching my answers. Leave out anything I said no to.

Then make sure ~/.zshrc sources it, ABOVE the plugin manager lines:

  [[ -r ~/.tupperclaude.zsh ]] && source ~/.tupperclaude.zsh

STEP 5 — Check the setup before building

  zsh -i -c 'claude-docker-doctor'

Show me the output. It reports what is missing and how to fix it. The image will be
reported as not built — that is expected at this point.

Fix anything else it flags before continuing.

STEP 6 — Build the image

ASK ME FIRST. About 15 minutes and 9 GB of disk; roughly 12 GB free is needed to start.

Use the command for my CPU from STEP 1:

  arm64 (Apple Silicon):  zsh -i -c 'claude-docker-build-arm --yes'
  amd64 (Intel):          zsh -i -c 'claude-docker-build-amd64 --yes'

This prints a long build log and ends with a list of tool versions. If it fails, show me
the last 30 lines.

STEP 7 — Test it

Run all four and show me a pass/fail for each:

  1. zsh -i -c 'claude-docker-doctor'
     Everything should now pass, including the image check.

  2. zsh -i -c 'print -r -- ${_comps[claude-docker-arm]}'
     Must print exactly: _claude-docker
     That means tab-completion is wired up.

  3. zsh -i -c 'claude-docker-status'
     Lists running sandboxes. An empty list is a pass.

  4. Ask me to run this one myself, in my own terminal — it takes over the window:
       cd <some project directory> && claude-docker-arm
     I should land in tmux with Claude Code running. Tell me to check that the window
     list at the bottom matches the tools I enabled, and that pressing Ctrl-b then d
     detaches.

Finally, tell me these two things:

  - The first run in a directory writes a MACHINE.md file there describing the sandbox
    to Claude. Add it to .gitignore, or delete it — nothing depends on it.
  - Inside the sandbox I have to sign in to Claude Code again. The sandbox keeps its own
    login, separate from my host.
````

---

## What the agent will and will not do

**It asks before:** editing `~/.zshrc`, writing `~/.tupperclaude.zsh`, and starting the
build.

**It will not:** invent a Tailscale key or a 1Password reference, work around a failure
without telling you, or run the interactive wizard from a tool call — that needs a real
terminal and refuses cleanly rather than silently taking every default.

**You still run one thing yourself:** the final `claude-docker-arm`. It takes over the
terminal with tmux, which an agent cannot usefully drive for you.

## If it goes wrong

Ask the agent to run `claude-docker-doctor` and paste the whole output — it names what is
broken and the command that fixes it. That output is also the right thing to attach to a
[bug report](https://github.com/abossenbroek/tupperclaude/issues/new/choose).
