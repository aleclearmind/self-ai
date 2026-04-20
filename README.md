# self-ai

This project uses [vast.ai](https://vast.ai/) to self-host things I'm interested in.

vast.ai has very low minimum deposit and you can rent machines with arbitrarily powerful GPUs for a short time. You get `root` on those machines and you can do whatever you want.

> [!WARNING]
> This will run on vast.ai a nix-based container image I built.
> This image will fetch additional software (depending on the task) that's cached on my personal nix cache (clearmind.me/attic/).
> This will save you a lot of time, since building from source it's quite demanding.
> This said, the nix flake is reproducible, so you can re-build it, if you want.

> [!CAUTION]
> Currently, these scripts do not turn off the instances, you have to do it manually from the vast.ai console.

## Set up

Create an account on vast.ai and then set up a key on the CLI:

```bash
pip install vastai
# https://cloud.vast.ai/manage-keys
vastai set api-key "$API_KEY"
```

Then, choose your SSH key and provide your hugging face token (required for `./launch-ghibli`).
Write in `configuration`:

```
SSH_KEY=/home/myuser/.ssh/id_ed25519
HF_TOKEN=hf_...
```

## Launch whisper

```
./launch-whisper
# On another terminal
./produce-srt video.mp4
```

## Launch easycontrol for Ghibli

```
./launch-ghibli
```

## Launch an LLM

```
./launch-llm gpt-oss
# or ./launch-llm minimax-2.7
```

### Configure OpenCode

Put the following in `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "cefprovider": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "local gpt-oss",
      "options": {
        "baseURL": "http://localhost:8000/v1"
      },
      "models": {
        "openai/gpt-oss-120b": {
          "name": "gpt-oss",
          "options": {
            "max_tokens": 20000
          }
        },
        "MiniMaxAI/MiniMax-M2.7": {
          "name": "MiniMax-M2.7",
          "options": {
            "max_tokens": 20000
          }
        }
      }
    }
  }
}
```

### Configure Open WebUI

1. Log in as an admin user
2. Go to [`/admin/settings/connections`](http://localhost:8080/admin/settings/connections)
3. Click on the gear on the right of "Manage OpenAI API Connections"
4. Set as URL `http://127.0.0.1:8000/v1` (note not `https://`).
5. Save
6. Go under "Models" ([`/admin/settings/models`](http://localhost:8080/admin/settings/models)), you should see your model.
7. Click on "New chat"
