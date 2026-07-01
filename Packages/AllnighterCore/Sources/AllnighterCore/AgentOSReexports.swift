import Foundation
// AgentOS runtime seam. Allnighter consumes shared runtime primitives from
// AgentOSCLI (roadmap P1). Re-exported so existing call sites resolve moved types
// (e.g. `JSONValue`) unqualified, without churn. As more primitives migrate, they
// travel through this same seam.
@_exported import AgentOSCLI
