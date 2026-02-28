{ pkgs, ... }:
let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.dbus-python ps.pygobject3 ]);
  fprint-verify = pkgs.writeScript "fprint-verify" ''
    #!${pythonEnv}/bin/python3
    import dbus
    import dbus.mainloop.glib
    import os
    import sys
    from gi.repository import GLib

    PREFERRED_DEVICE = "Digital Persona"
    TIMEOUT = 30

    def main():
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()
        manager = bus.get_object("net.reactivated.Fprint", "/net/reactivated/Fprint/Manager")
        manager_iface = dbus.Interface(manager, "net.reactivated.Fprint.Manager")
        devices = manager_iface.GetDevices()
        if not devices:
            sys.exit(1)

        user = os.environ.get("PAM_USER", "")
        if not user:
            sys.exit(1)

        # Find preferred device (Digital Persona USB), fall back to any other
        chosen = None
        fallback = None
        for dev_path in devices:
            dev = bus.get_object("net.reactivated.Fprint", dev_path)
            props = dbus.Interface(dev, "org.freedesktop.DBus.Properties")
            name = str(props.Get("net.reactivated.Fprint.Device", "name"))
            dev_iface = dbus.Interface(dev, "net.reactivated.Fprint.Device")
            try:
                fingers = dev_iface.ListEnrolledFingers(user)
            except dbus.DBusException:
                fingers = []
            if not fingers:
                continue
            if PREFERRED_DEVICE in name:
                chosen = (dev, dev_iface, name)
            elif fallback is None:
                fallback = (dev, dev_iface, name)

        if chosen is None:
            chosen = fallback
        if chosen is None:
            sys.exit(1)

        dev, dev_iface, name = chosen
        print(f"Place your finger on {name}")
        sys.stdout.flush()

        dev_iface.Claim(user)
        loop = GLib.MainLoop()
        result = [False]
        attempts = [0]
        max_attempts = 3

        def retry_verify():
            try:
                dev_iface.VerifyStart("any")
            except dbus.DBusException:
                pass
            return False

        def on_verify_status(status, done):
            if status == "verify-match":
                result[0] = True
                loop.quit()
            elif status in ("verify-no-match", "verify-unknown-error"):
                attempts[0] += 1
                if attempts[0] >= max_attempts:
                    loop.quit()
                else:
                    try:
                        dev_iface.VerifyStop()
                    except Exception:
                        pass
                    print(f"No match, try again ({max_attempts - attempts[0]} left)...")
                    sys.stdout.flush()
                    GLib.timeout_add(300, retry_verify)
            elif status == "verify-swipe-too-short":
                print("Too short, try again...")
                sys.stdout.flush()
            elif status == "verify-finger-not-centered":
                print("Not centered, try again...")
                sys.stdout.flush()

        dev.connect_to_signal(
            "VerifyStatus", on_verify_status,
            dbus_interface="net.reactivated.Fprint.Device",
        )
        GLib.timeout_add_seconds(TIMEOUT, lambda: (loop.quit(), False)[1])
        dev_iface.VerifyStart("any")

        try:
            loop.run()
        except Exception:
            pass
        finally:
            try:
                dev_iface.VerifyStop()
            except Exception:
                pass
            try:
                dev_iface.Release()
            except Exception:
                pass

        sys.exit(0 if result[0] else 1)

    try:
        main()
    except Exception:
        sys.exit(1)
  '';
in
{
  services.fprintd.enable = true;

  # Disable default pam_fprintd (always uses built-in reader) and use
  # custom script that prefers USB reader (Digital Persona), falling back to built-in (Synaptics)
  security.pam.services.sudo = {
    fprintAuth = false;
    rules.auth.fprint-prefer-usb = {
      enable = true;
      order = 11400;
      control = "sufficient";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = [ "stdout" "quiet" "${fprint-verify}" ];
    };
  };
  security.pam.services.greetd = {
    fprintAuth = false;
    rules.auth.fprint-prefer-usb = {
      enable = true;
      order = 11400;
      control = "sufficient";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = [ "stdout" "quiet" "${fprint-verify}" ];
    };
  };
  # hyprlock uses its own D-Bus fingerprint integration (enable_fingerprint = true in hyprlock.conf)
}
