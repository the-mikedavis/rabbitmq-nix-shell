# rabbitmq development Nix flake

This is a Nix flake that creates an ephemeral shell with all dependencies
needed to develop `rabbitmq/rabbitmq-server` via `bazel` or `make`.

> Note: this is not official or supported by the RabbitMQ team.

Usage:

```
(host machine)$ nix develop github:the-mikedavis/rabbitmq-nix-shell
(nix-shell)$ cd path/to/rabbitmq-server
(nix-shell)$ bazel build //...
(nix-shell)$ bazel test //...
```

The resulting shell has

* bazel
* (GNU) make
* `rabbitmq/rabbitmq-perf-test` built as a GraalVM native image
* necessary Java and C(++) dependencies for bazel
* python 3
* `mandoc`
* `open`, an alias to `xdg-open`
* `linkbazelrc`, a shell script that creates a symblink to a generated `user.bazelrc`
    * this `user.bazelrc` sets up the correct Erlang, Elixir, and Java variables
    * use this in each project repository built by bazel (`rabbitmq-server`, `ra`, `osiris`, etc.)
* `perf` for profiling OTP
* `mkflamegraph` for generating flamegraphs from `perf` data

### TODO

Remote builds are broken. `bazel` from nixpkgs replaces `/bin/bash` references
with the path to bash in the Nix store. Remote builders then try to use that
bash command which fails. Some investigation into the bazel codebase is needed
to figure out if we can replace usages of `/bin/bash` for local builds but not
remote builds.
