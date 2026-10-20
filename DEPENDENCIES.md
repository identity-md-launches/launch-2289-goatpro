# Vendored dependencies

Dependencies are copied as ordinary source files, with no submodules or runtime
downloads. Upstream files are unmodified.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | [v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | ERC20 and its four transitive source dependencies | MIT |
| Forge Standard Library | [v1.9.6](https://github.com/foundry-rs/forge-std/tree/v1.9.6) | `src/` (test utilities only) | MIT / Apache-2.0 |

The source archives were retrieved from the upstream GitHub tag archives:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  — SHA-256 `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.6`
  — SHA-256 `53d2b498183cb7dc62cf726cc6c1a222ad728b0d87976a877ca1f3ed3707b1c6`.

License texts are at `lib/openzeppelin-contracts/LICENSE`,
`lib/forge-std/LICENSE-MIT`, and `lib/forge-std/LICENSE-APACHE`.
`remappings.txt` resolves imports locally.
