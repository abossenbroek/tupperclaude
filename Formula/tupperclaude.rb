# Homebrew formula for tupperclaude.
#
# A formula, not a cask: casks install pre-built macOS artifacts (.app/.pkg/
# .dmg), and this is a zsh plugin installed from source.
#
# There is no tagged release yet, so this is HEAD-only — `brew install --HEAD`.
# When v0.1.0 is cut, add the stable stanza above `head`:
#
#     url "https://github.com/abossenbroek/tupperclaude/archive/refs/tags/v0.1.0.tar.gz"
#     sha256 "<shasum -a 256 of that tarball>"
#
# `make test-brew` does not depend on that release existing: it packages the
# current working tree into a tarball and builds the formula against it, so the
# packaging is exercised today rather than after the first tag.
class Tupperclaude < Formula
  desc "Run Claude Code in a sandboxed Docker container"
  homepage "https://github.com/abossenbroek/tupperclaude"
  head "https://github.com/abossenbroek/tupperclaude.git", branch: "main"
  license any_of: ["MIT", "BSD-3-Clause"]

  # jq is a hard runtime dependency, not a nicety: claude-ts-ensure pipes
  # through it, and the wizard's preflight fails without it. Docker itself is
  # deliberately NOT a dependency — it is Docker Desktop, a cask, and the
  # plugin's own preflight checks for it with a better message than a failed
  # brew install would give.
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

      Then set it up (needs Docker Desktop running):

        claude-docker-configure

      Completions are registered by the plugin itself, in either compinit
      order — nothing extra to add.
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
