return {
  name = "homebrew update formula",
  request = {
    action = "update",
    system = "homebrew",
    packages = {
      { name = "python@3.12" }
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
      match = "/opt/homebrew/bin/brew info --json=v2 python@3.12",
      exitCode = 0,
      stdout = [[{"formulae":[{"name":"python@3.12","full_name":"python@3.12","desc":"Interpreted, interactive, object-oriented programming language","homepage":"https://www.python.org/","tap":"homebrew/core","license":"Python-2.0","dependencies":[],"binaries":["python3.12"],"installed":[{"version":"3.12.8"}],"versions":{"stable":"3.12.9"},"outdated":true}],"casks":[]}]],
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew upgrade python@3.12",
      exitCode = 0,
      stdout = "==> Upgrading python@3.12\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "updated", "success" },
    eventPayloads = {
      updated = "{1=<lua-value>}",
      success = "ok",
    },
  }
}
