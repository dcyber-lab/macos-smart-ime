# Third-Party Data: rime-ice

The `smartime_pinyin` dictionary imports Chinese tables from
[rime-ice (雾凇拼音)](https://github.com/iDvel/rime-ice) by iDvel and contributors,
licensed under the GNU General Public License v3.0.

- Tables used: `cn_dicts/8105`, `cn_dicts/base`, `cn_dicts/ext`, `cn_dicts/others`
  from commit `3aea6d3694fb3d94ec663641f021f788822897ad` (2026-09-25).
- They are not stored in this repository. `scripts/rime/fetch-rime-ice.sh`
  downloads them at build time, verifies their SHA-256 checksums, and
  `scripts/rime/assemble-shared-data.sh` copies them (with rime-ice's `LICENSE`
  as `cn_dicts/LICENSE.rime-ice`) into `build/rime-data/shared`.
- Distributing a build that includes these tables must comply with GPL-3.0.

The files in this directory (`smartime_pinyin.schema.yaml`,
`smartime_pinyin.dict.yaml`, `default.yaml`) are project-authored; the schema's
speller rules and `default.yaml` derive from the `luna_pinyin` schema and
`default.yaml` in librime's `data/minimal`.
