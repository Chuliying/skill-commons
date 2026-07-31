"""Product Scope: active product scope as activated, precommitted deltas.

Built on Track 3 Foundation. Foundation owns artifact identity, publication and
resolvability; this package owns Product revisions and the activation protocol.
"""

from . import contracts, errors  # noqa: F401
from .activation import NeedsRebase, activate, head, lineage  # noqa: F401
