"""Pure, tested helpers for native desktop window-title branding."""
from __future__ import annotations

import re

_LINUX_TITLE = re.compile(
    r'(gtk_window_set_title\(window,\s*")[^"]*("\s*\);)'
)
_WINDOWS_TITLE = re.compile(
    r'(window\.Create(?:AndShow)?\s*\(\s*)(L?")([^"]*)(")'
)


def replace_linux_window_title(source: str) -> tuple[str, int]:
    """Replace only the GTK window caption, retaining valid C++ string quotes."""
    return _LINUX_TITLE.subn(
        lambda match: match.group(1) + "DepthVibe" + match.group(2),
        source,
        count=1,
    )


def replace_windows_window_title(source: str) -> tuple[str, int]:
    """Replace Flutter runner title literals for Create/CreateAndShow, wide or narrow."""
    return _WINDOWS_TITLE.subn(
        lambda match: (
            match.group(1) + match.group(2) + "DepthVibe" + match.group(4)
        ),
        source,
        count=1,
    )
