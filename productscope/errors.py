"""Typed errors for Product Scope. Every failure is fail-closed by contract."""

SCHEMA_ERROR = "SCHEMA_ERROR"
UNPUBLISHED_CANDIDATE = "UNPUBLISHED_CANDIDATE"
NEEDS_REBASE = "NEEDS_REBASE"
ADVISORY_NOT_ACCEPTED = "ADVISORY_NOT_ACCEPTED"
IDENTITY_MISMATCH = "IDENTITY_MISMATCH"
DUPLICATE_REQUIREMENT_ID = "DUPLICATE_REQUIREMENT_ID"
ACTIVATION_GIT_ERROR = "ACTIVATION_GIT_ERROR"


class ProductScopeError(Exception):
    """Carries a stable code so a caller can branch without parsing prose."""

    def __init__(self, code, message):
        super().__init__("%s: %s" % (code, message))
        self.code = code
        self.message = message


class NeedsRebase(ProductScopeError):
    """The parent revision moved; the ref was NOT advanced.

    Precise on purpose: a blob, tree and commit have already been written to the object
    database by the time the ref CAS fails. They are unreachable garbage that `git gc`
    collects, and no Product Scope Revision exists. Saying "nothing was written" would
    be false and would mislead anyone debugging object counts.
    """

    def __init__(self, message="parent scope revision is stale"):
        super().__init__(NEEDS_REBASE, message)
