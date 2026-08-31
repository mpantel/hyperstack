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
6. `git push --tags origin edge`. This starts a tag pipeline. It does **not**
   publish anything — see below.
7. When that pipeline is green, run the eleven `*-deploy` jobs. **They are
   `when: manual`**, so nothing is published until a human starts them. Each runs
   `rake hyperstack:gem:publish COMPONENT=<gem>`, which POSTs the built gem to the
   GitLab RubyGems registry and then polls the packages API until the version
   reports status `default` — a 201 only means the file was stored (#49). They
   share `resource_group: production`, so they serialise.

   The deploy jobs exist **only on a release pipeline**: a tag pipeline, or one
   started manually with the variable `RELEASE=1`. Ordinary pushes carry no deploy
   jobs at all, which is what lets them report a plain green (#117). If you are
   looking for the deploy jobs and they are not there, you are on an ordinary
   pipeline — start a new one with `RELEASE=1`, which is also how you retry a
   single gem without cutting another tag.
8. **The pipeline now tells you.** The deploy jobs are blocking, so a release
   pipeline reads `blocked` until they have run, and goes **red** if any gem
   fails to publish. `rake hyperstack:gem:publish` aborts when the upload is
   accepted but the version never reaches status `default`, naming any leftover
   `Gem.Temporary.Package` record to delete before retrying (#117).

   This replaces the old rule that pipeline colour was not evidence and the job
   statuses had to be read by hand. That rule existed because a failed publish
   used to leave the pipeline green — which is how `rails-hyperstack` went
   missing from `1.0.alpha1.9` behind eleven green check marks. Colour is now
   evidence. Verifying against the registry is still the strongest check, and
   costs one command:

   ```
   glab api "projects/65/packages?package_type=rubygems&package_name=rails-hyperstack" \
     | grep -o '"version":"<version>"'
   ```
9. Add a new release note (add release in GitLab): copy the CHANGELOG entry.

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
