"""Cross-repo orchestration, consumer boundary.

V1 scope here is the Foundation/Product-Scope consumer integration (program T04/T06):
accept an InitiativeScope, bind its requirements to Foundation-resolvable artifacts,
and produce a deterministic ready order. The execution engine described by the PRD
(dispatch, attempts, evidence, recovery) is a later phase and is not in this package.
"""

from . import (  # noqa: F401
    aggregate,
    consumer,
    errors,
    execution,
    graph,
    identity,
    invalidation,
    projection,
)
from .consumer import bind_initiative_scope  # noqa: F401
