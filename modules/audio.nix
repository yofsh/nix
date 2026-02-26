{ config, lib, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Sound
    pipewire
    pulseaudio
    wiremix
    pwvucontrol
    usbutils
  ];

  services.blueman.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
        KernelExperimental = "6fbaf188-05e0-496a-9885-d6ddfdb4e03e";
      };
    };
  };

  # Sound
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    raopOpenFirewall = true;
    extraConfig.pipewire."10-airplay" = {
      "context.modules" = [
        {
          name = "libpipewire-module-raop-discover";
          args = {
            "stream.rules" = [
              {
                matches = [ { "raop.ip" = "~.*"; } ];
                actions.create-stream = {
                  "stream.props" = {
                    "sess.latency.msec" = 247.44; # must be integer multiple of rtp.ptime (~7.98ms); 250 causes timestamp desync
                  };
                };
              }
            ];
          };
        }
      ];
    };
  };
  services.pipewire.wireplumber.configPackages = [
    (pkgs.writeTextDir
      "share/wireplumber/bluetooth.lua.d/51-bluez-config.lua" ''
        bluez_monitor.properties = {
        ["bluez5.enable-sbc-xq"] = true,
        ["bluez5.enable-msbc"] = true,
        ["bluez5.enable-hw-volume"] = true,
        ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
        }
      '')
  ];
}
