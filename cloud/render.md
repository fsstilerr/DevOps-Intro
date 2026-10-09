# Render deployment

- Platform: Render Web Service
- Plan: Free
- Region: Frankfurt
- Source: existing public GHCR image
- Image: `ghcr.io/fsstilerr/devops-intro/quicknotes:v0.1.1`
- Public URL: `https://quicknotes-lab10-pp1f.onrender.com`
- Health check path: `/health`
- `PORT`: `10000` (provided by Render)
- `ADDR`: `:10000`

QuickNotes initially had an incorrect `ADDR` value (`10000`). It was corrected
to `:10000`, after which the service became healthy.

The release workflow calls the Render deploy hook after publishing the tagged
image. The deploy-hook URL is stored in the GitHub Actions secret
`RENDER_DEPLOY_HOOK_URL` and is not committed to the repository.

The `v0.1.1` release was automatically deployed through the deploy hook.
