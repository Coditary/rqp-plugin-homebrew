return {
  name = "homebrew list installed packages",
  request = {
    action = "list",
    system = "homebrew",
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
      match = "/opt/homebrew/bin/brew info --json=v2 --installed",
      exitCode = 0,
      stdout = [[{"formulae":[{"name":"wget","full_name":"wget","desc":"Internet file retriever","homepage":"https://www.gnu.org/software/wget/","tap":"homebrew/core","license":"GPL-3.0-or-later","dependencies":["libidn2"],"binaries":["wget"],"installed":[{"version":"1.24.5"}],"versions":{"stable":"1.24.5"},"outdated":false}],"casks":[{"token":"visual-studio-code","full_token":"visual-studio-code","desc":"Open-source code editor","homepage":"https://code.visualstudio.com/","tap":"homebrew/cask","installed":"1.99.0","version":"1.99.0","outdated":false,"artifacts":[{"binary":["code",{"target":"/usr/local/bin/code"}]}]}]}]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "listed" },
    eventPayloads = {
      listed = "{1=<lua-value>, 2=<lua-value>}"
    },
    resultCount = 2,
    resultName = "wget",
    resultVersion = "1.24.5",
  }
}
