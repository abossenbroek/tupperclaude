# Set up tupperclaude with an AI assistant

Copy the prompt below into Claude Code, Warp, Codex, Cursor, Gemini CLI, or any coding
agent with shell access. It walks the agent through installing and configuring
tupperclaude on your machine, asking you before anything is changed, and testing the
result at the end.

You stay in control the whole way: the agent proposes, you approve.

**Prefer to do it yourself?** [INSTALL.md](INSTALL.md) has the same steps by hand, and
`claude-docker-configure` is an interactive wizard that asks most of the same questions
— it covers networking, the auth key, the optional toolchains and Helm, but not
`docker-sock`, which the prompt below asks about because it defaults to on.

---

## The prompt

````text
Help me install and set up "tupperclaude" — a zsh plugin that runs Claude Code inside a
sandboxed Docker container.

Repo: https://github.com/abossenbroek/tupperclaude

Work through the steps in order. Follow these rules the whole way:

RULES
- Show me each command before you run it.
- Ask me before you change any file of mine.
- My zshrc is whatever STEP 2 resolves it to. Do not assume ~/.zshrc anywhere — with
  ZDOTDIR set, ~/.zshrc is a file zsh never reads, and editing it means editing
  nothing while the real one silently goes unbacked-up. STEP 2 comes before any edit
  for exactly this reason; take the backup there.
- Before adding any line to a file, grep for it first. If it is already there, change
  nothing. Running this whole prompt twice must never duplicate a line.
- Ask me before starting the image build. It takes about 15 minutes and 9 GB of disk.
- Never invent a secret. If a step needs an auth key or a password-manager reference,
  stop and ask me for it.
- Never write a secret value into any file. If I give you a key, tell me where to
  export it and stop — do not put it in ~/.zshrc or ~/.tupperclaude.zsh.
- If something fails, stop and show me the exact error. Do not work around it.
- Do not run `claude-docker-configure`. It is an interactive wizard. Without a terminal
  it refuses to start; with one — some agent runners do allocate a pty — it starts and
  then blocks on input you cannot type. Ask me the questions yourself (STEP 4) instead.

STEP 1 — Check what I already have

Run these and show me the results as a short table:

  uname -s
  uname -m
  docker --version
  docker info >/dev/null 2>&1 && echo "docker daemon: running" || echo "docker daemon: NOT running"
  docker info --format '{{.OperatingSystem}}' 2>/dev/null
  zsh --version
  jq --version
  git --version
  command -v claude || echo "claude: MISSING"
  test -f ~/.claude.json && echo "claude.json: present" || echo "claude.json: MISSING"
  df -g "$HOME" | tail -1

Then tell me whether my CPU is arm64 (Apple Silicon) or amd64 (Intel). I need that later.

Stop and tell me how to fix it if any of these is true:

  - `uname -s` is not Darwin. tupperclaude is macOS-only today.
  - Docker, jq or git is missing. For git the fix is `xcode-select --install`;
    without it every clone below pops a GUI installer instead.
  - The Docker daemon is not running — I need to start Docker Desktop.
  - Claude Code itself is missing. Install it first — the file below comes from it.
  - `~/.claude.json` is missing. Fix: I run Claude Code once on the host, so it
    creates that file. The setup check below requires it.
  - Less than about 12 GB free in my home directory.

Warn me, but continue, if the Docker OperatingSystem is not "Docker Desktop"
(OrbStack and Colima report something else). tupperclaude mounts Docker Desktop's
ssh-agent socket at a fixed path, and that check will FAIL on other engines.

STEP 2 — Find my zsh plugin manager

First find where my zshrc actually lives — it is not always ~/.zshrc:

  zsh -i -c 'print -r -- "ZDOTDIR=${ZDOTDIR:-$HOME}"'

Take the text after ZDOTDIR= on the one line that starts with it, and stop if there
is not exactly one such line — themes print their own output here, and this answer
decides which file every later edit lands in.

Call the result <zshrc> = <that>/.zshrc, use it everywhere below and everywhere later
in this prompt, and tell me the path you settled on.

Then back it up, before any edit:

  test -f <zshrc> && cp <zshrc> <zshrc>.tupperclaude-bak-$(date +%Y%m%d%H%M%S)

Show me the backup path. If <zshrc> does not exist yet, say so — you will create it in
STEP 3. If it is a symlink into a dotfiles repo, tell me before you append: the edit
lands in that repo, not just on this machine.

Then look at that file and my home directory and tell me which of these I use:

  oh-my-zsh   the directory ~/.oh-my-zsh exists
  zinit       "zinit" appears in <zshrc>
  antidote    "antidote" appears in <zshrc>
  sheldon     the file ~/.config/sheldon/plugins.toml exists
  zplug       the directory ~/.zplug exists
  antigen     "antigen" appears in <zshrc>
  none        none of the above

If you find more than one, ask me which to use. Do not guess.

If it is antidote, also tell me which file holds my plugin list, and whether my
<zshrc> calls `antidote load` or sources a generated ~/.zsh_plugins.zsh. STEP 3
needs to know which.

STEP 3 — Install the plugin

Use the option matching my manager. Show me the exact edit and wait for my approval.

If the clone target already exists, git prints an error — that is expected, not a
failure, and it means a previous run got this far. Do not delete it and do not stop:
leave it alone, or run `git -C <that directory> pull --ff-only`, and tell me which.

  oh-my-zsh:
    first resolve the custom directory in zsh, where ZSH_CUSTOM is actually set:
      zsh -i -c 'print -r -- "ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"'
    Take the text after ZSH_CUSTOM= on the one line that starts with it, and stop
    if there is not exactly one such line. Themes like powerlevel10k print their
    own output here, and this answer becomes a path you clone into — do not just
    take the whole output.
    then, unless <that>/plugins/tupperclaude already exists:
      git clone https://github.com/abossenbroek/tupperclaude <that>/plugins/tupperclaude
    then add tupperclaude to the existing plugins=(...) line in <zshrc> — unless
    it is already in that array, in which case change nothing.
    Edit that line in place — do not add a second plugins=() line, and do not
    reformat the array. The array often spans several lines; insert the word
    inside the existing parentheses without reflowing them. If you cannot see one
    unambiguous plugins=( ... ) block, stop and show me the lines instead of
    guessing. A malformed plugins=() breaks my login shell.

  zinit:      add to <zshrc>:  zinit light abossenbroek/tupperclaude
  antidote:   add to my antidote plugins file:  abossenbroek/tupperclaude
              Find that file first — it is usually ~/.zsh_plugins.txt, but check what
              my <zshrc> actually references. If my setup is the static kind, where
              <zshrc> sources a generated ~/.zsh_plugins.zsh, adding to the .txt
              alone loads nothing; regenerate it too:
                antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
              If my <zshrc> uses `antidote load`, the .txt alone is enough.
  sheldon:    check ~/.config/sheldon/plugins.toml for tupperclaude first; if it is
              not there, run:
                sheldon add tupperclaude --github abossenbroek/tupperclaude
              Then check <zshrc> for `sheldon source`. If it is missing, nothing
              sheldon manages loads at all, so add:
                eval "$(sheldon source)"
              It has to come before anything that uses a sheldon-managed plugin.
  zplug:      add to <zshrc>:  zplug "abossenbroek/tupperclaude", use:"tupperclaude.plugin.zsh"
              This line must go ABOVE the existing `zplug load` line, not at the
              end of the file — a declaration after it is ignored.
              then run:  zsh -i -c 'zplug install'
              zplug does not clone on its own; without this the next shell says
              "not installed" and the check below fails.
  antigen:    add to <zshrc>:  antigen bundle abossenbroek/tupperclaude
              This line must go ABOVE the existing `antigen apply` line, not at
              the end of the file — a bundle after it is ignored.
  none:       unless ~/.tupperclaude already exists:
                git clone https://github.com/abossenbroek/tupperclaude ~/.tupperclaude
              then add to <zshrc>:  source ~/.tupperclaude/tupperclaude.plugin.zsh

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

  2. Only if I chose tailscale — the auth key.
     Tell me first that the key must be REUSABLE, TAGGED, and ephemeral OFF, and
     that I can mint one at https://login.tailscale.com/admin/settings/keys.
     tupperclaude creates one Tailscale node per project directory, so a
     single-use key works for the first project and then quietly stops working —
     long after this setup has finished and told me it succeeded.
     Then ask how it should be supplied:
     - a 1Password reference such as op://Private/Tailscale/authkey, or
     - I export TS_AUTHKEY myself, in my own shell.
     Do NOT make up a key, and do NOT write one into a file. If I pick the second
     option, tell me to run `export TS_AUTHKEY=...` in my own terminal and note that
     the check in STEP 5 will still report authkey as FAIL for you, because your
     shell cannot see what I exported in mine. That one is expected.
     If I pick the 1Password option, check I have the CLI: `command -v op`. Without
     it the same check fails.

  3. Include the AWS CLI in the image? [no]
  4. Include the Google Cloud SDK? [no]
  5. Include Kubernetes tools — kubectl, helm, k9s? [no]
     If I say yes here and no to question 4, tell me that authenticating to GKE
     needs the Google Cloud SDK too.
  6. Only if I said yes to Kubernetes — which Helm major: 3, 4, or both? [3]
  7. Mount the Docker socket into the sandbox? [on — this is the default]
     On, the sandbox can run docker commands. It also means the sandbox is NOT a
     security boundary: access to the docker socket is equivalent to root on my
     host. Off is safer and breaks anything in the sandbox that needs Docker.

If ~/.tupperclaude.zsh already exists, show me what is in it, back it up with

  cp ~/.tupperclaude.zsh ~/.tupperclaude.zsh.bak-$(date +%Y%m%d%H%M%S)

and ask me before replacing it. Keep any zstyle line I already set that is not one of
the ones below — `home`, `dockerfile` and `machine-md` are real options this prompt
never asks about, and losing them silently would be worse than asking.

Then write my answers to ~/.tupperclaude.zsh, showing me the file first:

  zstyle ':omz:plugins:tupperclaude' network tailscale
  zstyle ':omz:plugins:tupperclaude' op-ref 'op://Private/Tailscale/authkey'
  zstyle ':omz:plugins:tupperclaude' aws on
  zstyle ':omz:plugins:tupperclaude' gcloud on
  zstyle ':omz:plugins:tupperclaude' k8s on
  zstyle ':omz:plugins:tupperclaude' helm both
  zstyle ':omz:plugins:tupperclaude' docker-sock off

ALWAYS write the network line, with whichever value I chose — `tailscale` or
`default`. Leaving it out does not mean "no networking": the built-in default is
`tailscale`, so omitting it gives me the sidecar I just declined, plus an authkey
failure nobody expected.

The leave-it-out rule applies only to the yes/no options — aws, gcloud, k8s — to helm,
which belongs in the file only if I chose Kubernetes, and to docker-sock, which belongs
there only if I asked for it off.

Then make sure <zshrc> sources it. First check whether it already does:

  grep -n 'tupperclaude.zsh' <zshrc>

If there is no match, append exactly this line — no guard, no brackets, and it can go
at the end of the file:

  source ~/.tupperclaude.zsh

Write it exactly that way. `claude-docker-configure` recognises this spelling and will
leave it alone; a guarded variant like `[[ -r ... ]] && source ...` does not match, so
the wizard would later append a second copy.

STEP 5 — Check the setup before building

  zsh -i -c 'claude-docker-doctor'

Show me the output, then STOP and read it with me before continuing.

This command EXITS NON-ZERO at this point, and that is expected — it is a checklist,
not a failure. All of these are expected now:

  - the base image for my CPU reported FAIL — you have not built it yet (STEP 6)
  - any image row marked "info": the images for the other CPU architecture and the
    two Playwright images. Optional, not missing.
  - authkey FAIL, if I chose tailscale and export TS_AUTHKEY in my own shell
  - ssh-agent FAIL, if you warned me in STEP 1 that my Docker engine is not Docker
    Desktop
  - op-signin FAIL, if I chose 1Password and it is currently locked — and the
    authkey FAIL that comes with it, because the reference cannot resolve while
    it is locked. I can run `op signin` and you can re-run this.

Anything OTHER than those is a real problem. Show it to me and stop — do not try to
fix it yourself.

If I chose 1Password, this step may pop a biometric prompt and hang until I approve
it. Tell me when you are about to run it so I am watching.

STEP 6 — Build the image

ASK ME FIRST. About 15 minutes and 9 GB of disk; roughly 12 GB free is needed to start.

This runs far longer than a default command timeout. Run it in the background, or set
an explicit timeout of at least 30 minutes, or it will look like a failure when it is
merely slow.

Use the command for my CPU from STEP 1:

  arm64 (Apple Silicon):  zsh -i -c 'claude-docker-build-arm --yes'
  amd64 (Intel):          zsh -i -c 'claude-docker-build-amd64 --yes'

This prints a long build log and ends with a list of tool versions. If it fails, show me
the last 30 lines.

STEP 7 — Test it

Run all four and show me a pass/fail for each:

  1. zsh -i -c 'claude-docker-doctor'
     Pass = the image row for my CPU is now ok, and the only FAIL rows left are
     the ones we agreed in STEP 5 were expected. Those three do not go away after
     a build: authkey if I export TS_AUTHKEY in my own shell, ssh-agent if my
     engine is not Docker Desktop, op-signin while 1Password is locked.
     If none of those apply to me, then this must exit 0 and end with the line:
       All required checks passed.
     Rows marked "info" are fine either way — the Playwright images and the images
     for the other CPU architecture are optional, not missing.

  2. zsh -i -c '[[ ${_comps[claude-docker-arm]} == _claude-docker ]] && echo COMPLETION-OK'
     Pass = the output contains COMPLETION-OK. Match on that word rather than on
     the whole line: themes like powerlevel10k print their own chatter into a
     non-interactive `zsh -i -c`, which would swamp an exact-match test.
     If it is absent, everything else still works — it means my ~/.zshrc never runs
     compinit. Tell me, do not try to fix my ~/.zshrc for it.

  3. zsh -i -c 'claude-docker-status'
     Lists running sandboxes. An empty list is a pass.

  4. Ask me to run this one myself, in my own terminal — it takes over the window.
     Tell me to run `exec zsh` first, or open a new terminal: the shell I am sitting
     in was started before you edited ~/.zshrc, so it does not have these commands
     yet. (Your own checks above are unaffected — `zsh -i -c` starts a fresh shell
     every time, which is why they worked.)

     Use the command for my CPU, the same way STEP 6 did:

       exec zsh
       cd <some project directory>
       arm64 (Apple Silicon):  claude-docker-arm
       amd64 (Intel):          claude-docker-amd64
     I should land in tmux with Claude Code running. Tell me to check that the window
     list at the bottom matches the tools I enabled, and that pressing Ctrl-b then d
     detaches.

Finally, tell me these two things:

  - The first run in a directory writes a MACHINE.md file there describing the sandbox
    to Claude. It is removed again when the sandbox exits, unless it was edited. To
    stop it being written at all:
      zstyle ':omz:plugins:tupperclaude' machine-md off
  - Inside the sandbox I have to sign in to Claude Code again. The sandbox keeps its own
    login, separate from my host.
  - If I ever run `claude-docker-configure`, it rewrites ~/.tupperclaude.zsh from the
    template and only restores the options it asks about. Anything else I set — and
    `docker-sock off` in particular — is dropped, silently, back to its default. It
    takes a timestamped backup first, so the old file is recoverable. Tell me this
    only if I actually chose docker-sock off.
````

---

## What the agent will and will not do

**It asks before:** editing `~/.zshrc`, writing `~/.tupperclaude.zsh`, and starting the
build.

**It will not:** invent a Tailscale key or a 1Password reference, write a secret into
any file, work around a failure without telling you, or run the interactive wizard from
a tool call — that needs a real terminal and refuses cleanly rather than silently taking
every default.

**It is safe to run twice:** every edit is preceded by a check for what it would add, so
a second pass never duplicates a line. It will offer to rewrite `~/.tupperclaude.zsh`,
taking a fresh timestamped backup first.

**You still run one thing yourself:** the final `claude-docker-arm` (or
`claude-docker-amd64` on Intel). It takes over the
terminal with tmux, which an agent cannot usefully drive for you.

## If it goes wrong

Ask the agent to run `claude-docker-doctor` and paste the whole output — it names what is
broken and the command that fixes it. That output is also the right thing to attach to a
[bug report](https://github.com/abossenbroek/tupperclaude/issues/new/choose).
