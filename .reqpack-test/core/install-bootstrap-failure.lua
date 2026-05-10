return {
  name = "homebrew install fails when bootstrap fails",
  request = {
    action = "install",
    system = "homebrew",
    packages = {
      { name = "wget", version = "1.24.5" }
    },
  },
  fakeExec = {
    {
      match = "command -v brew 2>/dev/null || { [ -x /opt/homebrew/bin/brew ] && printf '%s\\n' /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && printf '%s\\n' /usr/local/bin/brew; } || { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && printf '%s\\n' /home/linuxbrew/.linuxbrew/bin/brew; }",
      exitCode = 1,
      stdout = "",
      stderr = "",
      success = false,
    },
    {
      match = "/opt/homebrew/bin/brew --version",
      exitCode = 127,
      stdout = "",
      stderr = "not found",
      success = false,
    },
    {
      match = "/usr/local/bin/brew --version",
      exitCode = 127,
      stdout = "",
      stderr = "not found",
      success = false,
    },
    {
      match = "/home/linuxbrew/.linuxbrew/bin/brew --version",
      exitCode = 127,
      stdout = "",
      stderr = "not found",
      success = false,
    },
    {
      match = "brew --version",
      exitCode = 127,
      stdout = "",
      stderr = "not found",
      success = false,
    },
    {
      match = "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      exitCode = 1,
      stdout = "",
      stderr = "homebrew bootstrap failed\n",
      success = false,
    },
  },
  expect = {
    success = false,
    commands = {
      "command -v brew 2>/dev/null || { [ -x /opt/homebrew/bin/brew ] && printf '%s\\n' /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && printf '%s\\n' /usr/local/bin/brew; } || { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && printf '%s\\n' /home/linuxbrew/.linuxbrew/bin/brew; }",
      "/opt/homebrew/bin/brew --version",
      "/usr/local/bin/brew --version",
      "/home/linuxbrew/.linuxbrew/bin/brew --version",
      "brew --version",
      "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
    },
    events = { "failed" },
    eventPayloads = {
      failed = "homebrew bootstrap failed",
    },
  }
}
