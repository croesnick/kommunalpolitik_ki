---
sidecar: minor
---

# `ping` answers optional extras from the sidecar (#515)

Sidecars can now implement the optional callback `ping_extra/1`; its map
is merged into the answer of the reserved `ping` operation, over `version`
and `ops`. Without the callback the answer is unchanged, and a malformed
extra is dropped — `ping` is the doctor's channel and must answer. The
RIS connector uses this to report its start probe of the upstream
(`"upstream"`: `"ok"` or a closed error code) so `komki doctor` recognizes
an unknown counterpart right at startup instead of at the first call.
