return {
  name = "homebrew remove cask",
  request = {
    action = "remove",
    system = "homebrew",
    packages = {
      { name = "visual-studio-code" }
    },
  },
  fakeExec = {
    {
      match = "command -v brew 2>/dev/null || { [ -x /opt/homebrew/bin/brew ] && printf '%s\\n' /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && printf '%s\\n' /usr/local/bin/brew; } || { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && printf '%s\\n' /home/linuxbrew/.linuxbrew/bin/brew; }",
      exitCode = 0,
      stdout = "/opt/homebrew/bin/brew\n",
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew info --json=v2 visual-studio-code",
      exitCode = 0,
      stdout = [[{"formulae":[],"casks":[{"token":"visual-studio-code","full_token":"visual-studio-code","desc":"Open-source code editor","homepage":"https://code.visualstudio.com/","tap":"homebrew/cask","installed":"1.99.0","version":"1.99.0","outdated":false,"artifacts":[{"binary":["code",{"target":"/usr/local/bin/code"}]}]}]}]],
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew uninstall --cask visual-studio-code",
      exitCode = 0,
      stdout = "==> Uninstalling Cask visual-studio-code\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "deleted", "success" },
    eventPayloads = {
      deleted = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
