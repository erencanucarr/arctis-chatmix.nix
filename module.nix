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
    enable = lib.mkEnableOption "the Arctis 7+ ChatMix wheel as a game/chat mixer";

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
      description = "PipeWire node name of the headset output. Detected automatically when null.";
    };

    setDefault = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Make the game output the default output while the headset is connected.";
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
    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.headsetcontrol pkgs.headsetcontrol;

    systemd.user.services.arctis-chatmix = {
      description = "Arctis 7+ ChatMix wheel";
      wantedBy = [ "default.target" ];
      after = [
        "pipewire.service"
        "wireplumber.service"
      ];
      environment = {
        ARCTIS_SET_DEFAULT = if cfg.setDefault then "1" else "0";
        ARCTIS_GAME_LABEL = cfg.labels.game;
        ARCTIS_CHAT_LABEL = cfg.labels.chat;
      }
      // lib.optionalAttrs (cfg.sink != null) { ARCTIS_SINK = cfg.sink; };
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
