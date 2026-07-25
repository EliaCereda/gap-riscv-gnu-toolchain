# Draft bug report for prefix.dev (sharded repodata)

**Where to file:** https://github.com/prefix-dev/prefix.dev/issues (no existing
issue matches — searched stale-repodata / shard-404 terms on 2026-07-25).

---

**Title:** Sharded repodata shards return 404 (HTML body) for channel while
shard index is served and updating — breaks `pixi add`

**Body:**

Channel: `eliacereda` (created private, later switched to public — possibly
relevant, since public channels like conda-forge shard fine).

Uploads to the channel succeed (`rattler-build upload prefix` with OIDC
trusted publishing from GitHub Actions) and packages appear in the web UI and,
after the periodic regeneration, in the plain `repodata.json`. The sharded
repodata however is broken:

- `https://shards.prefix.dev/eliacereda/linux-64/repodata_shards.msgpack.zst`
  returns **HTTP 404 with an HTML error page body** (~27 KB SPA shell).
- pixi (which prefers sharded repodata) fetches a shard index successfully,
  then gets **404 on every referenced shard**, e.g.
  `https://shards.prefix.dev/eliacereda/3701258aaf15af0c5d2794744803abaf828d8bf2037680d0f9e9167b0809337a.msgpack.zst`.
  After a later package upload the referenced hash changed to
  `747e605be2f5ceaa31f4e387a52fce4071bd1089a692f07d57605952bdb0cf90` — so the
  index is being regenerated server-side — and the new shard 404s as well.
- Net effect: `pixi add gap-riscv-gnu-toolchain` fails with
  `HTTP status client error (404 Not Found) for url (https://shards.prefix.dev/eliacereda/<hash>.msgpack.zst)`
  even though the package is published and visible. Reproduced with a fully
  cleared rattler cache and via `pixi search` as well.

Everything works with sharded repodata disabled client-side:

```toml
[repodata-config."https://prefix.dev"]
disable-sharded = true
```

With that config `pixi add` resolves and installs correctly from the plain
`repodata.json`.

Timeline (CEST, 2026-07-24/25):
- ~23:00 packages uploaded (workflow upload job green, OIDC).
- ~23:10-23:40 `pixi add` fails on shard 404 (hash `3701258a…`).
- ~00:30 channel switched private → public; anonymous plain repodata works
  from then on; shard 404 unchanged.
- ~02:00 after a second upload the referenced shard hash changed
  (`747e605b…`) and still 404s.
