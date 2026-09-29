# Dashboard-managed Mindroom configuration

During evaluation, let the owner configure Mindroom in its dashboard. Git continues
to own deployment and secret references, while the app owns its live configuration.
This intentionally changes the earlier read-only ConfigMap design.

Use the pinned upstream chart's file config source. A runtime-image init container
copies the existing ConfigMap seed into mindroom-workspace/config/config.yaml only
when absent, then the runtime reads and writes that persistent file. Run the init
container as the runtime's UID/GID. Stage and rename the initial copy so an
interrupted copy does not leave a partial live file. Recreate and one replica
avoid concurrent initialization. No PVC replacement or data migration is needed.

Merge/reconcile to restart the runtime, then confirm the dashboard allows edits.
Save an edit, restart, and confirm it remains. The config directory is included
in the existing whole-workspace offline backup. Git seed edits deliberately have
no effect once initialized. Export and review the live config before any future
return to Git-managed configuration; see the app README for the snapshot command.
