"""Terminal-table formatting shared by bin/ python scripts (wifi, router-clients).

Import via the lib/py bootstrap:

    sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib", "py"))
    from termui import C, dw, pad, signal_bar
"""

import re
import unicodedata


class C:
    """ANSI color codes."""
    RST = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    GRAY = "\033[90m"
    BG_GRAY = "\033[48;5;236m"


_ANSI_RE = re.compile(r"\033\[[^m]*m")


def dw(s: str) -> int:
    """Display width: strip ANSI, count wide chars (emoji, CJK) as 2."""
    stripped = _ANSI_RE.sub("", s)
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in stripped)


def pad(s: str, width: int) -> str:
    """Pad with spaces to the target display width (ANSI-aware)."""
    return s + " " * max(0, width - dw(s))


def signal_bar(dbm: float) -> str:
    """Colored 4-block Wi-Fi signal bar with emoji and dBm label."""
    if dbm >= -50:
        bars, color, emoji = "████", C.GREEN, "🟢"
    elif dbm >= -60:
        bars, color, emoji = "███░", C.GREEN, "🟢"
    elif dbm >= -70:
        bars, color, emoji = "██░░", C.YELLOW, "🟡"
    elif dbm >= -80:
        bars, color, emoji = "█░░░", C.RED, "🟠"
    else:
        bars, color, emoji = "░░░░", C.RED, "🔴"
    return f"{emoji} {color}{bars}{C.RST} {C.DIM}{dbm:.0f}dBm{C.RST}"
