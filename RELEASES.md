# Releases

## 2026-09-24: First deploy
- **What deployed:** https://writlog.levelbrook.com (container `writlog`, shared `lb-postgres` db `writlog_production`), seeded with 8 fictional matters, 5 templates.
- **Changed:** initial release. Event-sourced matter workflow, NY deadline rules with holiday rolling, idempotent document generation (Solid Queue async in Puma, Prawn PDFs, Active Storage), communications log, React 19 document composer via importmap.
- **How:** rsync to the box, `docker build`, `docker run --network kamal --memory 300m`, `kamal-proxy deploy --tls`, Cloudflare A record DNS-only.
- **Verified:** see the deploy notes below.
