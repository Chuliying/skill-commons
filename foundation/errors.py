"""Typed, closed error vocabulary for the Foundation (spec Errors/Contracts).

All failures are fail-closed and typed. Error codes and unresolvable reasons
are closed sets so callers can branch deterministically and tests can pin them.
"""

# Publish / registration / schema error codes.
SCHEMA_ERROR = "SCHEMA_ERROR"
STALE_HOME_REVISION = "STALE_HOME_REVISION"
PUBLICATION_CONFLICT = "PUBLICATION_CONFLICT"
HOME_ERROR = "HOME_ERROR"  # missing / unresolvable / split-brain (ERR-005)
ENGINE_ERROR = "ENGINE_ERROR"  # malformed-success / unexpected (reserved)

ERROR_CODES = (
    SCHEMA_ERROR,
    STALE_HOME_REVISION,
    PUBLICATION_CONFLICT,
    HOME_ERROR,
    ENGINE_ERROR,
)

# Resolve / change-fact unresolvable reasons (ERR-004). Closed set.
UNRESOLVABLE_REASONS = (
    "ref-unpublished",
    "object-missing",
    "digest-unverifiable",
    "repo-unregistered",
    "path-escape",
)


class FoundationError(Exception):
    """A typed, fail-closed Foundation failure.

    Carries a closed `code` (one of ERROR_CODES) plus a human `detail`.
    """

    def __init__(self, code, detail=""):
        if code not in ERROR_CODES:
            raise ValueError(f"unknown Foundation error code: {code!r}")
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


class Unresolvable(Exception):
    """A typed resolve failure carrying a closed reason + the offending ref."""

    def __init__(self, reason, artifact_ref=None):
        if reason not in UNRESOLVABLE_REASONS:
            raise ValueError(f"unknown unresolvable reason: {reason!r}")
        self.reason = reason
        self.artifact_ref = artifact_ref
        super().__init__(reason)

    def as_fact(self):
        """Closed typed fact for machine output (spec Contracts)."""
        return {"unresolvable": self.reason, "artifact_ref": self.artifact_ref}
