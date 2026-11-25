# arctis-chatmix.nix

A NixOS module that makes the ChatMix wheel on the **SteelSeries Arctis 7+** work on Linux, and sets up battery reading with [HeadsetControl](https://github.com/Sapd/HeadsetControl).

On Windows, SteelSeries GG splits audio into a game and a chat channel and the wheel balances between them. This module does the same with PipeWire:

- Two virtual outputs, **Arctis Game** and **Arctis Chat**, both playing into the headset.
- A small user service listens to the wheel's HID reports and sets the volume of each output's stream. No polling: it only reacts when the wheel moves.
- The outputs exist only while the dongle is plugged in. When it's removed, they're torn down and audio falls back to the remaining outputs.

The background and the details are in the write-up: [Making the Arctis 7+ ChatMix Wheel Work on Linux](https://erencan.me/thoughts/arctis-7-plus-chatmix-on-linux).

## Usage

Add the flake as an input and import the module:

```nix
{
  inputs.arctis-chatmix.url = "github:erencanucarr/arctis-chatmix.nix";

  outputs = { nixpkgs, arctis-chatmix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        arctis-chatmix.nixosModules.default
        { services.arctis-chatmix.enable = true; }
      ];
    };
  };
}
```

After rebuilding, log out and back in (or run `systemctl --user start arctis-chatmix`). Battery level is available with `headsetcontrol -b`.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `services.arctis-chatmix.enable` | `false` | Enable the service. |
| `services.arctis-chatmix.sink` | `null` | PipeWire node name of the headset output. Detected automatically when `null`. |
| `services.arctis-chatmix.setDefault` | `true` | Make the game output the default while the headset is connected. |
| `services.arctis-chatmix.labels.game` | `"Arctis Game"` | Display name of the game output. |
| `services.arctis-chatmix.labels.chat` | `"Arctis Chat"` | Display name of the chat output. |
| `services.arctis-chatmix.headsetcontrol` | `true` | Install `headsetcontrol` for battery reading. Its udev rules are always installed, since the service needs them to read the wheel. |

## Sending an app to the chat output

Everything goes to the game output by default. Apps that use the PulseAudio API (Discord and most Electron apps) follow the `PULSE_SINK` environment variable:

```sh
PULSE_SINK=arctis_chat discord
```

To make it permanent, wrap the package:

```nix
pkgs.symlinkJoin {
  name = "discord";
  paths = [ pkgs.discord ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = "wrapProgram $out/bin/discord --set PULSE_SINK arctis_chat";
}
```

You can also move a running stream to **Arctis Chat** in `pavucontrol`.

## State file

The current mix is written to `$XDG_RUNTIME_DIR/arctis-chatmix` as `game chat` (for example `100 64`), or `off` when the headset is disconnected. Status bars can read it.

## Notes

- Only the Arctis 7+ (USB ID `1038:220e`) is supported. Other ChatMix headsets use different report formats.
- Screen recorders that capture the default output only hear the game output. Record from the headset's own output to get both.

## License

MIT
