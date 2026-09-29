# Publishing

`service_mesh` is published to [rubygems.org](https://rubygems.org/gems/service_mesh) by hand
from a local checkout. The account that pushes is an owner of the gem, and
rubygems.org asks for its MFA code on every push because the gemspec sets
`rubygems_mfa_required`.

A gem that depends on `service_mesh` can only be installed once the `service_mesh` version it requires is on rubygems.org, so a new `service_mesh` version is published before the gems that need it.

## One-time setup

```sh
gem signin
```

This stores an API key in `~/.gem/credentials`.

## Releasing a version

1. Run `just bump patch`, `just bump minor`, or `just bump major` to set the new
   version in `lib/service_mesh/version.rb` and commit that file, then push `master`.
2. Wait for CI on `master` to pass.
3. Run the release from that commit:

   ```sh
   just release
   ```

   `just release` runs three recipes in order. `just tag` tags the commit
   `vX.Y.Z` and pushes the tag, and refuses when the working tree has
   changes. `just build` writes `pkg/service_mesh-X.Y.Z.gem`. `just publish` pushes
   that file and prompts for the MFA code. When the push fails after the tag
   exists, `just publish` alone retries it.

A pushed version is permanent. It can be yanked with `gem yank service_mesh -v X.Y.Z`,
but that version number can never be pushed again.

## Adding an owner

```sh
gem owner service_mesh --add someone@example.com
```
