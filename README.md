# One-time secret backend and web client

Inspired by https://github.com/sniptt-official/ots but is not tied to AWS.
Deployable to any place that can run a container. See instructions below for setting up on fly.io.

Future support for ChaPoly cipher, but would be encrypted and decrypted by backend.

## Accompanying cli

Cli that uses supports AES GCM and ChaPoly cipher: https://github.com/ringvold/neots

## Ots cli compatibility

Compatible with the [ots cli](https://github.com/sniptt-official/ots): `brew install ots`. 

To use the cli with your own instance of this project set `apiKey` in `~/.ots.yaml`:

```yaml
apiKey: https://my-ots.fly.dev/view
```
or test it out locally

```yaml
apiKey: https://localhost:400/view
```

## Deploy to fly.io

First, install the `fly` cli:

On MacOS:

```shell
brew install flyctl
```

On Linux:

```shell
curl -L https://fly.io/install.sh | sh
```

On Windows:

```shell
iwr https://fly.io/install.ps1 -useb | iex
```

Next, create a new app with `fly` on the command line:


```shell
fly create my-ots
```

Finally, update the first line of the `fly.toml` to use your new app name: `app = "my-ots"`

Now you can `fly deploy` and access your application at `my-ots.fly.dev`.

## Singe file Phoenix project

Single file Phoenix based on https://github.com/chrismccord/single_file_phoenix_fly
