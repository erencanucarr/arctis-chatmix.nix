{
  writeShellApplication,
  coreutils,
  gnugrep,
  jq,
  pipewire,
  wireplumber,
}:
writeShellApplication {
  name = "arctis-chatmix";
  runtimeInputs = [
    coreutils
    gnugrep
    jq
    pipewire
    wireplumber
  ];
  text = builtins.readFile ./arctis-chatmix.sh;
  meta = {
    description = "Turns the Arctis 7+ ChatMix wheel into a game/chat mixer on PipeWire";
    mainProgram = "arctis-chatmix";
  };
}
