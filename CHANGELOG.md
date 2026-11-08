# Changelog

All notable changes to this project are documented here. release-please writes
each section from the commit messages, and versions follow
[SemVer](https://semver.org/).

## [0.2.0](https://github.com/wearhats/hats/compare/v0.1.2...v0.2.0) (2026-11-08)


### Features

* always print every key in --json output ([#23](https://github.com/wearhats/hats/issues/23)) ([435ca02](https://github.com/wearhats/hats/commit/435ca02762245566f17220a7739b14580a424587))
* show launchers in Finder's Applications folder ([#37](https://github.com/wearhats/hats/issues/37)) ([889617c](https://github.com/wearhats/hats/commit/889617c66dd0fdc77858467e9d881b75ea6d9eeb))
* **site:** count install copies and outbound clicks with Umami ([#43](https://github.com/wearhats/hats/issues/43)) ([c01af36](https://github.com/wearhats/hats/commit/c01af366f1324a7e08c6af93feff487cdac01b72))


### Bug Fixes

* refuse launcher rebuild default ([#29](https://github.com/wearhats/hats/issues/29)) ([f5ba789](https://github.com/wearhats/hats/commit/f5ba789e4c41b26fca4eda25e103b8f106c96de3))
* resolve tilde paths against HOME and refuse paths that escape ([#22](https://github.com/wearhats/hats/issues/22)) ([1958df9](https://github.com/wearhats/hats/commit/1958df932961ddbc2c0651e5cf58e84d9d45a59c))

## [0.1.2](https://github.com/wearhats/hats/compare/v0.1.1...v0.1.2) (2026-11-02)


### Features

* add one-letter command shortcuts ([#17](https://github.com/wearhats/hats/issues/17)) ([4966317](https://github.com/wearhats/hats/commit/4966317311bf0716690b212589d58c56d72eb3fc))
* add per-profile shortcuts ([#19](https://github.com/wearhats/hats/issues/19)) ([3be110f](https://github.com/wearhats/hats/commit/3be110f6d7255123f2b8d7a7d9fba89c406c10f7))
* show profile dirs with hats ls --paths ([#20](https://github.com/wearhats/hats/issues/20)) ([14754db](https://github.com/wearhats/hats/commit/14754dbf1bba9b41ea61f34a89a897ddd4ecc529))

## [0.1.1](https://github.com/wearhats/hats/compare/hats-v0.1.0...v0.1.1) (2026-11-02)


### Bug Fixes

* tag releases v&lt;version&gt; and stop assuming the tag format ([#12](https://github.com/wearhats/hats/issues/12)) ([52580bb](https://github.com/wearhats/hats/commit/52580bbfd7986a3a77e87511738b05d1e42da9b0))

## 0.1.0 (2026-11-02)


### Features

* initial public release of hats ([10c6b91](https://github.com/wearhats/hats/commit/10c6b9187ee6703b1d5a25687a5abdaae4261ff0))
* show how to upgrade in hats doctor ([#8](https://github.com/wearhats/hats/issues/8)) ([557c53a](https://github.com/wearhats/hats/commit/557c53a793454007c93b500901ad95ee328964c4))
* warn when a newer release is available ([#9](https://github.com/wearhats/hats/issues/9)) ([d9bc6c3](https://github.com/wearhats/hats/commit/d9bc6c31c7bda40fb27c968ce7463d04f1579c23))


### Bug Fixes

* harden release packaging and correct the provenance claim ([#10](https://github.com/wearhats/hats/issues/10)) ([59c274d](https://github.com/wearhats/hats/commit/59c274d5b3920884fdd6d711185f6f3e407f814c))
