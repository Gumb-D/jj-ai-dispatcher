# Test Layout

The executable P3.1 baseline is exposed through npm scripts:

- `npm run test:unit`
- `npm run test:integration`
- `npm run smoke:local`
- `npm test`

`npm run test:smoke` remains as a compatibility alias for `npm run smoke:local`.

The repository currently reuses the existing validation scripts instead of duplicating them under `tests/`. P3.2 coverage is implemented by the scripts documented in `docs/testing.md`; future coverage can add focused test files here when runtime modules are made easier to import directly.
