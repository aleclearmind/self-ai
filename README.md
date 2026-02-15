# self-ai

This project uses [vast.ai](https://vast.ai/) to self-host things I'm interested in.

Usage:

```bash
# If you don't have nix, it installs a disposable nix-portable in `~/.nix-portable`
./nix develop

# https://cloud.vast.ai/manage-keys
vastai set api-key "$API_KEY"

./launch-llm gpt-oss
```
