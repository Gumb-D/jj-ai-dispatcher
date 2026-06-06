# Test Layout

The executable P3.1 baseline is exposed through npm scripts:

- `npm run test:unit`
- `npm run test:integration`
- `npm run test:smoke`
- `npm test`

The repository currently reuses the existing validation scripts instead of duplicating them under `tests/`. Future P3.2 coverage can add focused test files here when runtime modules are made easier to import directly.
