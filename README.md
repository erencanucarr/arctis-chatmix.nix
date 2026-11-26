# arctis-chatmix.nix

[![check](https://github.com/erencanucarr/arctis-chatmix.nix/actions/workflows/check.yml/badge.svg)](https://github.com/erencanucarr/arctis-chatmix.nix/actions/workflows/check.yml)

A NixOS module that makes the ChatMix wheel on the **SteelSeries Arctis 7+** work on Linux, and sets up battery reading with [HeadsetControl](https://github.com/Sapd/HeadsetControl).

On Windows, SteelSeries GG splits audio into a game and a chat channel and the wheel balances between them. This module does the same with PipeWire:

- Two virtual outputs, **Arctis Game** and **Arctis Chat**, both playing into the headset.
- A small user service listens to the wheel's HID reports and sets the volume of each output's stream. No polling: it only reacts when the wheel moves.
- By default the chat output follows the game output's volume and mute, so your volume keys (which change the default output, the game output) control both. The wheel still sets the balance between them.
- The service starts when the dongle is plugged in (a udev rule starts it) or at login if it's already in, and exits when the dongle is removed. The outputs go with it and audio falls back to the remaining outputs.

The background and the details are in the write-up: [Making the Arctis 7+ ChatMix Wheel Work on Linux](https://erencan.me/thoughts/arctis-7-plus-chatmix-on-linux).

## Supported headsets

The Arctis 7+ family, which shares one protocol:

| Model | USB ID |
| --- | --- |
| Arctis 7+ | `1038:220e` |
| Arctis 7+ PS5 | `1038:2212` |
| Arctis 7+ Xbox | `1038:2216` |
| Arctis 7+ Destiny | `1038:2236` |

Only the Arctis 7+ (`1038:220e`) has been tested on real hardware. The others should work the same way; reports are welcome. Other ChatMix headsets (Arctis Nova, Arctis 9, ...) use different report formats and are not supported.

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

After rebuilding, log out and back in, or replug the dongle. Battery level is available with `headsetcontrol -b`.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `services.arctis-chatmix.enable` | `false` | Enable the service. |
| `services.arctis-chatmix.sink` | `null` | PipeWire node name of the headset output. Detected automatically from the USB IDs when `null`. |
| `services.arctis-chatmix.setDefault` | `true` | Make the game output the default while the headset is connected. |
| `services.arctis-chatmix.linkVolume` | `true` | Make the chat output follow the game output's volume and mute, so volume keys control both. The wheel still sets the balance. |
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

## Troubleshooting

Check that the service is running and read its log:

```sh
systemctl --user status arctis-chatmix
journalctl --user -u arctis-chatmix -b
```

If it isn't running with the dongle plugged in, start it by hand with `systemctl --user start arctis-chatmix`. It also restarts together with PipeWire, so restarting PipeWire restarts it.

Check the state file: `cat $XDG_RUNTIME_DIR/arctis-chatmix` should show two numbers that change when you turn the wheel. `off` means the service doesn't see the headset.

Check that the virtual outputs exist: `wpctl status` should list **Arctis Game** and **Arctis Chat** under Sinks, and `pw-dump | grep arctis_` should show the `arctis_game` and `arctis_chat` nodes.

If the log shows the headset can't be read, it's usually hidraw permissions. They come from headsetcontrol's udev rules. After the first install, log out and back in or replug the dongle so they apply.

If the headset isn't detected as an output, set `sink` to its node name (find it with `wpctl status` or `pw-dump`).

The service makes the game output the default output while the headset is connected. If you don't want it to take over your default output, set `setDefault = false`.

## Notes

- Screen recorders that capture the default output only hear the game output. Record from the headset's own output to get both.

## License

MIT
