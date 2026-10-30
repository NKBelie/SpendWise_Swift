# Simulator screenshots

No simulator screenshots have been produced in the Windows development environment.
Do not treat design references or generated mockups as evidence of a running app.

On a Mac, configure Firebase and build the app using `docs/IOS_SETUP.md`. Run it
in a simulator, navigate to each screen, and capture real screenshots:

```bash
bash scripts/capture-screenshot.sh dashboard-light
bash scripts/capture-screenshot.sh transactions
bash scripts/capture-screenshot.sh budgets
bash scripts/capture-screenshot.sh savings
bash scripts/capture-screenshot.sh wallet
bash scripts/capture-screenshot.sh dashboard-dark
```

Use emulator accounts and fictional financial records for shareable screenshots.
Check a small iPhone, a larger iPhone, and iPad layout; include a large Dynamic
Type size and both appearances in the review. Each command captures the screen
currently displayed on the booted simulator.
