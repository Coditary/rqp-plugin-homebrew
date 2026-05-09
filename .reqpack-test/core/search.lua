return {
  name = "homebrew search formula and cask",
  request = {
    action = "search",
    system = "homebrew",
    prompt = "docker",
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
      match = "/opt/homebrew/bin/brew search --formula docker",
      exitCode = 0,
      stdout = "docker\ndocker-compose\n",
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew info --json=v2 --formula docker docker-compose",
      exitCode = 0,
      stdout = [[{"formulae":[{"name":"docker","full_name":"docker","desc":"Pack, ship and run any application as a lightweight container","homepage":"https://www.docker.com/","tap":"homebrew/core","license":"Apache-2.0","dependencies":["docker-completion"],"binaries":["docker"],"installed":[{"version":"28.0.0"}],"versions":{"stable":"28.1.0"},"outdated":true},{"name":"docker-compose","full_name":"docker-compose","desc":"Isolated development environments using Docker","homepage":"https://docs.docker.com/compose/","tap":"homebrew/core","license":"Apache-2.0","dependencies":[],"binaries":["docker-compose"],"installed":[],"versions":{"stable":"2.35.1"},"outdated":false}],"casks":[]}]],
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew search --cask docker",
      exitCode = 0,
      stdout = "docker-desktop\n",
      stderr = "",
      success = true,
    },
    {
      match = "/opt/homebrew/bin/brew info --json=v2 --cask docker-desktop",
      exitCode = 0,
      stdout = [[{"formulae":[],"casks":[{"token":"docker-desktop","full_token":"docker-desktop","desc":"App to build and share containerised applications and microservices","homepage":"https://www.docker.com/products/docker-desktop","tap":"homebrew/cask","installed":"4.38.0","version":"4.39.0","outdated":true,"artifacts":[{"binary":["docker",{"target":"/usr/local/bin/docker"}]}]}]}]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "searched" },
    resultCount = 3,
    resultName = "docker",
    resultVersion = "28.0.0",
  }
}
