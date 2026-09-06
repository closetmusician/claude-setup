// ABOUTME: Shim that re-exports the pre-bundled server-node.mjs.
// ABOUTME: The compiled dist/browse binary resolves ../src/server.ts at startup.
// ABOUTME: In a full gstack source tree this would be the real server. In our
// ABOUTME: decoupled dist-only install, this shim delegates to the bundle so
// ABOUTME: all 15+ skills that reference dist/browse directly keep working.

import '../dist/server-node.mjs';
