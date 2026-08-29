To release a new gem set:

1. Make sure CI is passing — the full matrix, every cell in `supported_versions.yml`.
   `rake hyperstack:matrix:check` must agree with `.gitlab-ci.yml`; it is a
   `publish` prerequisite, so a drifted table blocks the release anyway.
2. Bump the version to the next point release. It lives in 16 files: `HYPERSTACK_VERSION`,
   `ruby/version.rb`, and one `version.rb` per gem under `ruby/*/lib/**`. A global
   search-and-replace for the current version string catches all of them; verify with
   `grep -rn "<old version>" --include="*.rb" --include=HYPERSTACK_VERSION .` afterwards
   (only `ruby/version.rb`'s explanatory comment should still mention an older one).
3. Write the release's entry at the top of `/CHANGELOG.md`. It must cover **every**
   commit since the last bump commit — fixes, dependency changes and CI work alike,
   not just the headline. Individual MRs deliberately do not touch the changelog, so
   the bump commit is the only place these are recorded:
   `git log --no-merges --reverse <last bump commit>..HEAD`
4. Commit all the above. <- VERY IMPORTANT TO DO THIS BEFORE ADDING THE TAG
5. `git tag 1.0.alpha1.<new point release>`
6. `git push --tags origin edge` <- once build passes gems will be released!!!
7. Add a new release note (add release in GitLab): copy the CHANGELOG entry.

Notes on the version number
---------------------------

Up to and including `1.0.alpha1.8.34.18.61.1614.6`, the version encoded the one
configuration a build was tested against
(`<ruby>.<opal>.<rails>.<react major+minor>.<patch>`), because one build served
exactly one combination and each Rails version had its own branch line. That is no
longer true — a single gem set is tested across the whole matrix — so from
`1.0.alpha1.9` the version is a plain point release and `supported_versions.yml` is
the compatibility statement. Do not reintroduce the suffix.

Stale artifacts
---------------

`/current-status.md` and `/release-notes/` are upstream-era artifacts, last updated
in 2021, and are no longer part of this process. `/CHANGELOG.md` is the live record.
