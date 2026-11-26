{
  writeShellApplication,
  coreutils,
  gnugrep,
  jq,
  pipewire,
  pulseaudio,
  wireplumber,
}:
writeShellApplication {
  name = "arctis-chatmix";
  runtimeInputs = [
    coreutils
    gnugrep
    jq
    pipewire
    pulseaudio
    wireplumber
  ];
  text = builtins.readFile ./arctis-chatmix.sh;
  meta = {
    description = "Turns the ChatMix wheel of the Arctis 7+ family into a game/chat mixer on PipeWire";
    mainProgram = "arctis-chatmix";
  };
}
