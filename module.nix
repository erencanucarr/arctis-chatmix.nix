self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.arctis-chatmix;
in
{
  options.services.arctis-chatmix = {
    enable = lib.mkEnableOption "the ChatMix wheel of the Arctis 7+ family as a game/chat mixer";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "arctis-chatmix.packages.\${system}.default";
      description = "The arctis-chatmix package to run.";
    };

    sink = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alsa_output.usb-SteelSeries_Arctis_7_-00.analog-stereo";
      description = "PipeWire node name of the headset output. Detected automatically by USB id when null.";
    };

    setDefault = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Make the game output the default output while the headset is connected.";
    };

    linkVolume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mirror the volume and mute state of the game output onto the chat output, so volume keys control both.";
    };

    labels = {
      game = lib.mkOption {
        type = lib.types.str;
        default = "Arctis Game";
        description = "Display name of the game output.";
      };
      chat = lib.mkOption {
        type = lib.types.str;
        default = "Arctis Chat";
        description = "Display name of the chat output.";
      };
    };

    headsetcontrol = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install headsetcontrol for reading the battery level.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ pkgs.headsetcontrol ];
    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1038", ATTRS{idProduct}=="220e|2212|2216|2236", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}+="arctis-chatmix.service"
    '';
    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.headsetcontrol pkgs.headsetcontrol;

    systemd.user.services.arctis-chatmix = {
      description = "ChatMix wheel of the Arctis 7+ family";
      wantedBy = [ "default.target" ];
      after = [
        "pipewire.service"
        "pipewire-pulse.service"
        "wireplumber.service"
      ];
      partOf = [ "pipewire.service" ];
      startLimitIntervalSec = 0;
      environment = {
        ARCTIS_SET_DEFAULT = if cfg.setDefault then "1" else "0";
        ARCTIS_LINK_VOLUME = if cfg.linkVolume then "1" else "0";
        ARCTIS_GAME_LABEL = cfg.labels.game;
        ARCTIS_CHAT_LABEL = cfg.labels.chat;
      }
      // lib.optionalAttrs (cfg.sink != null) { ARCTIS_SINK = cfg.sink; };
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
