"""Typed errors for the orchestration consumer boundary.

Every one of these is fail-closed: orchestration refuses work it cannot verify rather
than proceeding on a partial or unverified scope, because a partially bound graph
would let a run report progress against requirements it never resolved.
"""

UNBINDABLE_REQUIREMENT = "UNBINDABLE_REQUIREMENT"
UNKNOWN_TOPOLOGY_ENDPOINT = "UNKNOWN_TOPOLOGY_ENDPOINT"
TOPOLOGY_CYCLE = "TOPOLOGY_CYCLE"

# Slice A: identity, bootstrap and the Work Graph.
UNSUPPORTED_PROFILE = "UNSUPPORTED_PROFILE"
DUPLICATE_REPO_ID = "DUPLICATE_REPO_ID"
OWNERSHIP_CONFLICT = "OWNERSHIP_CONFLICT"
UNKNOWN_GRAPH_KIND = "UNKNOWN_GRAPH_KIND"
MIXED_GENERATION = "MIXED_GENERATION"
MISSING_BINDING = "MISSING_BINDING"
INVALID_BINDING = "INVALID_BINDING"
UNSUPPORTED_PARTICIPANT_COUNT = "UNSUPPORTED_PARTICIPANT_COUNT"

# Slice B: projection and repo-local apply.
CAS_CONFLICT = "CAS_CONFLICT"

# Slice C: execution, locks and resume.
FOREIGN_LOCK = "FOREIGN_LOCK"
UNKNOWN_EVIDENCE_STATE = "UNKNOWN_EVIDENCE_STATE"
GRAPH_NOT_DISPATCHABLE = "GRAPH_NOT_DISPATCHABLE"
INVALID_RETRY_POLICY = "INVALID_RETRY_POLICY"
ATTEMPT_IDENTITY_REQUIRED = "ATTEMPT_IDENTITY_REQUIRED"


class OrchestrationError(Exception):
    def __init__(self, code, message):
        super().__init__("%s: %s" % (code, message))
        self.code = code
        self.message = message
