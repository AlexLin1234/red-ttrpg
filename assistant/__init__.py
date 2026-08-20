"""Redline's local rulebook reference assistant.

The helper owns everything the Godot console must not: PDF extraction, the
local search index, the operating-system credential vault, and the one outbound
request to Anthropic. Godot owns every pixel of UI and talks to this package
over an authenticated loopback socket.

No sourcebook content ships with Redline. A Game Master imports the PDFs they
own; the files, the extracted text and the index stay inside the private
application-data directory described in :mod:`assistant.paths`.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
