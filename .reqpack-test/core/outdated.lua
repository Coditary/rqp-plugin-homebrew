return {
  name = "homebrew outdated mixed",
  request = {
    action = "outdated",
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
      match = "/opt/homebrew/bin/brew outdated --json=v2",
      exitCode = 0,
      stdout = [[{"formulae":[{"name":"python@3.12","full_name":"python@3.12","desc":"Interpreted, interactive, object-oriented programming language","homepage":"https://www.python.org/","tap":"homebrew/core","license":"Python-2.0","dependencies":[],"binaries":["python3.12"],"installed":[{"version":"3.12.8"}],"versions":{"stable":"3.12.9"},"outdated":true}],"casks":[{"token":"docker-desktop","full_token":"docker-desktop","desc":"App to build and share containerised applications and microservices","homepage":"https://www.docker.com/products/docker-desktop","tap":"homebrew/cask","installed":"4.38.0","version":"4.39.0","outdated":true,"artifacts":[{"binary":["docker",{"target":"/usr/local/bin/docker"}]}]}]}]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "outdated" },
    eventPayloads = {
      outdated = "{1=<lua-value>, 2=<lua-value>}"
    },
    resultCount = 2,
    resultName = "python@3.12",
    resultVersion = "3.12.8",
  }
}
