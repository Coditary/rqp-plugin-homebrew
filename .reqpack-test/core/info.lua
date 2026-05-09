return {
  name = "homebrew info prefers formula",
  request = {
    action = "info",
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
      match = "/opt/homebrew/bin/brew info --json=v2 docker",
      exitCode = 0,
      stdout = [[{"formulae":[{"name":"docker","full_name":"docker","desc":"Pack, ship and run any application as a lightweight container","homepage":"https://www.docker.com/","tap":"homebrew/core","license":"Apache-2.0","dependencies":["docker-completion"],"binaries":["docker"],"installed":[{"version":"28.0.0"}],"versions":{"stable":"28.1.0"},"outdated":true}],"casks":[{"token":"docker","full_token":"docker","desc":"App to build and share containerised applications","homepage":"https://www.docker.com/products/docker-desktop","tap":"homebrew/cask","installed":"4.38.0","version":"4.39.0","outdated":true,"artifacts":[{"binary":["docker",{"target":"/usr/local/bin/docker"}]}]}]}]],
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "informed" },
    eventPayloads = {
      informed = "{binaries=<lua-value>, dependencies=<lua-value>, description=Pack, ship and run any application as a lightweight container, extraFields=<lua-value>, homepage=https://www.docker.com/, installed=true, latestVersion=28.1.0, license=Apache-2.0, name=docker, packageId=homebrew/formula/docker, packageType=formula, repository=homebrew/core, status=outdated, summary=Pack, ship and run any application as a lightweight container, type=package, version=28.0.0}",
    },
    resultCount = 1,
    resultName = "docker",
    resultVersion = "28.0.0",
  }
}
