# zmesh

zmesh is a distributed orchestration and replication engine for ScaleFS.

It provides:

- distributed filesystem orchestration
- ZFS-native replication with generic fallback
- virtual hierarchy (virtualpath)
- snapshot-based synchronization
- multi-node consistency coordination
- future support for object, block, and directory storage views

zmesh is designed to operate across:

- FreeBSD
- Linux
- Windows (experimental ZFS support)

---

# Architecture

zmesh separates storage into layers:

- ScaleFS body (physical storage unit)
- virtualpath (logical hierarchy)
- controller layer (replication, orchestration)
- transport layer (cluster communication)

Future extensions include:

- object storage interface
- block storage interface
- FUSE integration
- distributed replication engine

---

# License

Copyright 2026 Satoshi Takashima  
Copyright 2026 EixyScience, Inc.

Licensed under the Apache License, Version 2.0.

See LICENSE file for details.

---

# Status

This project is under active development.

Current features:

- ScaleFS initialization
- ZFS integration
- virtualpath hierarchy
- replication engine (in progress)
- CLI tools (zmesh, scalefs)

---

# Repository

https://github.com/EixyScience/zmesh

---

# Contributing

Contributions are welcome.

---

# Author

Satoshi Takashima  
EixyScience, Inc.