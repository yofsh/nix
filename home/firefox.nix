{ pkgs, ... }:
let username = "fobos";
in {
  programs.firefox = {
    enable = true;
    package = pkgs.firefox;
    nativeMessagingHosts = [ pkgs.tridactyl-native ];
    profiles.${username} = {
      name = "${username}";
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.aboutConfig.showWarning" = false;
      };
      isDefault = true;
      search = {
        force = true;
        engines = {
          "Nix Packages" = {
            urls = [{
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "type";
                  value = "packages";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }];
            icon =
              "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };
          "NixOS Wiki" = {
            urls = [{
              template = "https://nixos.wiki/index.php?search={searchTerms}";
            }];
            icon = "https://nixos.wiki/favicon.png";
            definedAliases = [ "@nw" ];
          };
          "google".metaData.alias =
            "@g"; # builtin engines only support specifying one additional alias
        };
        default = "google";
      };
      userChrome = ''
        @namespace "http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul";

        /* MacOs Related */
        * {
          box-shadow: none !important;
          filter: none !important;
        }

        #TabsToolbar-customization-target {
          position: relative;
          height: 24px;
        }

        #tabbrowser-tabs {
          /* height: 30px !important; */
          /* top: 9px; */
          position: relative;
          height: 24px;
          max-height: 24px;
          min-height: 24px;
        }
        #tabbrowser-arrowscrollbox {
          height: 24px;
        }

        .tab-content {
          height: 24px;
        }
        #new-tab-button,
        #alltabs-button,
        #scrollbutton-down {
          height: 24px;
          /* top: 2px; */
          position: relative;
        }

        /* Hide close button on tabs */
        #tabbrowser-tabs .tabbrowser-tab .tab-close-button {
          display: none !important;
        }
        .notification-anchor-icon {
          padding: 2px !important;
        }
        #TabsToolbar,
        .tabbrowser-tab {
          max-height: 24px !important;
          font-size: 14px;
          font-weight: 600;
          letter-spacing: -0.7px;
        }
        #titlebar {
          --tab-min-height: 24px !important;
          --proton-tab-block-margin: 0px !important;
        }
        .tab-background {
          margin-block: 0px !important;
          --tab-min-height: 24px !important;
        }
        toolbarbutton {
          --toolbarbutton-inner-padding: 1px 1px !important;
        }

        /* Change color of normal tabs */
        tab:not([selected="true"]) {
          background-color: #000000 !important;
          color: #666666 !important;
          border: none;
        }
        .tabbrowser-tab:not([pinned]) {
          /*   max-width: 150px !important;  */
        }

        /* Firefox account button */
        #fxa-toolbar-menu-button {
          /*   display: none; */
        }

        /* Empty space before and after the url bar */
        #customizableui-special-spring1,
        #customizableui-special-spring2 {
          display: none;
        }
        /* style navbar */
        #nav-bar,
        #navigator-toolbox {
          border-width: 0 !important;
        }

        /* style urlbar */
        #urlbar-container {
          --urlbar-container-height: 24px !important;
          --urlbar-min-height: 24px !important;
          margin-left: 0 !important;
          margin-right: 0 !important;
          padding-top: 0 !important;
          padding-bottom: 0 !important;
          font-size: 14px;
        }
        #urlbar {
          --urlbar-height: 24px !important;
          --urlbar-min-height: 24px !important;
          --urlbar-toolbar-height: 24px !important;
          min-height: 24px !important;
        }
        .urlbar-page-action {
          padding: 0 !important;
          width: 24px !important;
          height: 16px !important;
        }
        #urlbar-zoom-button {
          font-size: 12px !important;
          padding: 0px 7px !important;
          margin-block: 1px !important;
        }
        .tab-secondary-label {
          position: absolute;
          padding: 2px 7px;
          background: rgb(27, 110, 4);
          top: 5px;
          left: 5px;
          width: 24px;
          overflow: hidden;
          font-size: 9px;
          letter-spacing: 10px;
          border-radius: 5px;
          color: white;
        }
        .tabbrowser-tab[usercontextid]
          > .tab-stack
          > .tab-background
          > .tab-context-line {
          height: 100% !important;
          margin: 0 !important;
          opacity: 0.4;
        }
      '';
    };
  };
}
