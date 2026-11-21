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

_WINDOWS_PROJECT = re.compile(
    r'(?m)^(?P<indent>\\s*)flutter::DartProject\\s+project\\s*\\(\\s*L"data"\\s*\\)\\s*;'
)
_LINUX_PROJECT = re.compile(
    r'(?m)^(?P<indent>\\s*)g_autoptr\\(FlDartProject\\)\\s+project\\s*=\\s*fl_dart_project_new\\(\\)\\s*;'
)


def disable_windows_impeller(source: str) -> tuple[str, int]:
    """Use the stable Skia renderer on Windows desktop for older GPU compatibility."""
    if "set_impeller_switch" in source:
        return source, 0
    return _WINDOWS_PROJECT.subn(
        lambda match: (
            match.group(0)
            + "\\n"
            + match.group("indent")
            + "project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);"
        ),
        source,
        count=1,
    )


def disable_linux_impeller(source: str) -> tuple[str, int]:
    """Use the stable Skia renderer on Linux desktop for older GPU compatibility."""
    if "fl_dart_project_set_enable_impeller" in source:
        return source, 0
    return _LINUX_PROJECT.subn(
        lambda match: (
            match.group(0)
            + "\\n"
            + match.group("indent")
            + "fl_dart_project_set_enable_impeller(project, FALSE);"
        ),
        source,
        count=1,
    )
