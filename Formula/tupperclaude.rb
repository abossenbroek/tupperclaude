# Homebrew formula for tupperclaude.
#
# A formula, not a cask: casks install pre-built macOS artifacts (.app/.pkg/
# .dmg), and this is a zsh plugin installed from source.
#
# The stable url/version/sha256 stanza is written by .github/workflows/release.yml
# when a tag is pushed; `head` stays alongside it so `brew install --HEAD` keeps
# tracking main. Editing the stable stanza by hand means the next release
# overwrites it.
#
# `make test-brew` does not read either stanza: it packages the current working
# tree into a tarball and builds the formula against that, so packaging is
# exercised before a tag rather than after it.
class Tupperclaude < Formula
  desc "Run Claude Code in a sandboxed Docker container"
  homepage "https://github.com/abossenbroek/tupperclaude"
  head "https://github.com/abossenbroek/tupperclaude.git", branch: "main"
  license any_of: ["MIT", "BSD-3-Clause"]

  # zsh is the runtime: this is a zsh plugin and nothing here loads under bash.
  # jq is equally hard — claude-ts-ensure pipes through it and the wizard's
  # preflight fails without it.
  #
  # Everything else is deliberately absent. Homebrew dropped `=> :recommended`
  # and `=> :optional` along with `--without-*`, so a "recommended" dependency
  # today installs unconditionally; the companions listed in caveats would
  # become mandatory downloads for users who want none of them. Docker Desktop
  # is a cask, and the plugin's own preflight reports it missing far better than
  # a failed brew install would. oh-my-zsh has no formula at all — it installs
  # via its own script, and the plugin works without it.
  depends_on "jq"
  depends_on "zsh"

  def install
    # The layout matters. tupperclaude.plugin.zsh resolves TUPPERCLAUDE_DIR as
    # ${0:A:h}, and zsh/tupperclaude.zsh resolves it as ${0:A:h:h} — so the
    # shim, zsh/, docker/ and .version must keep their relative positions or
    # the plugin resolves its Dockerfile and version to nothing.
    pkgshare.install "tupperclaude.plugin.zsh"
    pkgshare.install "zsh"
    pkgshare.install "docker"
    pkgshare.install "fish"
    pkgshare.install ".version"
    doc.install "README.md", "INSTALL.md"
  end

  def caveats
    <<~EOS
      tupperclaude is a zsh plugin, so it has to be sourced. Add this to ~/.zshrc:

        source #{opt_pkgshare}/tupperclaude.plugin.zsh

      Under oh-my-zsh, source the same line after the `source $ZSH/oh-my-zsh.sh`
      line. Completions bind in either compinit order — nothing extra to add.

      Then set it up (needs Docker Desktop running):

        claude-docker-configure

      Required, and not installable as a formula:
        Docker Desktop      brew install --cask docker-desktop

      Optional, each enabling one wizard answer. The credentials these write on
      the host are what the sandbox mounts, so install the ones you want before
      running the wizard:
        tailscale           brew install tailscale
        awscli              brew install awscli
        google-cloud-sdk    brew install --cask google-cloud-sdk
        kubectl, k9s        brew install kubernetes-cli k9s
    EOS
  end

  test do
    # ZDOTDIR (with HOME alongside it, so nothing resolves to the real one)
    # gives a throwaway startup environment: zsh reads .zshrc from $ZDOTDIR
    # instead of $HOME, which is the only way to test a plugin that must be
    # sourced from an rc file without touching the tester's own dotfiles.
    # compinit is the user's job, not the plugin's — a plugin that ran it would
    # be slow and would clobber the cache of whoever runs it properly. So the
    # throwaway .zshrc has to run it, exactly as a real user's does, or there is
    # no completion system for the binding assertion below to find.
    (testpath/".zshrc").write <<~ZSHRC
      source #{pkgshare}/tupperclaude.plugin.zsh
      autoload -Uz compinit
      compinit -u -d #{testpath}/.zcompdump
    ZSHRC

    ENV["HOME"] = testpath
    ENV["ZDOTDIR"] = testpath

    # The plugin loads, the commands exist, and the version came from the
    # .version file installed above rather than the "unknown" fallback.
    assert_match "tupperclaude", shell_output("zsh -i -c 'claude-docker-status --version'")
    refute_match "unknown", shell_output("zsh -i -c 'claude-docker-status --version'")

    # The completion is bound — the bug that made this worth asserting was
    # invisible to every test that did not start a real shell.
    assert_equal "_claude-docker",
                 shell_output("zsh -i -c 'print -r -- ${_comps[claude-docker-arm]}'").strip

    # The Dockerfile survived the install with its path intact; without it the
    # build path fails much later with a confusing message.
    assert_predicate pkgshare/"docker/Dockerfile", :exist?
  end
end
