return {
  name = "real search smoke",
  request = {
    action = "search",
    system = "homebrew",
    prompt = "wget",
  },
  expect = {
    success = true,
  }
}
