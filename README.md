# self-ai

This project uses [vast.ai](https://vast.ai/) to self-host things I'm interested in.

vast.ai has very low minimum deposit and you can rent machines with arbitrarily powerful GPUs for a short time. You get `root` on those machines and you can do whatever you want.

Usage:

```bash
# If you don't have nix, it installs a disposable nix-portable in `~/.nix-portable`
./nix develop

# https://cloud.vast.ai/manage-keys
vastai set api-key "$API_KEY"
```

# Launch whisper

```
./launch-whisper
# On another terminal
./produce-srt video.mp4
```

# Launch an LLM

```
./launch-llm gpt-oss
```
