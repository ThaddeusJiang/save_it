# 2023-09-15

issues: fly deploy --remote-only fails with:

```log
   ** (EXIT) an exception was raised:
          ** (UndefinedFunctionError) function Tesla.Adapter.Hackney.call/2 is undefined (module Tesla.Adapter.Hackney is not available)
```

resolved by

```sh
fly deploy --remote-only --no-cache
```

docs:

- [Continuous Deployment with Fly.io and GitHub Actions · Fly Docs](https://fly.io/docs/app-guides/continuous-deployment-with-github-actions/)
