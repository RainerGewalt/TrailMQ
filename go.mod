// The TrailMQ launcher.
//
// Deliberately dependency-free: everything it needs is in the standard
// library. A distribution binary that evaluators download and run should not
// carry a dependency tree they have to trust, and a single static binary with
// no module graph is also the cheapest thing to cross-compile and to audit.
module github.com/RainerGewalt/TrailMQ

go 1.23
