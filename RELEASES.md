# Releases

## 2026-09-24: First deploy
- **What deployed:** https://writlog.levelbrook.com (container `writlog`, shared `lb-postgres` db `writlog_production`), seeded with 8 fictional matters, 5 templates.
- **Changed:** initial release. Event-sourced matter workflow, NY deadline rules with holiday rolling, idempotent document generation (Solid Queue async in Puma, Prawn PDFs, Active Storage), communications log, React 19 document composer via importmap.
- **How:** rsync to the box, `docker build`, `docker run --network kamal --memory 300m -v writlog_storage:/rails/storage`, `db:seed`, `kamal-proxy deploy --tls`, Cloudflare A record DNS-only.
- **Fixed during deploy:** image now ships `psql` (Rails 8.1 loads `structure.sql` into an empty database with it) and creates `storage/` as the app user (a root-owned volume made every PDF upload fail; `retry_on` surfaced it). Failed documents are now requeued when requested again instead of blocking their inputs.
- **Verified:** `/`, matter, deadlines, how-it-works and document pages return 200 over TLS. 12 concurrent POSTs for one document returned one 201 and eleven 200s, produced one row, one `document_generated` event and a PDF served as `application/pdf`. The React composer's "generate twice at once" returned 201 + 200 with the same id and the job finished within seconds. All seeded matters pass the replay check. 32 tests green locally. Container ~131 MB of its 300 MB cap.
