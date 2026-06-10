"""MAC-vendor (OUI) lookup shared by bin/ python scripts (wifi, router-clients).

The database lives next to this module at lib/oui.db (tab-separated
"<6-hex-prefix>\t<vendor>" lines).
"""

import os

_DB_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "oui.db")


def load_oui_db() -> dict[str, str]:
    """Load the OUI database; empty dict when the file is missing."""
    oui: dict[str, str] = {}
    if not os.path.exists(_DB_PATH):
        return oui
    with open(_DB_PATH) as f:
        for line in f:
            parts = line.strip().split("\t", 1)
            if len(parts) == 2:
                oui[parts[0]] = parts[1]
    return oui


def oui_lookup(mac: str, oui_db: dict[str, str]) -> str:
    """Vendor for a MAC/BSSID. For randomized (locally administered) MACs, retry
    with the locally-administered bit cleared; empty string when unknown."""
    prefix = mac.replace(":", "")[:6].lower()
    if prefix in oui_db:
        return oui_db[prefix]
    first_byte = int(prefix[:2], 16)
    if first_byte & 0x02:
        global_byte = first_byte & ~0x02
        global_prefix = f"{global_byte:02x}{prefix[2:]}"
        if global_prefix in oui_db:
            return oui_db[global_prefix]
    return ""
