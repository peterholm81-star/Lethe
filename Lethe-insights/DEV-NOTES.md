# Dev Notes

## Dependencies

### react-simple-maps + React 19

`react-simple-maps@3.0.0` officially supports React 16/17/18, but we run React 19.
This requires special handling:

1. **prop-types**: Must be installed as a runtime dependency (not just dev):
   ```bash
   npm install prop-types
   ```

2. **Vite dedupe**: To prevent "Invalid hook call" errors, `vite.config.ts` must include:
   ```ts
   resolve: {
     dedupe: ['react', 'react-dom'],
   }
   ```

3. **Installation**: Always use `--legacy-peer-deps` when installing:
   ```bash
   npm install --legacy-peer-deps
   ```

4. **Clean install if issues**: If you see "Invalid hook call" in MapProvider:
   ```bash
   # Stop dev server first, then:
   taskkill /F /IM node.exe   # Windows
   rm -rf node_modules package-lock.json
   npm install --legacy-peer-deps
   npm run dev -- --force
   ```

### npm ls output (for reference)

```
letheinsights@0.0.0
+-- react-dom@19.2.4
| `-- react@19.2.4 deduped
+-- react-simple-maps@3.0.0
| +-- react-dom@19.2.4 deduped invalid: "^16.8.0 || 17.x || 18.x"
| `-- react@19.2.4 deduped invalid: "^16.8.0 || 17.x || 18.x"
`-- react@19.2.4
```

The "invalid" warnings are expected due to peer dependency mismatch, but the app
works correctly with the dedupe configuration.
